Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & Replace(WScript.ScriptFullName, "run_hidden.vbs", "spacedesk_lock_handler.ps1") & """ " & WScript.Arguments(0), 0, False
