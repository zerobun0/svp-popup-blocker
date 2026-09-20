<#
.SYNOPSIS
    Instantly and silently closes SVP4's "SVP - Activation" nag dialog
    without touching SVP itself.

.DESCRIPTION
    SVP (SmoothVideo Project) periodically shows an "Activation" dialog
    nagging unregistered/unlicensed installs to purchase a license. This
    script watches for that specific window and closes it the moment it
    appears, so SVP keeps running and smoothing your video normally with
    no interruption.

    It uses SetWinEventHook(EVENT_OBJECT_SHOW) rather than a polling loop,
    so Windows calls back the instant the window is created instead of up
    to a poll-interval later — the dialog is closed within milliseconds.

    It closes the window with PostMessage(WM_CLOSE) rather than
    SetForegroundWindow + SendKeys, because:
      - PostMessage doesn't require focus, so it works even while a
        fullscreen video player has focus (SetForegroundWindow can
        silently fail against Windows' foreground-lock protection).
      - WM_CLOSE just dismisses the dialog like clicking the X, without
        risk of accidentally triggering a "Buy"/"Evaluate" button.

.NOTES
    Run install.ps1 to have this start automatically at login.
#>

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class SvpHook {
    public delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll")]
    public static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc, WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern IntPtr PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

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

# Kept alive in a variable for the whole run, or the GC will collect the
# delegate and crash the native callback.
$script:callback = [SvpHook+WinEventDelegate]{
    param($hWinEventHook, $eventType, $hwnd, $idObject, $idChild, $dwEventThread, $dwmsEventTime)

    if ($idObject -ne [SvpHook]::OBJID_WINDOW -or $idChild -ne 0 -or $hwnd -eq [IntPtr]::Zero) {
        return
    }

    $sbTitle = New-Object System.Text.StringBuilder 256
    [SvpHook]::GetWindowText($hwnd, $sbTitle, 256) | Out-Null
    if ($sbTitle.ToString() -eq "SVP - Activation") {
        [SvpHook]::PostMessage($hwnd, [SvpHook]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Log "Closed activation dialog (hwnd=$hwnd)."
    }
}

Log "svp-popup-blocker started."

$hook = [SvpHook]::SetWinEventHook(
    [SvpHook]::EVENT_OBJECT_SHOW,
    [SvpHook]::EVENT_OBJECT_SHOW,
    [IntPtr]::Zero,
    $script:callback,
    0,
    0,
    [SvpHook]::WINEVENT_OUTOFCONTEXT
)

if ($hook -eq [IntPtr]::Zero) {
    Log "ERROR: SetWinEventHook failed."
    exit 1
}

[System.Windows.Forms.Application]::Run()
