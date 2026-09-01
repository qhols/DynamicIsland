@echo off
title Dynamic Island Media Bridge (PowerShell)
echo ====================================================
echo  Starting Dynamic Island Media Bridge (PowerShell)...
echo  Listening on http://127.0.0.1:45455/
echo ====================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0media_bridge.ps1"
pause
