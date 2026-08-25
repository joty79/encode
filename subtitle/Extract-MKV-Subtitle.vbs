Option Explicit

Dim shell, fileSystem, inputFile, scriptPath, command, exitCode
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

If WScript.Arguments.Count < 1 Then WScript.Quit 2
inputFile = WScript.Arguments(0)
scriptPath = fileSystem.BuildPath(fileSystem.GetParentFolderName(WScript.ScriptFullName), "Extract-MKV-Subtitle.ps1")
command = "pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & scriptPath & """ -MkvFile """ & inputFile & """"
exitCode = shell.Run(command, 0, True)

If exitCode <> 0 Then
    MsgBox "Subtitle extraction failed. No source or existing output was overwritten.", 16, "Extract MKV subtitle"
End If
WScript.Quit exitCode
