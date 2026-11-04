param([string]$VivadoBin = 'C:\AMDDesignTools\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$runDir = Join-Path $repoRoot 'build/enemy_sim'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$sourceRoot = Join-Path $repoRoot 'FDP2026.srcs/sources_1/new'
Push-Location $runDir
try {
    & "$VivadoBin/xvlog.bat" "$sourceRoot/enemy/enemy_manager.v" `
        "$sourceRoot/enemy/flow_field.v" `
        "$sourceRoot/enemy/enemy_combat.v" `
        "$sourceRoot/enemy/zombie_renderer.v" "$sourceRoot/demo/demo_wall_view.v" `
        "$sourceRoot/game/wave_controller.v" "$sourceRoot/game/spawn_finder.v" `
        "$sourceRoot/game/player_health.v" "$sourceRoot/ui/weapon_ctrl.v" `
        "$sourceRoot/map/lfsr16.v" "$PSScriptRoot/tb_enemy_manager.v" `
        "$PSScriptRoot/tb_enemy_waves.v" "$PSScriptRoot/tb_zombie_renderer.v"
    if ($LASTEXITCODE -ne 0) { throw 'Verilog compilation failed' }
    foreach ($testTop in @('tb_enemy_manager', 'tb_enemy_waves', 'tb_zombie_renderer')) {
        & "$VivadoBin/xelab.bat" $testTop -s $testTop
        if ($LASTEXITCODE -ne 0) { throw "Elaboration failed: $testTop" }
        $simOutput = & "$VivadoBin/xsim.bat" $testTop -R 2>&1
        $simExit = $LASTEXITCODE
        $simOutput | Write-Output
        if ($simExit -ne 0 -or !($simOutput -match ($testTop.ToUpper() + ': PASS'))) {
            throw "Simulation failed: $testTop"
        }
    }
} finally { Pop-Location }
