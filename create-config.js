const fs = require('fs');

const port = process.env.PORT || '18789';
const llmUrl = process.env.LLM || 'http://localhost:11434/v1';
const model = process.env.MODEL || 'qwen3.5:9b';
const token = process.env.TOKEN || Math.random().toString(36).substring(2);
const dataDir = process.env.DATA || (process.env.USERPROFILE || process.env.HOME) + '/.openclaw';

const modelKey = 'locallm/' + model;

const config = {
    meta: { lastTouchedVersion: '2026.2.17' },
    models: {
        providers: {
            locallm: {
                baseUrl: llmUrl,
                apiKey: '',
                api: 'openai-completions',
                authHeader: false,
                models: [{
                    id: model,
                    name: model,
                    api: 'openai-completions',
                    reasoning: false, // Non-thinking mode (Direct Instruct)
                    input: ['text'],
                    cost: { input: 0, output: 0 },
                    contextWindow: 64000, // Optimized for local models
                    maxTokens: 16000
                }]
            }
        }
    },
    agents: {
        defaults: {
            model: { primary: modelKey },
            models: { [modelKey]: { temperature: 0.1, reasoning: false } }, // Low temperature and non-thinking
            workspace: dataDir + '/workspace',
            compaction: { mode: 'auto', messages: 20 },
            maxConcurrent: 4
        }
    },
    identity: {
        name: 'OpenClaw Assistant',
        emoji: '🦞',
        theme: 'red'
    },
    gateway: {
        port: parseInt(port),
        mode: 'local',
        bind: 'loopback',  // Localhost-only for security (using modern bind mode)
        auth: { mode: 'token', token: token },
        tailscale: { mode: 'off' },  // Disabled by default (no account required)
        nodes: { denyCommands: [] } // Allow all commands for direct setup
    },
    skills: {
        enabled: true,
        entries: {
            'pc-assistant': { enabled: true },
            'event-monitor': { enabled: true }
        }
    },
    channels: {},
    hooks: { internal: { enabled: true, entries: {} } },
    commands: { native: 'auto', nativeSkills: 'auto' },
    messages: { ackReactionScope: 'group-mentions' }
};

const sessionDir = dataDir + '/agents/main/sessions';
fs.mkdirSync(dataDir, { recursive: true });
fs.mkdirSync(dataDir + '/workspace', { recursive: true });
fs.mkdirSync(sessionDir, { recursive: true });

// Set permissions on Linux/Mac
if (process.platform !== 'win32') {
    try {
        fs.chmodSync(dataDir, 0o700);
        console.log('Set permissions 700 on ' + dataDir);
    } catch (e) {
        console.warn('Could not set permissions on ' + dataDir);
    }
}

fs.writeFileSync(dataDir + '/openclaw.json', JSON.stringify(config, null, 2));

// Set permissions for config file
if (process.platform !== 'win32') {
    try {
        fs.chmodSync(dataDir + '/openclaw.json', 0o600);
        console.log('Set permissions 600 on config file');
    } catch (e) {
        console.warn('Could not set permissions on config file');
    }
}

console.log('Config created at ' + dataDir + '/openclaw.json');
console.log('Token: ' + token);