<#
.SYNOPSIS
    Installs svp-popup-blocker to run now and on every login.

.NOTES
    Runs via a hidden Scheduled Task rather than a Startup-folder shortcut.
    A Startup shortcut launching powershell.exe with -WindowStyle Hidden
    can still cause a Windows Terminal tab to flash briefly at login on
    current Windows builds, because terminal delegation creates the tab
    before the hidden style takes effect. A Scheduled Task with -Hidden
    settings never allocates a console/terminal window in the first
    place, so there's no flash regardless of terminal delegation settings.
#>

$scriptPath = Join-Path $PSScriptRoot "svp-popup-blocker.ps1"
$taskName = "SVP Popup Blocker"

# Remove a v1 Startup-folder install if present, so it doesn't also launch
# and cause a double-run.
$startupDir = [Environment]::GetFolderPath("Startup")
$legacyShortcut = Join-Path $startupDir "SVP Popup Blocker.lnk"
if (Test-Path $legacyShortcut) {
    Remove-Item $legacyShortcut -Force
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
    -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description "Instantly closes SVP4's activation nag dialog. Runs hidden via Task Scheduler to avoid a terminal window flash." | Out-Null

Write-Host "Installed. Starting it now..."
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "svp-popup-blocker\.ps1" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-ScheduledTask -TaskName $taskName

Write-Host "Done. It will also start automatically the next time you log in."
Write-Host "To remove it later, run uninstall.ps1."
