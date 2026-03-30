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
export PORT
export LLM="$LLM_URL"
export MODEL

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "[ERROR] Running as root detected!"
    echo "DO NOT run this script as root/sudo."
    echo "OpenClaw should run under your standard user account for security."
    exit 1
fi

# Check/Install Node.js
echo "[1/5] Checking Node.js (Requires >= 22.16.0)..."
NEED_NODE=true
if command -v node &> /dev/null; then
    NODE_VER=$(node -v | cut -d'v' -f2)
    # Simple semantic version check (requires node 22.16.0 or higher)
    MAJOR=$(echo "$NODE_VER" | cut -d'.' -f1)
    MINOR=$(echo "$NODE_VER" | cut -d'.' -f2)
    if [ "$MAJOR" -gt 22 ] || ([ "$MAJOR" -eq 22 ] && [ "$MINOR" -ge 16 ]); then
        echo "OK: Node.js version $NODE_VER found."
        NEED_NODE=false
    else
        echo "INFO: Found Node.js $NODE_VER, but OpenClaw requires >= 22.16.0."
    fi
fi

if [ "$NEED_NODE" = true ]; then
    echo "INFO: Installing correct Node.js version via NVM..."
    export NVM_DIR="$HOME/.nvm"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    fi
    # Load NVM
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    nvm install 22.16.0
    nvm use 22.16.0
    nvm alias default 22.16.0
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
    # Ensure large context window for local models
    export OLLAMA_NUM_CTX=32000
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
npm install -g openclaw@latest clawhub@latest clawdhub@latest

# Function to install a skill with retries and check if already installed
install_skill() {
    local skill=$1
    local max_attempts=3
    local attempt=1
    local wait_time=5

    # Check if skill directory actually exists locally
    local skill_dir="$HOME/.openclaw/skills/$skill"
    if [ -d "$skill_dir" ]; then
        echo "OK: Skill '$skill' directory found at $skill_dir."
        return 0
    fi

    while [ $attempt -le $max_attempts ]; do
        echo "Installing skill '$skill' (Attempt $attempt/$max_attempts)..."
        # Try npx clawhub first with explicit workdir and force, then clawdhub as fallback
        if npx clawhub install "$skill" --force --workdir "$HOME/.openclaw" || npx clawdhub install "$skill" --force --workdir "$HOME/.openclaw"; then
            echo "OK: Skill '$skill' installed successfully."
            return 0
        else
            echo "WARNING: Failed to install skill '$skill' with clawhub/clawdhub."
            if [ $attempt -lt $max_attempts ]; then
                echo "Retrying in $wait_time seconds..."
                sleep $wait_time
                wait_time=$((wait_time * 2))
            fi
        fi
        attempt=$((attempt + 1))
    done

    echo "ERROR: Failed to install skill '$skill' after $max_attempts attempts."
    return 1
}

echo "Installing skills: pc-assistant, event-monitor..."
install_skill "pc-assistant" || true
install_skill "event-monitor" || true

echo ""
echo "[5/5] Configuring OpenClaw..."
CONFIG_OUTPUT=$(node "$(dirname "$0")/create-config.js")
echo "$CONFIG_OUTPUT"
TOKEN=$(echo "$CONFIG_OUTPUT" | grep "Token:" | awk '{print $2}')

echo "Installing OpenClaw Gateway service..."
openclaw gateway install --force || true

echo "Starting OpenClaw Gateway..."
openclaw gateway start || true

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

# Workspace initialization
mkdir -p "$HOME/.openclaw/workspace"

# Run OpenClaw Doctor to apply any migrations and verify setup
echo "Running diagnostics and repairs (openclaw doctor)..."
openclaw doctor --repair --yes --non-interactive

# Final gateway restart to ensure everything is loaded correctly
echo "Finalizing gateway..."
openclaw gateway restart

echo ""
echo "========================================"
echo "  DONE! Launching OpenClaw..."
echo "========================================"
DASH_URL=$(openclaw dashboard --no-open | grep "http" | head -n 1 | awk '{print $NF}')
echo "URL: $DASH_URL"

# Wait for gateway to be ready
echo "Waiting for gateway to start..."
max_retries=15
retry_count=0
while ! curl -s --connect-timeout 2 "http://localhost:$PORT" > /dev/null 2>&1; do
    sleep 2
    retry_count=$((retry_count+1))
    if [ $retry_count -ge $max_retries ]; then
        break
    fi
done

echo "Opening OpenClaw dashboard..."
if command -v xdg-open &> /dev/null; then
    xdg-open "$DASH_URL"
elif command -v open &> /dev/null; then
    open "$DASH_URL"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    start "$DASH_URL"
fi