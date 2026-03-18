#!/bin/bash

# ========================================
#   OpenClaw Direct Setup (Linux/Mac)
#   One-click Unattended Installer
# ========================================

set -e

echo "========================================"
echo "  OpenClaw Direct Setup"
echo "========================================"
echo ""

# Default Configuration
PORT="18789"
LLM_URL="http://localhost:11434/v1"
MODEL="qwen3.5:9b"
export PORT LLM
LLM="$LLM_URL"
export MODEL

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "[ERROR] Running as root detected!"
    echo "DO NOT run this script as root/sudo."
    echo "OpenClaw should run under your standard user account for security."
    exit 1
fi

# Check/Install Node.js
echo "[1/5] Checking Node.js..."
if ! command -v node &> /dev/null; then
    echo "INFO: Node.js not found. Installing via NVM (Node Version Manager)..."
    export NVM_DIR="$HOME/.nvm"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    fi
    # Load NVM
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    nvm install --lts
    nvm use --lts
else
    echo "OK: $(node --version)"
fi

if ! command -v npm &> /dev/null; then
    echo "ERROR: npm still not found. Try restarting your terminal or installing Node manually."
    exit 1
fi
echo "OK: $(npm --version)"

# Check/Install Ollama
echo ""
echo "[2/5] Checking Ollama..."
if ! command -v ollama &> /dev/null; then
    echo "INFO: Ollama not found. Installing..."
    curl -fsSL https://ollama.com/install.sh | sh
fi
echo "OK: Ollama found"

echo ""
echo "[3/5] Starting Ollama and pulling model $MODEL..."
# Start Ollama service if not already running
if ! curl -s --connect-timeout 2 http://localhost:11434/api/version > /dev/null 2>&1; then
    echo "Starting Ollama..."
    ollama serve >/dev/null 2>&1 &
    sleep 5
fi

# Wait for Ollama to be ready
max_retries=10
retry_count=0
while ! curl -s --connect-timeout 2 http://localhost:11434/api/version > /dev/null 2>&1; do
    sleep 2
    retry_count=$((retry_count+1))
    if [ $retry_count -ge $max_retries ]; then
        echo "WARNING: Ollama is taking too long to start. Model pull might fail."
        break
    fi
done

if ! ollama list | grep -q "$MODEL"; then
    echo "Pulling model $MODEL. This may take a while based on your internet connection..."
    ollama pull "$MODEL"
else
    echo "OK: Model $MODEL already installed."
fi

echo ""
echo "[4/5] Installing OpenClaw and Skills..."
npm install -g openclaw@latest clawhub@latest

echo "Installing skills: pc-assistant, event-monitor..."
clawhub install ningtoba/pc-assistant
clawhub install event-monitor

echo ""
echo "[5/5] Configuring OpenClaw..."
node "$(dirname "$0")/create-config.js"

# Security Hardening - Firewall (Optional but automatic)
echo "Setting up Firewall (silent)..."
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v ufw &> /dev/null; then
        sudo ufw deny from any to any port $PORT proto tcp 2>/dev/null || true
    elif command -v firewall-cmd &> /dev/null; then
        sudo firewall-cmd --permanent --add-port=$PORT/tcp 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
    fi
fi

echo ""
echo "========================================"
echo "  DONE! Launching OpenClaw..."
echo "========================================"
echo "URL: http://localhost:$PORT"

openclaw gateway >/dev/null 2>&1 &
sleep 3

# Wait for gateway to be ready
echo "Waiting for gateway to start..."
max_retries=15
retry_count=0
while ! curl -s --connect-timeout 2 http://localhost:$PORT > /dev/null 2>&1; do
    sleep 2
    retry_count=$((retry_count+1))
    if [ $retry_count -ge $max_retries ]; then
        break
    fi
done

echo "Opening OpenClaw dashboard..."
if command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:$PORT"
elif command -v open &> /dev/null; then
    open "http://localhost:$PORT"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    start "http://localhost:$PORT"
fi