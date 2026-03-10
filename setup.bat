@echo off
setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0

echo ========================================
echo   OpenClaw Direct Setup
echo ========================================
echo.

REM Check if running as Administrator
net session >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [ERROR] Running as Administrator detected!
    echo.
    echo DO NOT run this script as Administrator.
    echo OpenClaw should run under your standard user account for security.
    echo.
    echo Please close this window and run normally (double-click)
    echo.
    pause
    exit /b 1
)

set PORT=18789
set ENGINE=ollama
set LLM_URL=http://localhost:11434/v1
set MODEL=qwen3.5:9b

echo [1/6] Checking Node.js...
cmd /c node --version
if %ERRORLEVEL% neq 0 (
    echo ERROR: Node.js not found. Install from https://nodejs.org
    pause
    exit /b 1
)
echo OK

echo.
echo [2/6] Checking npm...
cmd /c npm --version
if %ERRORLEVEL% neq 0 (
    echo ERROR: npm not found
    pause
    exit /b 1
)
echo OK

echo.
echo Select Inference Engine:
echo 1) Ollama (Local, default)
echo 2) LM Studio (OpenAI Compatible)
set /p ENGINE_CHOICE="Choice [1]: "

if "%ENGINE_CHOICE%"=="2" (
    set ENGINE=lmstudio
    set LLM_URL=http://localhost:1234/v1
    set MODEL=model-identifier
    echo Using LM Studio (OpenAI Compatible API)
) else (
    set ENGINE=ollama
    echo Using Ollama
)

if "%ENGINE%"=="ollama" (
    echo.
    echo [3/6] Checking Ollama...
    where ollama >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo Ollama not found. Installing Ollama...
        echo Please download from https://ollama.com and run the installer
        echo Or run this command in PowerShell as Admin:
        powershell -Command "irm https://ollama.com/install.ps1 | iex"
        pause
        exit /b 1
    )
    echo OK: Ollama found
)

echo.
echo [4/6] Checking VRAM (GPU memory)...
for /f "delims=" %%i in ('powershell -Command "Get-WmiObject Win32_VideoController | Select-Object -ExpandProperty AdapterRAM"') do set VRAM_BYTES=%%i
set /a VRAM_GB=%VRAM_BYTES% / 1024 / 1024 / 1024
echo GPU Memory: %VRAM_GB% GB
if %VRAM_GB% LSS 12 (
    echo WARNING: Less than 12GB VRAM detected
    echo For local models, you need at least 12GB VRAM
    echo Cloud LLMs will work, but local inference may be slow
    pause
)
echo OK

echo.
echo.
echo [5/6] Configuration
echo -------------------------
set /p PORT=Port [%PORT%]: 
set /p LLM_URL=LLM URL [%LLM_URL%]: 
set /p MODEL=Model name [%MODEL%]: 

if "%PORT%"=="" set PORT=18789
if "%LLM_URL%"=="" set LLM_URL=http://localhost:11434/v1
if "%MODEL%"=="" set MODEL=qwen3.5:9b

echo.
if "%ENGINE%"=="ollama" (
    echo Checking Ollama model: %MODEL%
    cmd /c "ollama list" | findstr /C:"%MODEL%" >nul
    if %ERRORLEVEL% neq 0 (
        echo Model not found. Pulling from Ollama library...
        cmd /c "ollama pull %MODEL%"
        if %ERRORLEVEL% neq 0 (
            echo WARNING: Could not pull model. Will use default.
        ) else (
            echo OK: Model installed
        )
    ) else (
        echo OK: Model already installed
    )
)

echo.
echo [6/6] Checking OpenClaw...
where openclaw >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo OpenClaw already installed. Updating...
    cmd /c "npm install -g openclaw"
    set /p RECONFIGURE="OpenClaw is already configured on this machine. Overwrite configuration with entries? (y/n, default: n): "
    if /i "!RECONFIGURE!"=="y" (
        set SHOULD_CONFIG=true
    ) else (
        echo Keeping existing configuration.
        set SHOULD_CONFIG=false
    )
) else (
    echo Installing OpenClaw...
    cmd /c "npm install -g openclaw"
    set SHOULD_CONFIG=true
)
echo OK

echo.
echo [7/7] Installing ClawHub and skills...
cmd /c "npm install -g clawhub"
cmd /c "clawhub install ningtoba/pc-assistant"
cmd /c "clawhub install event-monitor"
if %ERRORLEVEL% neq 0 (
    echo WARNING: Could not install skills. Continuing anyway.
)
echo OK

if "%SHOULD_CONFIG%"=="true" (
    echo.
    echo Creating/Updating configuration...
    cmd /c "cd /d %SCRIPT_DIR% && set PORT=%PORT% && set LLM=%LLM_URL% && set MODEL=%MODEL% && node create-config.js"
    echo OK
)

echo.
echo ========================================
echo   Security Hardening (Optional)
echo ========================================
echo.
echo Gateway is configured for localhost-only binding (127.0.0.1)
echo This means only your browser on this machine can access OpenClaw
echo.
set /p FIREWALL="Add Windows Firewall rule to block external access? (y/n, default: y): "
if "%FIREWALL%"=="" set FIREWALL=y
if /i "%FIREWALL%"=="y" (
    echo Adding firewall rule...
    netsh advfirewall firewall add rule name="OpenClaw Gateway Block" dir=in action=block protocol=TCP localport=%PORT% enable=yes profile=any >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        echo [OK] Firewall rule added - external access blocked
    ) else (
        echo [WARNING] Could not create firewall rule (may require admin)
        echo Localhost binding still provides protection
    )
) else (
    echo [INFO] Skipping firewall configuration
    echo Localhost binding still protects from external access
)

echo.
echo ========================================
echo   DONE!
echo ========================================
echo URL: http://localhost:%PORT%
echo.

if "%ENGINE%"=="ollama" (
    REM Check if Ollama is already running
    echo Checking Ollama status...
    powershell -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:11434/api/version' -TimeoutSec 2 -UseBasicParsing; if ($r.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }"
    if %ERRORLEVEL% equ 0 (
        echo [OK] Ollama is already running
    ) else (
        REM Check if port 11434 is in use
        netstat -ano | findstr ":11434" | findstr "LISTENING" >nul
        if %ERRORLEVEL% equ 0 (
            echo [ERROR] Port 11434 is already in use by another process
            echo Please stop the process using port 11434
            pause
            exit /b 1
        )
        echo Starting Ollama in background...
        start /b cmd /c "ollama serve"
        timeout /t 5 /nobreak >nul
    )

    REM Verify Ollama is responding
    powershell -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:11434/api/version' -TimeoutSec 5 -UseBasicParsing; exit 0 } catch { exit 1 }"
    if %ERRORLEVEL% neq 0 (
        echo [WARNING] Ollama may not be fully ready yet
    )
)

echo Starting OpenClaw Gateway...
start cmd /k "openclaw gateway"

echo.
echo Waiting for gateway to be ready...
echo.

REM Health check loop - wait for gateway to respond
set /a MAX_RETRIES=30
set /a RETRY_COUNT=0
:HEALTH_CHECK
timeout /t 2 /nobreak >nul
powershell -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:%PORT%' -TimeoutSec 2 -UseBasicParsing; exit $r.StatusCode } catch { exit 1 }"
if %ERRORLEVEL% equ 0 (
    echo [OK] Gateway is ready!
    goto OPEN_BROWSER
)
set /a RETRY_COUNT+=1
echo Still waiting... (%RETRY_COUNT%/%MAX_RETRIES%)
if %RETRY_COUNT% LSS %MAX_RETRIES% (
    goto HEALTH_CHECK
)

echo.
echo [WARNING] Gateway took longer than expected to start.
echo Opening browser anyway - you may need to refresh.
echo.

:OPEN_BROWSER
echo.
echo ========================================
echo   All set! OpenClaw is running
echo ========================================
echo.

echo Opening OpenClaw dashboard...
start http://localhost:%PORT%

pause
