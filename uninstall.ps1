<#
.SYNOPSIS
    Stops SVP Popup Blocker and removes it from login startup.
#>

$taskName = "SVP Popup Blocker"
$installDir = Join-Path $env:LOCALAPPDATA "SvpPopupBlocker"

Get-CimInstance Win32_Process -Filter "Name='powershell.exe' or Name='SvpPopupBlocker.exe'" |
    Where-Object { $_.CommandLine -match "svp-popup-blocker\.ps1" -or $_.CommandLine -match "SvpPopupBlocker\.exe" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# Remove older install methods if present.
$startupDir = [Environment]::GetFolderPath("Startup")
$legacyShortcut = Join-Path $startupDir "SVP Popup Blocker.lnk"
if (Test-Path $legacyShortcut) {
    Remove-Item $legacyShortcut -Force
}

if (Test-Path $installDir) {
    Remove-Item -Path $installDir -Recurse -Force
}

Write-Host "SVP Popup Blocker stopped and removed from startup."
