' Silent runner for Subtitle Edit seconv
Set shell = CreateObject("WScript.Shell")

If WScript.Arguments.Count > 0 Then
    inputFile = WScript.Arguments(0)
    cmd = """C:\Program Files\Subtitle Edit\seconv.exe"" " & Chr(34) & inputFile & Chr(34) & " srt"
    shell.Run cmd, 0, True
End If
