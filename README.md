# SVP Popup Blocker

A tiny background utility for Windows that instantly closes SVP4's
`SVP - Activation` nag dialog, without stopping or interfering with SVP
itself.

[SVP (SmoothVideo Project)](https://www.svp-team.com/) is popular for
real-time video frame interpolation (smoother playback via AI-based frame
generation). On unregistered/unlicensed installs, it periodically pops up
an "Activation" dialog during playback asking you to purchase a license.
This tool closes that dialog automatically the moment it appears, so SVP
keeps running and interpolating your video normally with no interruption
to playback.

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
- Only ever matches the exact window title `SVP - Activation`. It doesn't
  touch, modify, or interact with SVP in any other way.
- Runs via a hidden Scheduled Task that launches a `.vbs` wrapper
  (`wscript.exe`) rather than `powershell.exe -WindowStyle Hidden`
  directly, so it never gets handed to Windows Terminal as a visible tab
  - not even briefly, and not even at logon.

## Install

1. Download or clone this repo.
2. Open PowerShell in the folder and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File install.ps1
   ```
3. That's it - it starts immediately and will also launch automatically
   every time you log in.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

## Requirements

- Windows 10/11
- PowerShell (built in)
- SVP 4

## License

MIT
