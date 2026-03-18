---
name: openclaw-direct
description: One-click OpenClaw installer with security hardening. No Docker required - runs directly on Windows, macOS, and Linux.
metadata: {"user-invocable": true}
---

# OpenClaw Direct Setup

**Double-click to install! No Docker required.**

## Quick Start

**Windows:** Double-click `setup.bat` or `setup.ps1`
**Linux/Mac:** Run `bash setup.sh`

The script will:
1. Check if Node.js is installed
2. Install OpenClaw globally
3. Install ClawHub CLI and skills (pc-assistant, event-monitor)
4. Create config with your LLM settings
5. Start Ollama (if not running)
6. Start the OpenClaw gateway

That's it!

## Requirements

- **Node.js** - Download from https://nodejs.org (LTS version)
- **npm** - Comes with Node.js

## What Gets Installed

| Component | Details |
|-----------|---------|
| OpenClaw | `npm install -g openclaw` |
| ClawHub | `npm install -g clawhub` |
| Skills | pc-assistant, event-monitor |
| Config | `~/.openclaw/openclaw.json` |
| Workspace | `~/.openclaw/workspace` |

## Security Features

- **Localhost-only binding** (127.0.0.1) - No external network access
- **Admin/root detection** - Blocks if running with elevated privileges
- **Optional firewall rules** - Blocks external access to gateway port
- **Tailscale disabled by default** - No account required

## Configuration Options

This is a true one-click installer. It will automatically:
- Install Node.js (via NVM or Winget) if missing
- Install Ollama if missing
- Pull the `qwen3.5:9b` model
- Install OpenClaw, pc-assistant, and event-monitor skills
- Enforce localhost-only security and disable tailscale
- Start the gateway and open your browser

No prompts, interactivity, or user intervention required!

After installation, edit `~/.openclaw/openclaw.json` to add your API key.

## After Installation

- **URL:** http://localhost:18789
- **Auth Token:** Shown after installation
- **Config:** `~/.openclaw/openclaw.json`

### Commands

```bash
# Start gateway
openclaw gateway

# Stop gateway
openclaw gateway stop

# Check status
openclaw status
```

## Uninstall

```bash
npm uninstall -g openclaw
rm -rf ~/.openclaw
```

## Scripts

| File | Platform | Usage |
|------|----------|-------|
| `setup.bat` | Windows | Double-click or run in CMD |
| `setup.ps1` | Windows | Right-click → Run with PowerShell |
| `setup.sh` | Linux/Mac | `bash setup.sh` |

## Problems?

1. **Node.js not found** - Restart after installing Node.js
2. **Port in use** - Choose a different port during setup
3. **LLM not connecting** - Check your LLM is running and the URL is correct
4. **Ollama port conflict** - Script detects if port 11434 is already in use

## Version History

### 1.0.1
- Complete rework to one-click unattended installer
- Auto-installs Node.js (NVM/Winget) and Ollama if missing
- Auto-pulls qwen3.5:9b model
- Enforces strict zero-interaction setup for maximum convenience

### 1.0.0
- Initial release
- Security hardening (localhost binding, admin detection)
- Auto-install pc-assistant and event-monitor skills
- Ollama port conflict detection
- Optional firewall rules
