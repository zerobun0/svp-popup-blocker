<#
.SYNOPSIS
    Installs svp-popup-blocker to run now and on every login.
#>

$scriptPath = Join-Path $PSScriptRoot "svp-popup-blocker.ps1"
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "SVP Popup Blocker.lnk"

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcutPath)
$lnk.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.Save()

Write-Host "Installed. Starting it now..."
Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`""

Write-Host "Done. It will also start automatically the next time you log in."
Write-Host "To remove it later, run uninstall.ps1."
