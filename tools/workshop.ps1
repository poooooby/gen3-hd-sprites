# The Scene Workshop (tests/drivers/workshop.lua): Battle Scene's world around a spot, to look round
# and tune its models by eye. Saves go to src/scene/games/<game>_tune.lua in this mod.
#   .\tools\workshop.ps1                                  # FireRed, Route 2
#   .\tools\workshop.ps1 -Game firered -Spot FR_VIRIDIAN_FOREST:20:40
#   .\tools\workshop.ps1 -Engine D:\gen1recomp -Love "C:\Program Files\LOVE\love.exe"
# The engine must load this mod (its mods\gen3-hd-sprites linked to this folder) and have the game
# imported. Battle Scene is on for the session only; no option or save is changed.
param(
  [string]$Game = "firered",
  [string]$Spot = "",
  [string]$Engine = (Join-Path $PSScriptRoot "..\..\gen1recomp"),
  [string]$Love = "C:\Program Files\LOVE\lovec.exe"
)
$engine = (Resolve-Path $Engine).Path
if (-not (Test-Path (Join-Path $engine "mods\gen3-hd-sprites\tests\drivers\workshop.lua"))) {
  Write-Error "The engine at $engine does not load this mod (mods\gen3-hd-sprites)."
  exit 1
}
$env:POKEPORT_GAME = $Game
$env:POKEPORT_VERSION = $Game
$env:POKEPORT_DRIVER = "mods/gen3-hd-sprites/tests/drivers/workshop.lua"
$env:WORKSHOP_SPOT = $Spot
$shots = Join-Path $env:TEMP "woobleview-workshop"
New-Item -ItemType Directory -Force $shots | Out-Null
$env:SHOT_DIR = $shots   # (its log and F12 screenshots)
Push-Location $engine
try { & $Love . } finally {
  Pop-Location
  Remove-Item Env:POKEPORT_DRIVER, Env:WORKSHOP_SPOT, Env:SHOT_DIR -ErrorAction SilentlyContinue
}
