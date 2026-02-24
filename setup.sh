#!/bin/bash

# ========================================
#   OpenClaw Direct Setup (Linux/Mac)
# ========================================

set -e

echo "========================================"
echo "  OpenClaw Direct Setup"
echo "========================================"
echo ""

# Check Node.js
echo "[1/6] Checking Node.js..."
if ! command -v node &> /dev/null; then
    echo "ERROR: Node.js not found. Install from https://nodejs.org"
    read -p "Press Enter to exit..."
    exit 1
fi
echo "OK: $(node --version)"

# Check npm
echo ""
echo "[2/6] Checking npm..."
if ! command -v npm &> /dev/null; then
    echo "ERROR: npm not found"
    read -p "Press Enter to exit..."
    exit 1
fi
echo "OK: $(npm --version)"

# Check Ollama
echo ""
echo "[3/6] Checking Ollama..."
if ! command -v ollama &> /dev/null; then
    echo "Ollama not found. Installing..."
    if command -v curl &> /dev/null; then
        curl -fsSL https://ollama.com/install.sh | sh
    else
        echo "ERROR: curl not found. Install Ollama manually from https://ollama.com"
        read -p "Press Enter to exit..."
        exit 1
    fi
fi
echo "OK: Ollama found"

# Check VRAM
echo ""
echo "[4/6] Checking VRAM..."
if command -v nvidia-smi &> /dev/null; then
    VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    echo "GPU Memory: ${VRAM} MB"
    if [ "$VRAM" -lt 12000 ]; then
        echo "WARNING: Less than 12GB VRAM detected"
        echo "For local models, you need at least 12GB VRAM"
        echo "Cloud LLMs will work, but local inference may be slow"
    fi
    echo "OK"
elif command -v rocm-smi &> /dev/null; then
    VRAM=$(rocm-smi --showmeminfo V | grep -oP '\d+' | head -1)
    echo "GPU Memory: ${VRAM} MB"
    if [ "$VRAM" -lt 12000 ]; then
        echo "WARNING: Less than 12GB VRAM detected"
    fi
    echo "OK"
else
    echo "INFO: Could not detect GPU VRAM (no nvidia-smi or rocm-smi)"
    echo "Assuming system has sufficient memory"
fi

# Configuration
echo ""
echo "[5/6] Configuration"
echo "-------------------------"
PORT="${PORT:-18789}"
LLM_URL="${LLM_URL:-http://localhost:11434/v1}"
MODEL="${MODEL:-ServiceNow-AI/Apriel-1.6-15b-Thinker:Q4_K_M}"

read -p "Port [$PORT]: " CUSTOM_PORT
[ -n "$CUSTOM_PORT" ] && PORT="$CUSTOM_PORT"

read -p "Ollama URL [$LLM_URL]: " CUSTOM_LLM
[ -n "$CUSTOM_LLM" ] && LLM_URL="$CUSTOM_LLM"

read -p "Model name [$MODEL]: " CUSTOM_MODEL
[ -n "$CUSTOM_MODEL" ] && MODEL="$CUSTOM_MODEL"

# Check/Install model
echo ""
echo "Checking Ollama model: $MODEL"
if ollama list | grep -q "$MODEL"; then
    echo "OK: Model already installed"
else
    echo "Model not found. Pulling from Ollama library..."
    ollama pull "$MODEL"
    echo "OK: Model installed"
fi

# Install OpenClaw
echo ""
echo "[6/6] Installing OpenClaw..."
npm install -g openclaw
echo "OK"

# Install ClawHub and skills
echo ""
echo "[7/7] Installing ClawHub and skills..."
npm install -g clawhub
clawhub install ningtoba/pc-assistant
echo "OK"

# Create config
echo ""
echo "Creating config..."
export PORT LLM MODEL
node "$(dirname "$0")/create-config.js"
echo "OK"

# Start Ollama and OpenClaw
echo ""
echo "========================================"
echo "  DONE!"
echo "========================================"
echo "URL: http://localhost:$PORT"
echo ""

echo "Starting Ollama..."
ollama serve &
sleep 2

echo "Starting OpenClaw Gateway..."
openclaw gateway &

echo ""
echo "All set! OpenClaw is running"
read -p "Press Enter to exit..."