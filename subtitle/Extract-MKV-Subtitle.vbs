' Silent runner for Extract-MKV-Subtitle.ps1
Set shell = CreateObject("WScript.Shell")

If WScript.Arguments.Count > 0 Then
    mkvFile = WScript.Arguments(0)
    cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""D:\Users\joty79\scripts\encode\subtitle\Extract-MKV-Subtitle.ps1"" " & Chr(34) & mkvFile & Chr(34)
    shell.Run cmd, 0, True
End If
