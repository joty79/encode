Option Explicit

Dim shell, fileSystem, inputFile, scriptPath, command, exitCode
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

If WScript.Arguments.Count < 1 Then WScript.Quit 2
inputFile = WScript.Arguments(0)
scriptPath = fileSystem.BuildPath(fileSystem.GetParentFolderName(WScript.ScriptFullName), "Convert-ToSrt.ps1")
command = "pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & scriptPath & """ -Path """ & inputFile & """"
exitCode = shell.Run(command, 0, True)

If exitCode <> 0 Then
    MsgBox "Subtitle conversion failed. No source or existing output was overwritten.", 16, "Convert to SRT"
End If
WScript.Quit exitCode
