@echo off
setlocal
chcp 65001 >nul
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0windows\native-pet.ps1"
endlocal
