# ========================================
#   OpenClaw Direct Setup (PowerShell)
#   Right-click -> Run with PowerShell
#   DO NOT run as Administrator!
# ========================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpenClaw Direct Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Defaults
$port = 18789
$engine = "ollama"
$llmBaseUrl = "http://localhost:11434/v1"
$llmModel = "qwen3.5:9b"
$dataDir = "$env:USERPROFILE\.openclaw"
$workspace = "$dataDir\workspace"

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Host "[ERROR] Running as Administrator detected!" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "DO NOT run this script as Administrator." -ForegroundColor Red
    Write-Host "OpenClaw should run under your standard user account for security." -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "Please close this window and run normally (double-click or right-click -> Run with PowerShell)" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit 1
}

# Check if Node.js is installed
try {
    $nodeVersion = node --version
    Write-Host "[OK] Node.js found: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Node.js is not installed" -ForegroundColor Red
    Write-Host "Please install Node.js from https://nodejs.org" -ForegroundColor Yellow
    Read-Host "Press Enter to exit..."
    exit 1
}

# Check npm
try {
    $npmVersion = npm --version
    Write-Host "[OK] npm found: $npmVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] npm is not installed" -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit 1
}

Write-Host ""
Write-Host "Select Inference Engine:"
Write-Host "1) Ollama (Local, default)"
Write-Host "2) LM Studio (OpenAI Compatible)"
$engineChoice = Read-Host "Choice [1]"

if ($engineChoice -eq "2") {
    $engine = "lmstudio"
    $llmBaseUrl = "http://localhost:1234/v1"
    $llmModel = "model-identifier"
    Write-Host "Using LM Studio (OpenAI Compatible API)" -ForegroundColor Green
} else {
    $engine = "ollama"
    Write-Host "Using Ollama" -ForegroundColor Green
}

if ($engine -eq "ollama") {
    # Check Ollama
    Write-Host ""
    Write-Host "[3/6] Checking Ollama..." -ForegroundColor Cyan
    try {
        $ollamaVersion = ollama --version
        Write-Host "[OK] Ollama found: $ollamaVersion" -ForegroundColor Green
    } catch {
        Write-Host "[INFO] Ollama not found. Installing..." -ForegroundColor Yellow
        # Install Ollama via PowerShell
        $ollamaInstallScript = Invoke-WebRequest -Uri "https://ollama.com/install.ps1" -UseBasicParsing
        Invoke-Expression $ollamaInstallScript.Content
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Failed to install Ollama" -ForegroundColor Red
            Write-Host "Please install manually from https://ollama.com" -ForegroundColor Yellow
        } else {
            Write-Host "[OK] Ollama installed" -ForegroundColor Green
        }
    }
}

# Check VRAM
Write-Host ""
Write-Host "[4/6] Checking VRAM..." -ForegroundColor Cyan
try {
    $gpu = Get-WmiObject Win32_VideoController
    $vram = $gpu.AdapterRAM / 1GB
    Write-Host "GPU Memory: $([math]::Round($vram, 1)) GB" -ForegroundColor Green
    if ($vram -lt 12) {
        Write-Host "[WARNING] Less than 12GB VRAM detected" -ForegroundColor Yellow
        Write-Host "Local models may run slowly" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[INFO] Could not detect GPU VRAM" -ForegroundColor Yellow
}

Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$customPort = Read-Host "Port (default $port)"
if ($customPort) { $port = $customPort }

$customLlm = Read-Host "LLM Base URL (default $llmBaseUrl)"
if ($customLlm) { $llmBaseUrl = $customLlm }

$customModel = Read-Host "LLM Model (default $llmModel)"
if ($customModel) { $llmModel = $customModel }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installing OpenClaw..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

npm install -g openclaw

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to install OpenClaw" -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit 1
}

Write-Host "[OK] OpenClaw installed" -ForegroundColor Green
Write-Host ""

# Install ClawHub and skills
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installing ClawHub and skills..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

npm install -g clawhub
clawhub install ningtoba/pc-assistant
clawhub install event-monitor

Write-Host "[OK] Skills installed" -ForegroundColor Green
Write-Host ""

# Check/Install Ollama model
if ($engine -eq "ollama") {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Checking Ollama model..." -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $modelList = ollama list 2>&1
    if ($modelList -match $llmModel) {
        Write-Host "[OK] Model '$llmModel' already installed" -ForegroundColor Green
    } else {
        Write-Host "Model not found. Pulling '$llmModel'..." -ForegroundColor Yellow
        ollama pull $llmModel
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Model installed" -ForegroundColor Green
        } else {
            Write-Host "[WARNING] Could not pull model. Will use default." -ForegroundColor Yellow
        }
    }
}

# Create directories
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
New-Item -ItemType Directory -Force -Path $workspace | Out-Null

# Generate auth token
$authToken = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object {[char]$_})

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Creating config..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Create config using Node.js via PowerShell
$nodeScript = @"
const fs = require('fs');
const modelKey = 'localllm/' + '$llmModel';
const c = {
    meta: { lastTouchedVersion: '2026.2.17' },
    models: {
        providers: {
            localllm: {
                baseUrl: '$llmBaseUrl',
                apiKey: '',
                api: 'openai-completions',
                authHeader: false,
                models: [{
                    id: '$llmModel',
                    name: '$llmModel',
                    api: 'openai-completions',
                    reasoning: false,
                    input: ['text'],
                    cost: { input: 0, output: 0 },
                    contextWindow: 200000,
                    maxTokens: 20000
                }]
            }
        }
    },
    agents: {
        defaults: {
            model: { primary: modelKey },
            models: { [modelKey]: {} },
            workspace: '$workspace',
            compaction: { mode: 'safeguard' },
            maxConcurrent: 4
        }
    },
    gateway: {
        port: $port,
        mode: 'local',
        bind: '127.0.0.1',  // Localhost-only for security (no external access)
        auth: { mode: 'token', token: '$authToken' },
        tailscale: { mode: 'off' },  // Disabled by default (no account required)
        nodes: { denyCommands: ['camera.snap', 'camera.clip', 'screen.record', 'exec'] }
    },
    channels: {
        "webchat": {
            "account": "default",
            "config": {}
        }
    },
    hooks: { internal: { enabled: true, entries: {} } },
    commands: { native: 'auto', nativeSkills: 'auto' },
    messages: { ackReactionScope: 'group-mentions' }
};
fs.writeFileSync('$dataDir\\openclaw.json', JSON.stringify(c, null, 2));
console.log('Config created');
"@

node -e $nodeScript

Write-Host "[OK] Config created at $dataDir\openclaw.json" -ForegroundColor Green
Write-Host ""

# Optional: Configure Windows Firewall for additional security
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Security Hardening (Optional)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Gateway is configured for localhost-only binding (127.0.0.1)" -ForegroundColor Green
Write-Host "This means only your browser on this machine can access OpenClaw" -ForegroundColor Green
Write-Host ""

$firewallChoice = Read-Host "Add Windows Firewall rule to block external access? (y/n, default: y)"
if ($firewallChoice -eq "" -or $firewallChoice -eq "y" -or $firewallChoice -eq "Y") {
    try {
        # Check if rule already exists
        $existingRule = Get-NetFirewallRule -DisplayName "OpenClaw Gateway Block" -ErrorAction SilentlyContinue
        if ($existingRule) {
            Write-Host "[INFO] Firewall rule already exists" -ForegroundColor Gray
        } else {
            # Create firewall rule to block inbound connections to the gateway port
            New-NetFirewallRule -DisplayName "OpenClaw Gateway Block" `
                -Direction Inbound `
                -LocalPort $port `
                -Protocol TCP `
                -Action Block `
                -Enabled True `
                -Profile Any `
                -ErrorAction SilentlyContinue
            
            Write-Host "[OK] Firewall rule added - external access blocked" -ForegroundColor Green
        }
    } catch {
        Write-Host "[WARNING] Could not create firewall rule (may require admin)" -ForegroundColor Yellow
        Write-Host "Localhost binding still provides protection" -ForegroundColor Gray
    }
} else {
    Write-Host "[INFO] Skipping firewall configuration" -ForegroundColor Gray
    Write-Host "Localhost binding still protects from external access" -ForegroundColor Gray
}

if ($engine -eq "ollama") {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Starting Ollama..." -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Check if Ollama is already running on port 11434
    $ollamaRunning = $false
    try {
        $testConnection = Invoke-WebRequest -Uri "http://localhost:11434/api/version" -TimeoutSec 2 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($testConnection.StatusCode -eq 200) {
            $ollamaRunning = $true
            Write-Host "[OK] Ollama is already running" -ForegroundColor Green
        }
    } catch {
        # Ollama not running, will start it
    }

    if (-not $ollamaRunning) {
        # Check if port 11434 is in use by another process
        $portInUse = Get-NetTCPConnection -LocalPort 11434 -ErrorAction SilentlyContinue
        if ($portInUse) {
            Write-Host "[ERROR] Port 11434 is already in use by another process" -ForegroundColor Red
            Write-Host "Please stop the process using port 11434 or configure a different Ollama port" -ForegroundColor Yellow
            Read-Host "Press Enter to exit..."
            exit 1
        }
        
        # Start Ollama in background
        Write-Host "Starting Ollama service..." -ForegroundColor Cyan
        Start-Process powershell -ArgumentList "-NoExit", "-Command", "ollama serve"
        Start-Sleep -Seconds 5
    } else {
        Write-Host "[INFO] Skipping Ollama start (already running)" -ForegroundColor Gray
    }

    # Verify Ollama is responding
    try {
        $verifyOllama = Invoke-WebRequest -Uri "http://localhost:11434/api/version" -TimeoutSec 5 -UseBasicParsing
        Write-Host "[OK] Ollama is responding" -ForegroundColor Green
    } catch {
        Write-Host "[WARNING] Ollama may not be fully ready yet" -ForegroundColor Yellow
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Starting OpenClaw Gateway..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Verify config exists before starting gateway
$configPath = "$dataDir\openclaw.json"
if (-not (Test-Path $configPath)) {
    Write-Host "[ERROR] Config file not found at $configPath" -ForegroundColor Red
    Write-Host "Please run 'openclaw setup' first" -ForegroundColor Yellow
    Read-Host "Press Enter to exit..."
    exit 1
}

# Verify gateway mode is set to local
$configContent = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $configContent.gateway.mode -or $configContent.gateway.mode -ne "local") {
    Write-Host "[WARNING] Gateway mode is not set to 'local'. Fixing..." -ForegroundColor Yellow
    $configContent.gateway.mode = "local"
    $configContent | ConvertTo-Json -Depth 10 | Set-Content $configPath
    Write-Host "[OK] Gateway mode set to 'local'" -ForegroundColor Green
}

# Start in new window
Write-Host "Starting gateway..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "openclaw gateway"
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Waiting for gateway to be ready..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Health check loop - wait for gateway to respond
$maxRetries = 30
$retryCount = 0
$gatewayReady = $false

while ($retryCount -lt $maxRetries) {
    Start-Sleep -Seconds 2
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$port" -TimeoutSec 2 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            $gatewayReady = $true
            Write-Host "[OK] Gateway is ready!" -ForegroundColor Green
            break
        }
    } catch {
        $retryCount++
        Write-Host "Still waiting... ($retryCount/$maxRetries)" -ForegroundColor Yellow
    }
}

if (-not $gatewayReady) {
    Write-Host ""
    Write-Host "[WARNING] Gateway took longer than expected to start." -ForegroundColor Yellow
    Write-Host "Opening browser anyway - you may need to refresh." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  OpenClaw is running!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "URL: http://localhost:$port" -ForegroundColor Yellow
Write-Host "Auth Token: $authToken" -ForegroundColor Yellow
Write-Host "Workspace: $workspace" -ForegroundColor Yellow
Write-Host ""
Write-Host "To stop: Close the OpenClaw window or run 'openclaw gateway stop'" -ForegroundColor White
Write-Host ""

# Open dashboard in browser
Write-Host "Opening OpenClaw dashboard..." -ForegroundColor Cyan
Start-Process "http://localhost:$port"

Read-Host "Press Enter to exit..."
