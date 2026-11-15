# Registers the "woobleview-workshop:" link for your Windows user, so the review page's "Open in
# workshop" buttons start the Scene Workshop at that item (tools\workshop.ps1 -Url ...). It writes
# only under HKEY_CURRENT_USER\Software\Classes\woobleview-workshop (no admin needed).
#   .\tools\register-workshop-link.ps1           # register (again: it points at this folder)
#   .\tools\register-workshop-link.ps1 -Remove   # take it away
param([switch]$Remove)
$key = "HKCU:\Software\Classes\woobleview-workshop"
if ($Remove) {
  if (Test-Path $key) { Remove-Item -Path $key -Recurse -Force }
  Write-Host "Removed the woobleview-workshop: link."
  exit 0
}
$script = Join-Path $PSScriptRoot "workshop.ps1"
$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`" -Url `"%1`""
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name "(Default)" -Value "URL:WoobleView Scene Workshop"
Set-ItemProperty -Path $key -Name "URL Protocol" -Value ""
New-Item -Path "$key\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$key\shell\open\command" -Name "(Default)" -Value $command
Write-Host "Registered woobleview-workshop: -> $script"
