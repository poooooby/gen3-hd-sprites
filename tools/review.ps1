# The review sheet (tests/drivers/review.lua): every model Battle Scene stands - buildings, rooms,
# trees, caves - proved against the game's own drawing at 45 degrees, gathered into one page that
# opens in the browser. Mark each item "looks fine" / "needs work" with a note, then "copy my notes".
#   .\tools\review.ps1                                  # FireRed, everything
#   .\tools\review.ps1 -Game leafgreen -Kinds room,cave
#   .\tools\review.ps1 -Engine D:\gen1recomp -Love "C:\Program Files\LOVE\love.exe"
# The engine must load this mod (its mods\gen3-hd-sprites linked to this folder) and have the game
# imported. The sheets show the game's own art: they stay in %TEMP%\woobleview-review\<game>.
param(
  [string]$Game = "firered",
  [string]$Kinds = "",
  [int]$Shots = 10,
  [string]$Engine = (Join-Path $PSScriptRoot "..\..\gen1recomp"),
  [string]$Love = "C:\Program Files\LOVE\lovec.exe"
)
$engine = (Resolve-Path $Engine).Path
if (-not (Test-Path (Join-Path $engine "mods\gen3-hd-sprites\tests\drivers\review.lua"))) {
  Write-Error "The engine at $engine does not load this mod (mods\gen3-hd-sprites)."
  exit 1
}
$out = Join-Path $env:TEMP (Join-Path "woobleview-review" $Game)
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $out -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force
$env:POKEPORT_GAME = $Game
$env:POKEPORT_VERSION = $Game
$env:POKEPORT_DRIVER = "mods/gen3-hd-sprites/tests/drivers/review.lua"
$env:POKEPORT_BACKGROUND = "1"
$env:REVIEW_KINDS = $Kinds
$env:REVIEW_SHOTS = "$Shots"
$env:SHOT_DIR = $out
Write-Host "Building the review sheet (a few minutes)..."
Push-Location $engine
try { & $Love . | Out-Null } finally {
  Pop-Location
  Remove-Item Env:POKEPORT_DRIVER, Env:POKEPORT_BACKGROUND, Env:REVIEW_KINDS, Env:REVIEW_SHOTS, Env:SHOT_DIR -ErrorAction SilentlyContinue
}
$page = Join-Path $out "index.html"
if (Test-Path $page) {
  Get-Content (Join-Path $out "driver.log") -Tail 1
  Start-Process $page
} else {
  Write-Error "No page was written; see $(Join-Path $out 'driver.log')."
}
