@echo off
setlocal
chcp 65001 >nul
wscript.exe "%~dp0windows\launch-native.vbs"
endlocal
