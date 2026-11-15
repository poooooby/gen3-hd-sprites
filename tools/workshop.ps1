# The Scene Workshop (tests/drivers/workshop.lua): Battle Scene's world around a spot, to look round
# and tune its models by eye. Saves go to src/scene/games/<game>_tune.lua in this mod.
#   .\tools\workshop.ps1                                  # FireRed, Route 2
#   .\tools\workshop.ps1 -Game firered -Spot FR_VIRIDIAN_FOREST:20:40
#   .\tools\workshop.ps1 -Spot FR_CERULEAN_CITY:22:22 -Select 22,17   # that cell selected, its check open
#   .\tools\workshop.ps1 -Engine D:\gen1recomp -Love "C:\Program Files\LOVE\love.exe"
# The review page's "Open in workshop" buttons call it with -Url woobleview-workshop:<game>/<spot>/<x,y>
# (tools\register-workshop-link.ps1 registers that link for your Windows user, once).
# The engine must load this mod (its mods\gen3-hd-sprites linked to this folder) and have the game
# imported. Battle Scene is on for the session only; no option or save is changed.
param(
  [string]$Game = "firered",
  [string]$Spot = "",
  [string]$Select = "",
  [string]$Url = "",
  [string]$Engine = (Join-Path $PSScriptRoot "..\..\gen1recomp"),
  [string]$Love = "C:\Program Files\LOVE\lovec.exe"
)
if ($Url -ne "") {
  # woobleview-workshop:<game>/<MAP:x:y>/<x,y> (a browser may add slashes or encode the colons)
  $u = [System.Uri]::UnescapeDataString($Url) -replace '^woobleview-workshop:/*', ''
  $parts = $u.Trim('/') -split '/'
  if ($parts.Count -ge 2 -and $parts[0] -match '^[a-z]+$' -and $parts[1] -match '^[A-Z0-9_]+:\d+:\d+$') {
    $Game = $parts[0]
    $Spot = $parts[1]
    if ($parts.Count -ge 3 -and $parts[2] -match '^-?\d+,-?\d+$') { $Select = $parts[2] }
  } else {
    Write-Error "Not a workshop link: $Url"
    exit 1
  }
}
$engine = (Resolve-Path $Engine).Path
if (-not (Test-Path (Join-Path $engine "mods\gen3-hd-sprites\tests\drivers\workshop.lua"))) {
  Write-Error "The engine at $engine does not load this mod (mods\gen3-hd-sprites)."
  exit 1
}
$env:POKEPORT_GAME = $Game
$env:POKEPORT_VERSION = $Game
$env:POKEPORT_DRIVER = "mods/gen3-hd-sprites/tests/drivers/workshop.lua"
$env:WORKSHOP_SPOT = $Spot
$env:WORKSHOP_SELECT = $Select
$shots = Join-Path $env:TEMP "woobleview-workshop"
New-Item -ItemType Directory -Force $shots | Out-Null
$env:SHOT_DIR = $shots   # (its log and F12 screenshots)
Push-Location $engine
try { & $Love . } finally {
  Pop-Location
  Remove-Item Env:POKEPORT_DRIVER, Env:WORKSHOP_SPOT, Env:WORKSHOP_SELECT, Env:SHOT_DIR -ErrorAction SilentlyContinue
}
