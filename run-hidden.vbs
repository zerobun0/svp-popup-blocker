' Launches svp-popup-blocker.ps1 with zero window and zero console.
'
' wscript.exe is a GUI-subsystem process (no console of its own), and
' WshShell.Run's window-style 0 tells CreateProcess to allocate the child's
' console already hidden. Windows' "default terminal application" feature
' (which hands new console windows to Windows Terminal, causing a visible
' tab even for "-WindowStyle Hidden" powershell.exe launches in some
' timing conditions, e.g. right at logon) explicitly skips delegation for
' windows created hidden this way, so no tab is ever created - not just
' hidden after a flash.
'
' The final argument (bWaitOnReturn) MUST be True, not False. The watcher
' is meant to run forever (it blocks in a message loop). If wscript.exe
' fires the child and exits immediately (False), Task Scheduler sees its
' tracked action process finish and reaps the whole job - including the
' still-running powershell.exe child - within seconds. Waiting keeps
' wscript.exe alive for the watcher's entire lifetime, so Task Scheduler
' never tears the process tree down early.

Dim fso, scriptDir, ps1Path, objShell
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path = fso.BuildPath(scriptDir, "svp-popup-blocker.ps1")

Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1Path & """", 0, True
