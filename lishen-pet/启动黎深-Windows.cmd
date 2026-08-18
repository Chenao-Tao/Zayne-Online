@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\launch.ps1"
if errorlevel 1 pause
endlocal
