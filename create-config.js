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
                baseUrl: llmUrl.replace('/v1', ''),
                apiKey: 'ollama', // Required for native provider identification
                api: 'ollama',
                authHeader: false,
                models: [{
                    id: model,
                    name: model,
                    api: 'ollama',
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
            workspace: dataDir + '/workspace',
            compaction: { mode: 'safeguard' },
            maxConcurrent: 4
        },
        list: [
            {
                id: 'main',
                identity: {
                    name: 'OpenClaw Assistant',
                    emoji: '🦞',
                    theme: 'red'
                }
            }
        ]
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
        entries: {
            'pc-assistant': { enabled: true },
            'event-monitor': { enabled: true }
        }
    },
    channels: {},
    hooks: { internal: { enabled: true, entries: {} } },
    commands: { native: 'auto', nativeSkills: 'auto' },
    session: { retention: 100 },
    messages: { ackReactionScope: 'group-mentions' }
};

const workspaceDir = dataDir + '/workspace';
const sessionDir = dataDir + '/agents/main/sessions';
fs.mkdirSync(dataDir, { recursive: true });
fs.mkdirSync(workspaceDir, { recursive: true });
fs.mkdirSync(sessionDir, { recursive: true });

// Identity
const identityContent = `# Identity\n\n- Name: ${config.agents.list[0].identity.name}\n- Emoji: ${config.agents.list[0].identity.emoji}\n- Theme: ${config.agents.list[0].identity.theme}\n`;
fs.writeFileSync(workspaceDir + '/IDENTITY.md', identityContent);

// Soul
const soulContent = `# Soul\n\nYou are a highly efficient PC Assistant. **You have full memory of the current conversation history and must use it to provide context-aware answers.** You prioritize accuracy and performance. You have the following skills energized:\n\n- **PC Assistant**: Advanced system control and automation\n- **Event Monitor**: Predictive resource monitoring and alert detection\n`;
fs.writeFileSync(workspaceDir + '/SOUL.md', soulContent);

// Tools
const toolsContent = `# Tools\n\nThe following skills are installed and available via ClawHub. You can use any tools defined in their SKILL.md files:\n\n- [pc-assistant](skills/pc-assistant)\n- [event-monitor](skills/event-monitor)\n\nNotes: Use predictive monitoring to analyze system trends.\n`;
fs.writeFileSync(workspaceDir + '/TOOLS.md', toolsContent);

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