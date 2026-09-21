<#
.SYNOPSIS
    Instantly closes SVP4's "SVP - Activation" nag dialog without touching
    SVP itself. Installs and uninstalls itself; no separate scripts.

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

    The UI is a system tray icon (bottom-right of the taskbar, possibly
    under the "show hidden icons" arrow): blue with a checkmark while
    active, gray with pause bars while paused, red with an X if it failed
    to start. Right-click it for:
     - A live count of popups blocked this session.
     - "Open Log" - opens the log file.
     - "Enabled" checkbox - pauses/resumes blocking without exiting.
     - "Uninstall" - removes the scheduled task and the installed copy.
     - "Exit" - stops this instance (restarts automatically next login).
    A balloon notification fires each time a popup is blocked, and a
    warning notification fires if closing it ever fails.

    On first run from anywhere (e.g. a freshly downloaded exe sitting in
    Downloads), it copies itself to %LOCALAPPDATA%\SvpPopupBlocker\ and
    registers a hidden Scheduled Task pointing there, so it starts
    automatically at every login. No install.ps1/uninstall.ps1 needed.
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

$AppVersion = "1.3.0"
$TaskName = "SVP Popup Blocker"

# Only one instance should ever run at once, so a stray second launch (or
# the freshly-copied installed exe versus the one the user double-clicked)
# doesn't create two tray icons both fighting over the same dialog.
$mutex = New-Object System.Threading.Mutex($false, "SvpPopupBlockerSingleInstance")
if (-not $mutex.WaitOne(0, $false)) {
    exit 0
}

# $PSScriptRoot is empty inside a ps2exe-compiled binary, because the
# script runs as an embedded, dynamically-hosted script block rather than
# actual IL in the exe's own assembly (so GetExecutingAssembly().Location
# doesn't point at the exe either - it resolves to an internal dynamic
# assembly with no meaningful path). The one thing that reliably points
# at the real running exe in that case is the current process itself.
$currentExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ($PSScriptRoot) {
    $scriptDir = $PSScriptRoot
} else {
    $scriptDir = Split-Path -Parent $currentExe
}

$logPath = Join-Path $scriptDir "svp-popup-blocker.log"
function Log($msg) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" | Out-File -FilePath $logPath -Append -Encoding utf8
}

# --- Self-install -----------------------------------------------------

$installDir = Join-Path $env:LOCALAPPDATA "SvpPopupBlocker"
$installedExe = Join-Path $installDir "SvpPopupBlocker.exe"
$isInstalled = $currentExe -eq $installedExe
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if (-not $isInstalled -or -not $existingTask) {
    try {
        if (-not (Test-Path $installDir)) {
            New-Item -ItemType Directory -Path $installDir | Out-Null
        }
        if (-not $isInstalled) {
            Copy-Item -Path $currentExe -Destination $installedExe -Force
            $logPath = Join-Path $installDir "svp-popup-blocker.log"
        }
        $action = New-ScheduledTaskAction -Execute $installedExe -WorkingDirectory $installDir
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
            -Description "Instantly closes SVP4's activation nag dialog. Runs hidden via Task Scheduler." | Out-Null
        Log "Installed to $installedExe and registered login task."
        $script:justInstalled = -not $isInstalled
    } catch {
        Log "ERROR during self-install: $_"
    }
}

# --- Icon -----------------------------------------------------------------

# Drawn at runtime rather than shipped as a file, so the exe stays a
# single portable file with no loose assets.
function New-ShieldIcon([System.Drawing.Color]$Color, [string]$Glyph) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    [System.Drawing.Point[]]$pts = @(
        [System.Drawing.Point]::new(16, 1),
        [System.Drawing.Point]::new(30, 7),
        [System.Drawing.Point]::new(30, 16),
        [System.Drawing.Point]::new(16, 31),
        [System.Drawing.Point]::new(2, 16),
        [System.Drawing.Point]::new(2, 7)
    )
    $path.AddPolygon($pts)
    $brush = New-Object System.Drawing.SolidBrush $Color
    $g.FillPath($brush, $path)
    $pen = New-Object System.Drawing.Pen(([System.Drawing.Color]::FromArgb(60, 0, 0, 0)), 1.5)
    $g.DrawPath($pen, $path)

    $glyphPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3)
    $glyphPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $glyphPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    switch ($Glyph) {
        "check" {
            [System.Drawing.Point[]]$checkPts = @(
                [System.Drawing.Point]::new(9, 16),
                [System.Drawing.Point]::new(14, 22),
                [System.Drawing.Point]::new(23, 10)
            )
            $g.DrawLines($glyphPen, $checkPts)
        }
        "pause" {
            $g.DrawLine($glyphPen, 12, 10, 12, 22)
            $g.DrawLine($glyphPen, 20, 10, 20, 22)
        }
        "x" {
            $g.DrawLine($glyphPen, 10, 10, 22, 22)
            $g.DrawLine($glyphPen, 22, 10, 10, 22)
        }
    }

    $hIcon = $bmp.GetHicon()
    return [System.Drawing.Icon]::FromHandle($hIcon)
}

$ColorActive = [System.Drawing.Color]::FromArgb(41, 128, 185)
$ColorPaused = [System.Drawing.Color]::FromArgb(127, 140, 141)
$ColorFailed = [System.Drawing.Color]::FromArgb(192, 57, 43)

# --- Tray icon --------------------------------------------------------

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = New-ShieldIcon $ColorActive "check"
$notifyIcon.Text = "SVP Popup Blocker (active)"

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$titleItem = New-Object System.Windows.Forms.ToolStripMenuItem "SVP Popup Blocker v$AppVersion"
$titleItem.Enabled = $false
$titleItem.Font = New-Object System.Drawing.Font($titleItem.Font, [System.Drawing.FontStyle]::Bold)
$menu.Items.Add($titleItem) | Out-Null

$counterItem = New-Object System.Windows.Forms.ToolStripMenuItem "Blocked this session: 0"
$counterItem.Enabled = $false
$menu.Items.Add($counterItem) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$enabledItem = New-Object System.Windows.Forms.ToolStripMenuItem "Enabled"
$enabledItem.CheckOnClick = $true
$enabledItem.Checked = $true
$menu.Items.Add($enabledItem) | Out-Null

$logItem = New-Object System.Windows.Forms.ToolStripMenuItem "Open Log"
$menu.Items.Add($logItem) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$uninstallItem = New-Object System.Windows.Forms.ToolStripMenuItem "Uninstall"
$menu.Items.Add($uninstallItem) | Out-Null

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem "Exit"
$menu.Items.Add($exitItem) | Out-Null

$notifyIcon.ContextMenuStrip = $menu
$notifyIcon.Visible = $true

$script:enabled = $true
$script:blockedCount = 0

if ($script:justInstalled) {
    $notifyIcon.BalloonTipTitle = "SVP Popup Blocker"
    $notifyIcon.BalloonTipText = "Installed. It'll start automatically every time you log in. Right-click this icon any time for options."
    $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    $notifyIcon.ShowBalloonTip(6000)
}

$enabledItem.add_CheckedChanged({
    $script:enabled = $enabledItem.Checked
    if ($script:enabled) {
        $notifyIcon.Icon = New-ShieldIcon $ColorActive "check"
        $notifyIcon.Text = "SVP Popup Blocker (active)"
    } else {
        $notifyIcon.Icon = New-ShieldIcon $ColorPaused "pause"
        $notifyIcon.Text = "SVP Popup Blocker (paused)"
    }
    Log $(if ($script:enabled) { "Enabled via tray menu." } else { "Paused via tray menu." })
})

$logItem.add_Click({
    if (-not (Test-Path $logPath)) {
        "" | Out-File -FilePath $logPath -Encoding utf8
    }
    Start-Process notepad.exe -ArgumentList "`"$logPath`""
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

$uninstallItem.add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Remove SVP Popup Blocker and stop it from starting at login?",
        "Uninstall SVP Popup Blocker",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }
    Log "Uninstalling via tray menu."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    if ($script:hook -ne [IntPtr]::Zero) {
        [SvpHook]::UnhookWinEvent($script:hook) | Out-Null
    }
    # The running exe can't delete its own folder while its file handle is
    # open. Hand off to a detached cmd that waits for this process to fully
    # exit, then removes the install folder.
    if ($isInstalled) {
        Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q `"$installDir`"" `
            -WindowStyle Hidden
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
        $script:blockedCount++
        $counterItem.Text = "Blocked this session: $script:blockedCount"
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
    $notifyIcon.Icon = New-ShieldIcon $ColorFailed "x"
    $notifyIcon.Text = "SVP Popup Blocker (FAILED TO START)"
    $enabledItem.Enabled = $false
    Notify "SVP Popup Blocker" "Failed to start - popup blocking is NOT active. Try Exit and run the exe again." ([System.Windows.Forms.ToolTipIcon]::Error)
}

[System.Windows.Forms.Application]::Run()
$mutex.ReleaseMutex()
