@echo off
setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0

echo ========================================
echo   OpenClaw Direct Setup (Batch)
echo   Rerouting to PowerShell Setup...
echo ========================================
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%SCRIPT_DIR%setup.ps1"
