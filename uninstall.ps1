<#
.SYNOPSIS
    Stops svp-popup-blocker and removes it from login startup.
#>

$taskName = "SVP Popup Blocker"
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "SVP Popup Blocker.lnk"

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "svp-popup-blocker\.ps1" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# Remove a v1 Startup-folder install if present.
if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
}

Write-Host "svp-popup-blocker stopped and removed from startup."
