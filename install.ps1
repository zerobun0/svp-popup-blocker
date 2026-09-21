<#
.SYNOPSIS
    Installs svp-popup-blocker to run now and on every login.

.NOTES
    Runs via a hidden Scheduled Task whose action launches run-hidden.vbs
    (wscript.exe), not powershell.exe directly.

    powershell.exe -WindowStyle Hidden, even from a Hidden scheduled task,
    is not reliably immune to Windows' "default terminal application"
    delegation - under some timing conditions (notably right at logon) it
    still gets handed to Windows Terminal as a visible tab before the
    hidden style takes effect, and if that tab is then closed by hand it
    kills the watcher process, silently disabling popup-dismissal.

    wscript.exe is a GUI-subsystem process with no console of its own.
    Its WshShell.Run(..., 0, True) call creates the child console already
    hidden, which Windows' terminal delegation explicitly skips - so no
    tab is ever created, not just hidden after a flash. The True (wait)
    also keeps wscript.exe alive for the watcher's whole lifetime, so
    Task Scheduler doesn't reap it early.
#>

$vbsPath = Join-Path $PSScriptRoot "run-hidden.vbs"
$taskName = "SVP Popup Blocker"

# Remove a v1 Startup-folder install if present, so it doesn't also launch
# and cause a double-run.
$startupDir = [Environment]::GetFolderPath("Startup")
$legacyShortcut = Join-Path $startupDir "SVP Popup Blocker.lnk"
if (Test-Path $legacyShortcut) {
    Remove-Item $legacyShortcut -Force
}

$action = New-ScheduledTaskAction -Execute "wscript.exe" `
    -Argument "`"$vbsPath`"" `
    -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description "Instantly closes SVP4's activation nag dialog. Runs hidden via Task Scheduler + wscript.exe to avoid any terminal window." | Out-Null

Write-Host "Installed. Starting it now..."
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "svp-popup-blocker\.ps1" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-ScheduledTask -TaskName $taskName

Write-Host "Done. It will also start automatically the next time you log in."
Write-Host "To remove it later, run uninstall.ps1."
