@echo off
title Brave Backup Manager

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BraveBackupManager.ps1"

echo.
echo =====================================
echo Script Finished
echo =====================================
pause