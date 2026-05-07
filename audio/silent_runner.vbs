' Silent Runner for Add to Audio Queue
Set objShell = CreateObject("WScript.Shell")

If WScript.Arguments.Count > 0 Then
    strPath = WScript.Arguments(0)
    ' Χτίζουμε την εντολή με προσοχή στα quotes για να μην σπάει σε paths με κενά/αγκύλες
    strCmd = "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ""D:\Users\joty79\scripts\encode\audio\add_to_audio_queue.ps1"" -TargetPath " & Chr(34) & strPath & Chr(34)
    
    ' Το "0" στο τέλος σημαίνει HIDE WINDOW (Εντελώς αόρατο)
    objShell.Run strCmd, 0, False
End If