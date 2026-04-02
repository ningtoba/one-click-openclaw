@echo off
setlocal enabledelayedexpansion

echo ========================================
echo   OpenClaw Direct Setup (Batch)
echo   One-click Unattended Installer
echo ========================================
echo.

:: Defaults
set "PORT=18789"
set "LLM=http://localhost:11434/v1"
set "MODEL=qwen3.5:9b"
set "DATA_DIR=%USERPROFILE%\.openclaw"
set "WORKSPACE=%DATA_DIR%\workspace"

:: Check if running as Administrator
net session >nul 2>&1
if %errorlevel% == 0 (
    echo [ERROR] Running as Administrator detected^^!
    echo DO NOT run this script as Administrator.
    echo OpenClaw should run under your standard user account for security.
    timeout /t 5 >nul
    exit /b 1
)

:: Run OpenClaw Official Installer (handles Node.js, Git, OpenClaw CLI)
echo [1/5] Running official OpenClaw installer (Node.js, Git, OpenClaw)...
set "OPENCLAW_NO_ONBOARD=1"
powershell -c "irm https://openclaw.ai/install.ps1 | iex"

:: Reload path
for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USER_PATH=%%B"
for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "MACHINE_PATH=%%B"
set "PATH=!USER_PATH!;!MACHINE_PATH!;%PATH%"

call npm --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARNING] npm is not in current PATH. You might need to restart terminal after installation.
)

:: Check Ollama
echo.
echo [2/5] Checking Ollama...
ollama --version >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%v in ('ollama --version') do echo [OK] Ollama found: %%v
) else (
    echo [INFO] Ollama not found. Installing...
    powershell -NoProfile -Command "$content = Invoke-RestMethod -Uri 'https://ollama.com/install.ps1'; if ($content -is [byte[]]) { $content = [System.Text.Encoding]::UTF8.GetString($content) }; Invoke-Expression $content"
    
    :: Reload path for ollama
    for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USER_PATH=%%B"
    for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "MACHINE_PATH=%%B"
    set "PATH=!USER_PATH!;!MACHINE_PATH!;%PATH%"
)

echo.
echo [3/5] Starting Ollama and checking model...

set OLLAMA_RUNNING=0
curl -s http://localhost:11434/api/version >nul 2>&1
if %errorlevel% equ 0 set OLLAMA_RUNNING=1

if !OLLAMA_RUNNING! equ 0 (
    echo Starting Ollama service...
    set "OLLAMA_NUM_CTX=32000"
    start /b "" powershell -WindowStyle Hidden -Command "$env:OLLAMA_NUM_CTX=32000; ollama serve"
    timeout /t 5 >nul
)

:: Wait for Ollama
set RETRY_COUNT=0
:WAIT_OLLAMA
curl -s http://localhost:11434/api/version >nul 2>&1
if %errorlevel% neq 0 (
    timeout /t 2 >nul
    set /a RETRY_COUNT+=1
    if !RETRY_COUNT! lss 10 goto WAIT_OLLAMA
)

:: Check/Install model
ollama list 2>&1 | findstr /R /C:"%MODEL%" >nul
if %errorlevel% equ 0 (
    echo [OK] Model '%MODEL%' already installed
) else (
    echo Model not found. Pulling '%MODEL%'. This may take a while...
    ollama pull %MODEL%
)

echo [4/5] Installing Skills management tools...
call npm install -g clawhub@latest clawdhub@latest

:: Install skills sequentially
call :InstallSkill pc-assistant
call :InstallSkill event-monitor

echo [OK] Core and Skills installed

echo.
echo [5/5] Configuring OpenClaw...

set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

FOR /F "tokens=*" %%i IN ('node create-config.js 2^>nul') DO (
    echo %%i
)

echo Installing OpenClaw Gateway service...
call openclaw gateway install --force

echo Starting OpenClaw Gateway...
call openclaw gateway start
timeout /t 3 >nul

echo Applying security firewall rules...
netsh advfirewall firewall show rule name="OpenClaw Gateway Block" >nul 2>&1
if %errorlevel% neq 0 (
    :: Will fail silently if not admin, which is intended
    netsh advfirewall firewall add rule name="OpenClaw Gateway Block" dir=in action=block protocol=TCP localport=%PORT% profile=any >nul 2>&1
)

:: Workspace initialization
if not exist "%WORKSPACE%" mkdir "%WORKSPACE%"

echo Running diagnostics and repairs (openclaw doctor)...
call openclaw doctor --repair --yes --non-interactive

echo Finalizing gateway...
call openclaw gateway restart

echo ========================================
echo   Starting OpenClaw...
echo ========================================

:: Wait for OpenClaw to start
set "RETRY_COUNT=0"
:WAIT_OPENCLAW
curl -s http://localhost:%PORT% >nul 2>&1
if %errorlevel% neq 0 (
    timeout /t 2 >nul
    set /a RETRY_COUNT+=1
    if !RETRY_COUNT! lss 15 goto WAIT_OPENCLAW
)

set "DASH_URL="
FOR /F "tokens=*" %%i IN ('openclaw dashboard --no-open ^| findstr "http"') DO set "FULL_URL_LINE=%%i"
for %%a in (!FULL_URL_LINE!) do set "DASH_URL=%%a"
if "!DASH_URL:~0,4!" neq "http" set "DASH_URL=http://localhost:%PORT%/onboard?token=!DASH_URL!"

echo URL: !DASH_URL!
echo Opening OpenClaw dashboard...
start "" "!DASH_URL!"

goto :EOF

:: ==========================================
:: Functions
:: ==========================================

:InstallSkill
set "SKILL=%~1"
set "SKILL_DIR=%DATA_DIR%\skills\%SKILL%"
if exist "%SKILL_DIR%" (
    echo OK: Skill '%SKILL%' directory found at %SKILL_DIR%.
    exit /b 0
)

set MAX_ATTEMPTS=3
set ATTEMPT=1
set WAIT_TIME=5

:RETRY_SKILL
echo Installing skill '%SKILL%' (Attempt !ATTEMPT!/%MAX_ATTEMPTS%)...
call npx clawhub install %SKILL% --force --workdir "%DATA_DIR%"
if %errorlevel% equ 0 (
    echo OK: Skill '%SKILL%' installed successfully.
    exit /b 0
)

call npx clawdhub install %SKILL% --force --workdir "%DATA_DIR%"
if %errorlevel% equ 0 (
    echo OK: Skill '%SKILL%' installed successfully.
    exit /b 0
)

echo WARNING: Failed to install skill '%SKILL%' with clawhub/clawdhub.
if !ATTEMPT! lss !MAX_ATTEMPTS! (
    echo Retrying in !WAIT_TIME! seconds...
    timeout /t !WAIT_TIME! >nul
    set /a WAIT_TIME*=2
    set /a ATTEMPT+=1
    goto RETRY_SKILL
)

echo ERROR: Failed to install skill '%SKILL%' after !MAX_ATTEMPTS! attempts.
exit /b 1
