@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\disable-autostart.ps1"
if errorlevel 1 pause
endlocal
