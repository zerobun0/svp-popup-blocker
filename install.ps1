<#
.SYNOPSIS
    Installs SvpPopupBlocker.exe to run now and on every login.

.DESCRIPTION
    Copies SvpPopupBlocker.exe (expected next to this script, or in
    .\dist) to %LOCALAPPDATA%\SvpPopupBlocker\, then registers a hidden
    Scheduled Task that launches it directly at logon.

    The exe is a compiled ps2exe binary built with -noConsole, so it is a
    true Windows GUI-subsystem executable with no console of its own.
    Windows' "default terminal application" feature only intercepts new
    console windows, so it never applies here at all, and there is no
    Windows Terminal tab, flash or otherwise, at any point.

.NOTES
    Run build.ps1 first if dist\SvpPopupBlocker.exe doesn't exist yet.
#>

$taskName = "SVP Popup Blocker"
$installDir = Join-Path $env:LOCALAPPDATA "SvpPopupBlocker"
$installedExe = Join-Path $installDir "SvpPopupBlocker.exe"

$sourceExe = Join-Path $PSScriptRoot "SvpPopupBlocker.exe"
if (-not (Test-Path $sourceExe)) {
    $sourceExe = Join-Path $PSScriptRoot "dist\SvpPopupBlocker.exe"
}
if (-not (Test-Path $sourceExe)) {
    Write-Error "SvpPopupBlocker.exe not found next to this script or in .\dist. Run build.ps1 first, or download it from the Releases page."
    exit 1
}

# Clean up any earlier install method before installing fresh.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' or Name='SvpPopupBlocker.exe'" |
    Where-Object { $_.CommandLine -match "svp-popup-blocker\.ps1" -or $_.CommandLine -match "SvpPopupBlocker\.exe" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$startupDir = [Environment]::GetFolderPath("Startup")
$legacyShortcut = Join-Path $startupDir "SVP Popup Blocker.lnk"
if (Test-Path $legacyShortcut) {
    Remove-Item $legacyShortcut -Force
}

if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
}
Copy-Item -Path $sourceExe -Destination $installedExe -Force

$action = New-ScheduledTaskAction -Execute $installedExe -WorkingDirectory $installDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description "Instantly closes SVP4's activation nag dialog. Runs hidden via Task Scheduler." | Out-Null

Write-Host "Installed to $installedExe. Starting it now..."
Start-ScheduledTask -TaskName $taskName

Write-Host "Done. It will also start automatically the next time you log in."
Write-Host "To remove it later, run uninstall.ps1."
