# SVP Popup Blocker

A tiny Windows tray utility that instantly closes SVP4's `SVP - Activation`
nag dialog, without stopping or interfering with SVP itself.

[SVP (SmoothVideo Project)](https://www.svp-team.com/) is popular for
real-time video frame interpolation (smoother playback via AI-based frame
generation). On unregistered/unlicensed installs, it periodically pops up
an "Activation" dialog during playback asking you to purchase a license.
This tool closes that dialog automatically the moment it appears, so SVP
keeps running and interpolating your video normally with no interruption
to playback.

## Download

Grab `SvpPopupBlocker.exe` from the
[latest release](https://github.com/zerobun0/svp-popup-blocker/releases/latest),
put it in its own folder along with `install.ps1`, then run:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

It copies itself to `%LOCALAPPDATA%\SvpPopupBlocker\`, starts immediately,
and registers itself to launch automatically at every login.

To remove it:

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

## What it looks like

A shield icon sits in the system tray the whole time it's running: blue
with a checkmark while active, gray with pause bars if you pause it, red
with an X if it failed to start. Right-click it for:

- A live count of popups blocked this session
- `Open Log`
- `Enabled` checkbox, to pause/resume without exiting
- `Exit`

A notification balloon fires each time it blocks a popup, and a warning
balloon fires if a close attempt ever fails.

## How it works

- Uses `SetWinEventHook(EVENT_OBJECT_SHOW)` instead of polling. Windows
  calls back the instant the window is created, so the dialog is closed
  within milliseconds instead of up to a poll-interval later.
- Closes the window with `PostMessage(WM_CLOSE)` rather than
  `SetForegroundWindow` + simulated keystrokes:
  - `PostMessage` doesn't require focus, so it works even while a
    fullscreen video player has focus (`SetForegroundWindow` can silently
    fail against Windows' foreground-lock protection).
  - `WM_CLOSE` just dismisses the dialog like clicking the X, with no
    risk of accidentally triggering a "Buy" / "Evaluate" button.
- Only ever matches the exact window title `SVP - Activation`. There is no
  process-killing logic anywhere in this codebase; it doesn't touch,
  modify, or interact with SVP, Harbor, or any player in any other way.
- After sending `WM_CLOSE`, it checks that the window actually closed
  (`IsWindow`) instead of assuming the message worked, so you get an
  accurate "blocked" or "failed" notification either way.
- Ships as a compiled `-noConsole` executable (built with
  [ps2exe](https://github.com/MScholtes/PS2EXE)), so it's a real Windows
  GUI-subsystem binary with no console of its own. Windows' "default
  terminal application" feature only intercepts new console windows, so
  it never applies here, meaning no Windows Terminal tab, flash or
  otherwise, at any point, including at login.
- Runs via a hidden Scheduled Task triggered at logon.

## Building from source

Requires the [ps2exe](https://www.powershellgallery.com/packages/ps2exe)
module (`build.ps1` installs it automatically if missing).

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

Produces `dist\SvpPopupBlocker.exe` from `src\svp-popup-blocker.ps1`.

## Repo layout

| Path | Purpose |
|---|---|
| `src/svp-popup-blocker.ps1` | source script |
| `build.ps1` | compiles src into `dist/SvpPopupBlocker.exe` |
| `install.ps1` | installs the exe and registers the scheduled task |
| `uninstall.ps1` | removes both, and the installed copy |

## Requirements

- Windows 10/11
- SVP 4

## License

MIT
