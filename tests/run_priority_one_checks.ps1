param([string]$VivadoBin='C:/AMDDesignTools/2025.2/Vivado/bin',
    [string[]]$Tests=@('priority_one_tb','tb_uart','tb_packet','tb_multiplayer_link','tb_two_board_game'))
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$sourceDir=Join-Path $repoRoot 'FDP2026.srcs/sources_1/new'
$outputDir=Join-Path $repoRoot 'build/priority_one_sim'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$verilog=@(Get-ChildItem -LiteralPath $sourceDir -Recurse -File -Filter '*.v' | ForEach-Object FullName)
$vhdl=@(Get-ChildItem -LiteralPath $sourceDir -Recurse -File -Filter '*.vhd' | ForEach-Object FullName)
$benches=@((Join-Path $PSScriptRoot 'priority_one_tb.sv'))+
    @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'sim/uart') -Filter '*.v' | ForEach-Object FullName)
Push-Location -LiteralPath $outputDir
try {
    & "$VivadoBin/xvhdl.bat" @vhdl
    if($LASTEXITCODE -ne 0) { throw 'VHDL compile failed' }
    & "$VivadoBin/xvlog.bat" --sv -i $sourceDir @verilog @benches
    if($LASTEXITCODE -ne 0) { throw 'Verilog compile failed' }
    foreach($test in $Tests) {
        & "$VivadoBin/xelab.bat" $test -L unisims_ver -s $test
        if($LASTEXITCODE -ne 0) { throw "Elaboration failed: $test" }
        $result=& "$VivadoBin/xsim.bat" $test -R -log "${test}.log" 2>&1
        $result | Write-Output
        if($LASTEXITCODE -ne 0 -or !($result -match '(^PASS(\s|:|$)|ALL PASSED)') -or
           ($result -match '(^FAIL|FAILED|FATAL|ERROR:)')) { throw "Simulation failed: $test" }
    }
} finally { Pop-Location }
