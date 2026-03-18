# ========================================
#   OpenClaw Direct Setup (PowerShell)
#   One-click Unattended Installer
# ========================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpenClaw Direct Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Defaults
$port = 18789
$llmBaseUrl = "http://localhost:11434/v1"
$llmModel = "qwen3.5:9b"
$dataDir = "$env:USERPROFILE\.openclaw"
$workspace = "$dataDir\workspace"
$env:PORT = $port
$env:LLM = $llmBaseUrl
$env:MODEL = $llmModel

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Host "[ERROR] Running as Administrator detected!" -ForegroundColor Red
    Write-Host "DO NOT run this script as Administrator." -ForegroundColor Red
    Write-Host "OpenClaw should run under your standard user account for security." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

# Check if Node.js is installed
Write-Host "[1/5] Checking Node.js..." -ForegroundColor Cyan
$nodeInstalled = $false
try {
    $nodeVersion = node --version
    Write-Host "[OK] Node.js found: $nodeVersion" -ForegroundColor Green
    $nodeInstalled = $true
} catch {
    Write-Host "[INFO] Node.js is not installed. Using winget..." -ForegroundColor Yellow
    # Install Node.js silently using winget in user scope
    winget install --id OpenJS.NodeJS.LTS -e --silent --scope user --accept-package-agreements --accept-source-agreements
    
    # Reload environment variables
    foreach ($level in "Machine", "User") {
        [Environment]::GetEnvironmentVariables($level).GetEnumerator() | ForEach-Object {
            if ($_.Key -eq "Path") {
                $env:Path = $_.Value + ";" + $env:Path
            } else {
                Set-Item "Env:\$($_.Key)" $_.Value
            }
        }
    }
    
    try {
        $nodeVersion = node --version
        Write-Host "[OK] Node.js installed: $nodeVersion" -ForegroundColor Green
        $nodeInstalled = $true
    } catch {
        Write-Host "[ERROR] Failed to install Node.js via winget. Please install manually." -ForegroundColor Red
        Start-Sleep -Seconds 5
        exit 1
    }
}

# Make sure npm is available
try {
    $npmVersion = npm --version
} catch {
    Write-Host "[ERROR] npm is not available. Try restarting terminal." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

# Check Ollama
Write-Host ""
Write-Host "[2/5] Checking Ollama..." -ForegroundColor Cyan
try {
    $ollamaVersion = ollama --version
    Write-Host "[OK] Ollama found: $ollamaVersion" -ForegroundColor Green
} catch {
    Write-Host "[INFO] Ollama not found. Installing..." -ForegroundColor Yellow
    $ollamaInstallScript = Invoke-WebRequest -Uri "https://ollama.com/install.ps1" -UseBasicParsing
    Invoke-Expression $ollamaInstallScript.Content
    
    # Reload paths
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
}

Write-Host ""
Write-Host "[3/5] Starting Ollama and checking model..." -ForegroundColor Cyan

# Check if Ollama is running
$ollamaRunning = $false
try {
    $testConnection = Invoke-WebRequest -Uri "http://localhost:11434/api/version" -TimeoutSec 2 -UseBasicParsing -ErrorAction SilentlyContinue
    if ($testConnection.StatusCode -eq 200) {
        $ollamaRunning = $true
    }
} catch { }

if (-not $ollamaRunning) {
    Write-Host "Starting Ollama service..." -ForegroundColor Cyan
    Start-Process powershell -ArgumentList "-WindowStyle Hidden", "-Command", "ollama serve"
    Start-Sleep -Seconds 5
}

# Wait for Ollama
$retryCount = 0
while ($retryCount -lt 10) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:11434/api/version" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        break
    } catch {
        Start-Sleep -Seconds 2
        $retryCount++
    }
}

# Check/Install model
$modelList = ollama list 2>&1
if ($modelList -match $llmModel) {
    Write-Host "[OK] Model '$llmModel' already installed" -ForegroundColor Green
} else {
    Write-Host "Model not found. Pulling '$llmModel'. This may take a while..." -ForegroundColor Yellow
    ollama pull $llmModel
}

Write-Host ""
Write-Host "[4/5] Installing OpenClaw and Skills..." -ForegroundColor Cyan
npm install -g openclaw@latest clawhub@latest
clawhub install ningtoba/pc-assistant
clawhub install event-monitor
Write-Host "[OK] Core and Skills installed" -ForegroundColor Green

Write-Host ""
Write-Host "[5/5] Configuring OpenClaw..." -ForegroundColor Cyan
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir
node create-config.js

# Apply Security Features (Firewall)
Write-Host "Applying security firewall rules..." -ForegroundColor Cyan
try {
    $existingRule = Get-NetFirewallRule -DisplayName "OpenClaw Gateway Block" -ErrorAction SilentlyContinue
    if (-not $existingRule) {
        # Firewalls require Admin privilege, so we try, and just fail silently if not Admin
        New-NetFirewallRule -DisplayName "OpenClaw Gateway Block" `
            -Direction Inbound `
            -LocalPort $port `
            -Protocol TCP `
            -Action Block `
            -Enabled True `
            -Profile Any `
            -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Starting OpenClaw..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Start-Process powershell -ArgumentList "-WindowStyle Hidden", "-Command", "openclaw gateway"
Start-Sleep -Seconds 3

# Wait for OpenClaw to start
$retryCount = 0
while ($retryCount -lt 15) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$port" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        break
    } catch {
        Start-Sleep -Seconds 2
        $retryCount++
    }
}

Write-Host "Opening OpenClaw dashboard..." -ForegroundColor Cyan
Start-Process "http://localhost:$port"
