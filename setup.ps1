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

# Run OpenClaw Official Installer (handles Node.js, Git, OpenClaw CLI)
Write-Host "[1/5] Running official OpenClaw installer (Node.js, Git, OpenClaw)..." -ForegroundColor Cyan
$env:OPENCLAW_NO_ONBOARD = "1"
powershell -c "irm https://openclaw.ai/install.ps1 | iex"

# Reload paths
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

try {
    $npmVersion = npm --version
} catch {
    Write-Host "[WARNING] npm is not in current PATH. You might need to restart terminal after installation." -ForegroundColor Yellow
}

# Check Ollama
Write-Host ""
Write-Host "[2/5] Checking Ollama..." -ForegroundColor Cyan
try {
    $ollamaVersion = ollama --version
    Write-Host "[OK] Ollama found: $ollamaVersion" -ForegroundColor Green
} catch {
    Write-Host "[INFO] Ollama not found. Installing..." -ForegroundColor Yellow
    $ollamaInstall = Invoke-RestMethod -Uri "https://ollama.com/install.ps1"
    if ($ollamaInstall -is [byte[]]) {
        $ollamaInstall = [System.Text.Encoding]::UTF8.GetString($ollamaInstall)
    }
    Invoke-Expression $ollamaInstall
    
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
    $env:OLLAMA_NUM_CTX = 32000
    Start-Process powershell -ArgumentList "-WindowStyle Hidden", "-Command", "`$env:OLLAMA_NUM_CTX=32000; ollama serve"
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

Write-Host "[4/5] Installing Skills management tools..." -ForegroundColor Cyan
npm install -g clawhub@latest clawdhub@latest

# Function to install a skill with retries and check if already installed
function Install-Skill {
    param([string]$skill)
    $maxAttempts = 3
    $attempt = 1
    $waitTime = 5

    # Check if skill directory actually exists locally
    $skillDir = "$env:USERPROFILE\.openclaw\skills\$skill"
    if (Test-Path $skillDir) {
        Write-Host "OK: Skill '$skill' directory found at $skillDir." -ForegroundColor Green
        return
    }

    while ($attempt -le $maxAttempts) {
        Write-Host "Installing skill '$skill' (Attempt $attempt/$maxAttempts)..." -ForegroundColor Cyan
        
        # Try npx clawhub first, then npx clawdhub as fallback (with explicit workdir and force)
        $success = $false
        $dataDir = "$env:USERPROFILE\.openclaw"
        try {
            cmd /c "npx clawhub install $skill --force --workdir ""$dataDir"""
            if ($LASTEXITCODE -eq 0) { $success = $true }
            else {
                cmd /c "npx clawdhub install $skill --force --workdir ""$dataDir"""
                if ($LASTEXITCODE -eq 0) { $success = $true }
            }
        } catch { }

        if ($success) {
            Write-Host "OK: Skill '$skill' installed successfully." -ForegroundColor Green
            return
        } else {
            Write-Host "WARNING: Failed to install skill '$skill' with clawhub/clawdhub." -ForegroundColor Yellow
            if ($attempt -lt $maxAttempts) {
                Write-Host "Retrying in $waitTime seconds..." -ForegroundColor Cyan
                Start-Sleep -Seconds $waitTime
                $waitTime *= 2
            }
        }
        $attempt++
    }

    Write-Host "ERROR: Failed to install skill '$skill' after $maxAttempts attempts." -ForegroundColor Red
}

Write-Host "Installing skills: pc-assistant, event-monitor..." -ForegroundColor Cyan
Install-Skill "pc-assistant"
Install-Skill "event-monitor"
Write-Host "[OK] Core and Skills installed" -ForegroundColor Green

Write-Host ""
Write-Host "[5/5] Configuring OpenClaw..." -ForegroundColor Cyan
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir
$configResult = node create-config.js | Out-String
Write-Host $configResult
$tokenMatch = $configResult | Select-String "Token: (.*)"
$setupToken = $tokenMatch.Matches.Groups[1].Value.Trim()

Write-Host "Installing OpenClaw Gateway service..." -ForegroundColor Cyan
openclaw gateway install --force

Write-Host "Starting OpenClaw Gateway..." -ForegroundColor Cyan
openclaw gateway start
Start-Sleep -Seconds 3

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

# Workspace initialization
if (-not (Test-Path "$dataDir\workspace")) { New-Item -ItemType Directory -Path "$dataDir\workspace" -Force | Out-Null }

# Run OpenClaw Doctor to apply any migrations and verify setup
Write-Host "Running diagnostics and repairs (openclaw doctor)..." -ForegroundColor Cyan
openclaw doctor --repair --yes --non-interactive

# Restart Gateway to apply changes
Write-Host "Finalizing gateway..." -ForegroundColor Cyan
openclaw gateway restart

Write-Host "========================================" -ForegroundColor Green
Write-Host "  Starting OpenClaw..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

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

$DASH_URL = (openclaw dashboard --no-open | Select-String "http" | Select-Object -First 1).ToString().Split(' ')[-1]
Write-Host "URL: $DASH_URL" -ForegroundColor Green
Write-Host "Opening OpenClaw dashboard..." -ForegroundColor Cyan
Start-Process "$DASH_URL"
