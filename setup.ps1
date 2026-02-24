# ========================================
#   OpenClaw Direct Setup (PowerShell)
#   Right-click -> Run with PowerShell
# ========================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpenClaw Direct Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

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

# Defaults
$port = 18789
$llmBaseUrl = "http://localhost:11434/v1"
$llmModel = "glm-4.7-flash"
$dataDir = "$env:USERPROFILE\.openclaw"
$workspace = "$dataDir\workspace"

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

Write-Host "[OK] Skills installed" -ForegroundColor Green
Write-Host ""

# Check/Install Ollama model
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Checking Ollama model..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$modelList = ollama list 2>&1
if ($modelList -match $llmModel) {
    Write-Host "[OK] Model '$llmModel' already installed" -ForegroundColor Green
} else {
    Write-Host "Model not found. Installing from HuggingFace..." -ForegroundColor Yellow
    
    # Model info
    $hfModel = "unsloth/GLM-4.7-Flash-GGUF"
    $hfFile = "GLM-4.7-Flash-Q2_K_L.gguf"
    $modelDir = "$env:USERPROFILE\.ollama\models"
    $modelPath = "$modelDir\$hfFile"
    $modelfilePath = "$modelDir\Modelfile"
    
    # Download from HuggingFace using hf-cli or direct download
    Write-Host "Downloading $hfFile from HuggingFace..." -ForegroundColor Cyan
    
    # Try using huggingface-cli first, fallback to direct download
    $downloadSuccess = $false
    
    # Method 1: Try huggingface-cli
    try {
        Write-Host "Trying huggingface-cli..." -ForegroundColor Gray
        hf download --repo-type model --filename $hfFile $hfModel --local-dir $modelDir 2>&1 | Out-Null
        if (Test-Path $modelPath) {
            $downloadSuccess = $true
        }
    } catch {}
    
    # Method 2: Direct download via raw URL
    if (-not $downloadSuccess) {
        Write-Host "Trying direct download..." -ForegroundColor Gray
        $downloadUrl = "https://huggingface.co/$hfModel/resolve/main/$hfFile"
        try {
            New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
            Invoke-WebRequest -Uri $downloadUrl -OutFile $modelPath -UseBasicParsing
            if (Test-Path $modelPath) {
                $downloadSuccess = $true
            }
        } catch {
            Write-Host "[WARNING] Could not download automatically" -ForegroundColor Yellow
        }
    }
    
    if ($downloadSuccess -and (Test-Path $modelPath)) {
        Write-Host "Creating Ollama Modelfile..." -ForegroundColor Cyan
        
        # Create Modelfile
        @"
FROM ./$hfFile
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
"@ | OutFile -FilePath $modelfilePath -Encoding UTF8
        
        # Create the model in Ollama
        Set-Location $modelDir
        ollama create $llmModel -f $modelfilePath
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Model '$llmModel' installed from HuggingFace" -ForegroundColor Green
        } else {
            Write-Host "[WARNING] Could not create Ollama model. Trying direct..." -ForegroundColor Yellow
            ollama create $llmModel --from $modelPath
        }
    } else {
        Write-Host "[WARNING] Could not download model. Trying ollama pull..." -ForegroundColor Yellow
        ollama pull $llmModel
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
const modelKey = 'locallm/' + '$llmModel';
const c = {
    meta: { lastTouchedVersion: '2026.2.17' },
    models: {
        providers: {
            locallm: {
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
        bind: 'lan',
        auth: { mode: 'token', token: '$authToken' },
        tailscale: { mode: 'off' },
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

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Starting Ollama..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Start Ollama in background
Start-Process powershell -ArgumentList "-NoExit", "-Command", "ollama serve"
Start-Sleep -Seconds 3

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Starting OpenClaw Gateway..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Start in new window
Start-Process powershell -ArgumentList "-NoExit", "-Command", "openclaw gateway"

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

# Wait for gateway to start
Start-Sleep -Seconds 5

# Open dashboard in browser
Write-Host "Opening OpenClaw dashboard..." -ForegroundColor Cyan
Start-Process "http://localhost:$port"

Read-Host "Press Enter to exit..."