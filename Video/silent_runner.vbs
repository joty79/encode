' Silent Runner for VIDEO Queue
Set objShell = CreateObject("WScript.Shell")

If WScript.Arguments.Count > 0 Then
    strPath = WScript.Arguments(0)
    ' Calls the VIDEO add_to_queue script
    strCmd = "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ""D:\Users\joty79\scripts\encode\Video\add_to_queue.ps1"" -TargetPath " & Chr(34) & strPath & Chr(34)
    
    ' Hide Window (0)
    objShell.Run strCmd, 0, False
End If