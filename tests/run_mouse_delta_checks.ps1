param([string]$VivadoBin = 'C:/AMDDesignTools/2025.2/Vivado/bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $repoRoot 'build/mouse_delta_checks'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
Push-Location -LiteralPath $outputDir
try {
    # The byte-level Ps2Interface stand-in must stay in this isolated library.
    & (Join-Path $VivadoBin 'xvhdl.bat') --2008 `
        (Join-Path $repoRoot 'FDP2026.srcs/sources_1/new/Mouse_Control_Delta.vhd') `
        (Join-Path $PSScriptRoot 'mouse_delta_tb.vhd')
    if ($LASTEXITCODE -ne 0) { throw 'VHDL compilation failed' }
    & (Join-Path $VivadoBin 'xelab.bat') mouse_delta_tb -s mouse_delta_tb
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') mouse_delta_tb -R -log mouse_delta_tb.log
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    if (!(Select-String -LiteralPath 'mouse_delta_tb.log' -Pattern 'PASS:' -Quiet)) {
        throw 'Simulation did not report PASS'
    }
} finally { Pop-Location }
