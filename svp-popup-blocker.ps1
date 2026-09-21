<#
.SYNOPSIS
    Instantly closes SVP4's "SVP - Activation" nag dialog without touching
    SVP itself, with a system tray icon to show it's running.

.DESCRIPTION
    SVP (SmoothVideo Project) periodically shows an "Activation" dialog
    nagging unregistered/unlicensed installs to purchase a license. This
    script watches for that specific window and closes it the moment it
    appears, so SVP keeps running and smoothing your video normally with
    no interruption.

    It uses SetWinEventHook(EVENT_OBJECT_SHOW) rather than a polling loop,
    so Windows calls back the instant the window is created instead of up
    to a poll-interval later - the dialog is closed within milliseconds.

    It closes the window with PostMessage(WM_CLOSE) rather than
    SetForegroundWindow + SendKeys, because:
     - PostMessage doesn't require focus, so it works even while a
        fullscreen video player has focus (SetForegroundWindow can
        silently fail against Windows' foreground-lock protection).
     - WM_CLOSE just dismisses the dialog like clicking the X, without
        risk of accidentally triggering a "Buy"/"Evaluate" button.

    It only ever matches the exact window title "SVP - Activation" - it
    has no code path that touches SVP's actual playback/smoothing window,
    Harbor, mpv, or any other process. There is no process-killing logic
    anywhere in this script; the only Win32 call that affects another
    window is the single PostMessage(WM_CLOSE) guarded by that exact
    title match.

    A tray icon shows it's alive. Right-click it for:
     - "Enabled" checkbox - pauses/resumes blocking without exiting.
     - "Exit" - stops this instance (restarts automatically next login).
    A balloon notification fires each time a popup is blocked, and a
    warning notification fires if closing it ever fails.

.NOTES
    Run install.ps1 to have this start automatically at login.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class SvpHook {
    public delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll")]
    public static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc, WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern IntPtr PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    public const uint EVENT_OBJECT_SHOW = 0x8002;
    public const uint WINEVENT_OUTOFCONTEXT = 0x0000;
    public const uint WM_CLOSE = 0x0010;
    public const int OBJID_WINDOW = 0;
}
"@

$logPath = Join-Path $PSScriptRoot "svp-popup-blocker.log"
function Log($msg) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" | Out-File -FilePath $logPath -Append -Encoding utf8
}

# --- Tray icon ---------------------------------------------------------

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
try {
    $svpExe = "C:\Program Files\SVP 4\SVPManagerLauncher.exe"
    $notifyIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($svpExe)
} catch {
    $notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
}
$notifyIcon.Text = "SVP Popup Blocker (active)"

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem "SVP Popup Blocker"
$statusItem.Enabled = $false
$menu.Items.Add($statusItem) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$enabledItem = New-Object System.Windows.Forms.ToolStripMenuItem "Enabled"
$enabledItem.CheckOnClick = $true
$enabledItem.Checked = $true
$menu.Items.Add($enabledItem) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem "Exit"
$menu.Items.Add($exitItem) | Out-Null

$notifyIcon.ContextMenuStrip = $menu
$notifyIcon.Visible = $true

$script:enabled = $true
$enabledItem.add_CheckedChanged({
    $script:enabled = $enabledItem.Checked
    $notifyIcon.Text = if ($script:enabled) { "SVP Popup Blocker (active)" } else { "SVP Popup Blocker (paused)" }
    Log $(if ($script:enabled) { "Enabled via tray menu." } else { "Paused via tray menu." })
})

$exitItem.add_Click({
    Log "Exiting via tray menu."
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    if ($script:hook -ne [IntPtr]::Zero) {
        [SvpHook]::UnhookWinEvent($script:hook) | Out-Null
    }
    [System.Windows.Forms.Application]::Exit()
})

function Notify($title, $msg, $iconKind) {
    $notifyIcon.BalloonTipTitle = $title
    $notifyIcon.BalloonTipText = $msg
    $notifyIcon.BalloonTipIcon = $iconKind
    $notifyIcon.ShowBalloonTip(4000)
}

# --- Popup watcher -------------------------------------------------------

# Kept alive in a variable for the whole run, or the GC will collect the
# delegate and crash the native callback.
$script:callback = [SvpHook+WinEventDelegate]{
    param($hWinEventHook, $eventType, $hwnd, $idObject, $idChild, $dwEventThread, $dwmsEventTime)

    if ($idObject -ne [SvpHook]::OBJID_WINDOW -or $idChild -ne 0 -or $hwnd -eq [IntPtr]::Zero) {
        return
    }

    $sbTitle = New-Object System.Text.StringBuilder 256
    [SvpHook]::GetWindowText($hwnd, $sbTitle, 256) | Out-Null
    if ($sbTitle.ToString() -ne "SVP - Activation") {
        return
    }

    if (-not $script:enabled) {
        Log "Saw activation dialog (hwnd=$hwnd) but blocking is paused - left it open."
        return
    }

    [SvpHook]::PostMessage($hwnd, [SvpHook]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null

    # PostMessage is async - give Windows a moment to actually destroy the
    # window, then confirm it's really gone rather than assuming success.
    Start-Sleep -Milliseconds 150
    if ([SvpHook]::IsWindow($hwnd)) {
        Log "FAILED to close activation dialog (hwnd=$hwnd) - still open after WM_CLOSE."
        Notify "SVP Popup Blocker" "Couldn't auto-close the activation popup - you may need to dismiss it manually." ([System.Windows.Forms.ToolTipIcon]::Warning)
    } else {
        Log "Closed activation dialog (hwnd=$hwnd)."
        Notify "SVP Popup Blocker" "Blocked an SVP activation popup." ([System.Windows.Forms.ToolTipIcon]::Info)
    }
}

Log "svp-popup-blocker started."

$script:hook = [SvpHook]::SetWinEventHook(
    [SvpHook]::EVENT_OBJECT_SHOW,
    [SvpHook]::EVENT_OBJECT_SHOW,
    [IntPtr]::Zero,
    $script:callback,
    0,
    0,
    [SvpHook]::WINEVENT_OUTOFCONTEXT
)

if ($script:hook -eq [IntPtr]::Zero) {
    Log "ERROR: SetWinEventHook failed."
    $notifyIcon.Icon = [System.Drawing.SystemIcons]::Error
    $notifyIcon.Text = "SVP Popup Blocker (FAILED TO START)"
    $enabledItem.Enabled = $false
    Notify "SVP Popup Blocker" "Failed to start - popup blocking is NOT active. Try Exit and restart from Task Scheduler." ([System.Windows.Forms.ToolTipIcon]::Error)
}

[System.Windows.Forms.Application]::Run()
