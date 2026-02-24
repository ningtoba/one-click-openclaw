@echo off
setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0

echo ========================================
echo   OpenClaw Direct Setup
echo ========================================
echo.

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
echo [5/6] Configuration
echo -------------------------
set PORT=18789
set LLM_URL=http://localhost:11434/v1
set MODEL=glm-4.7-flash

set /p PORT=Port [%PORT%]: 
set /p LLM_URL=Ollama URL [%LLM_URL%]: 
set /p MODEL=Model name [%MODEL%]: 

if "%PORT%"=="" set PORT=18789
if "%LLM_URL%"=="" set LLM_URL=http://localhost:11434/v1
if "%MODEL%"=="" set MODEL=glm-4.7-flash

echo.
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

echo.
echo [6/6] Installing OpenClaw...
cmd /c "npm install -g openclaw"
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to install OpenClaw
    pause
    exit /b 1
)
echo OK

echo.
echo [7/7] Installing ClawHub and skills...
cmd /c "npm install -g clawhub"
cmd /c "clawhub install ningtoba/pc-assistant"
if %ERRORLEVEL% neq 0 (
    echo WARNING: Could not install skills. Continuing anyway.
)
echo OK

echo.
echo Creating config...
cmd /c "cd /d %SCRIPT_DIR% && set PORT=%PORT% && set LLM=%LLM_URL% && set MODEL=%MODEL% && node create-config.js"
echo OK

echo.
echo ========================================
echo   DONE!
echo ========================================
echo URL: http://localhost:%PORT%
echo.
echo Starting Ollama in background...
start /b cmd /c "ollama serve"

timeout /t 3 /nobreak >nul

echo Starting OpenClaw Gateway...
start cmd /k "openclaw gateway"

echo.
echo ========================================
echo   All set! OpenClaw is running
echo ========================================
echo.

echo Opening OpenClaw dashboard...
start http://localhost:%PORT%

pause