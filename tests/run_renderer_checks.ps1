param(
    [string]$VivadoBin = 'C:/AMDDesignTools/2025.2/Vivado/bin',
    [switch]$Hardware,
    [string[]]$Tests = @('ray_caster_tb', 'map_renderer_tb', 'clock_enable_tb', 'player_controller_tb', 'mouse_top_tb', 'oled_renderer_tb', 'mouse_pointer_tb', 'runtime_map_tb')
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $repoRoot 'build/renderer_checks'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$sourceDir = Join-Path $repoRoot 'FDP2026.srcs/sources_1/new'
& python (Join-Path $PSScriptRoot 'generate_ray_vectors.py')
if ($LASTEXITCODE -ne 0) { throw 'Reference generation failed' }
$sources = @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File -Filter '*.v' | ForEach-Object { $_.FullName })
$vhdlSources = @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File -Filter '*.vhd' | ForEach-Object { $_.FullName })
$testNames = $Tests
$testFiles = @($testNames | ForEach-Object { Join-Path $PSScriptRoot "${_}.sv" })
Push-Location -LiteralPath $outputDir
try {
    & (Join-Path $VivadoBin 'xvhdl.bat') @vhdlSources
    if ($LASTEXITCODE -ne 0) { throw 'VHDL compilation failed' }
    & (Join-Path $VivadoBin 'xvlog.bat') --sv -i $sourceDir @sources @testFiles
    if ($LASTEXITCODE -ne 0) { throw 'Verilog compilation failed' }
    foreach ($test in $testNames) {
        & (Join-Path $VivadoBin 'xelab.bat') $test -L unisims_ver -s $test --timescale 1ns/1ps
        if ($LASTEXITCODE -ne 0) { throw "Elaboration failed: $test" }
        & (Join-Path $VivadoBin 'xsim.bat') $test -R -log "${test}.log"
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $test" }
        if (!(Select-String -LiteralPath "${test}.log" -Pattern '^PASS:' -Quiet)) {
            throw "Simulation did not report PASS: $test"
        }
    }
} finally { Pop-Location }
if ($Hardware) {
    $hardwareDir = Join-Path $repoRoot 'build/renderer_hardware'
    New-Item -ItemType Directory -Force -Path $hardwareDir | Out-Null
    & (Join-Path $VivadoBin 'vivado.bat') -mode batch `
        -source (Join-Path $PSScriptRoot 'check_renderer_hardware.tcl') `
        -log (Join-Path $hardwareDir 'vivado.log') `
        -journal (Join-Path $hardwareDir 'vivado.jou') `
        -tclargs ($repoRoot.Replace('\','/'))
    if ($LASTEXITCODE -ne 0) { throw 'Hardware validation failed' }
}
