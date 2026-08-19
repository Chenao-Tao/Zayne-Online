Option Explicit

Dim shell, fileSystem, scriptDirectory, petScript, command, argument
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
petScript = fileSystem.BuildPath(scriptDirectory, "native-pet.ps1")
command = "powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & petScript & """"

For Each argument In WScript.Arguments
    command = command & " " & Chr(34) & Replace(CStr(argument), Chr(34), Chr(34) & Chr(34)) & Chr(34)
Next

shell.Run command, 0, False
