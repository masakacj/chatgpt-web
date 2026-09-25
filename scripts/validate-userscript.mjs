import fs from 'node:fs';

const scriptPath = 'safari/chatgpt-safari.user.js';
const source = fs.readFileSync(scriptPath, 'utf8');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));

function fail(message) {
  console.error('[validate] ' + message);
  process.exit(1);
}

function requireText(text, description) {
  if (!source.includes(text)) fail('missing ' + description + ': ' + text);
}

const metadataVersion = source.match(/^\/\/\s*@version\s+([^\s]+)$/m)?.[1];
const runtimeVersion = source.match(/const VERSION = ['"]([^'"]+)['"];/)?.[1];

if (!metadataVersion) fail('userscript @version not found');
if (!runtimeVersion) fail('runtime VERSION not found');
if (metadataVersion !== pkg.version) fail('@version does not match package.json');
if (runtimeVersion !== pkg.version) fail('runtime VERSION does not match package.json');

requireText('// @match        https://chatgpt.com/*', 'chatgpt.com match');
requireText('// @run-at       document-start', 'document-start injection');
requireText('// @grant        none', 'grant none');
requireText('content-visibility: auto', 'conservative rendering hint');
requireText("const liveTurn = streaming ? turns[turns.length - 1] : null;", 'streaming turn protection');
requireText("perfLabel.textContent = '常驻轻量优化';", 'always-on control label');
requireText('const SETTLE_MS = 2800;', 'desktop-compatible settling window');
requireText('const READ_DWELL_MS = 1200;', 'desktop-compatible read dwell');
requireText('new BroadcastChannel(STATE_CHANNEL)', 'cross-tab state sync');
requireText("window.addEventListener('storage', onStorageSync)", 'storage-event sync fallback');
requireText("attachShadow({ mode: 'open' })", 'isolated control UI');

for (const status of ['running', 'waiting_user', 'settling', 'completed_unread', 'completed_read']) {
  requireText(status, 'conversation state ' + status);
}

const forbidden = [
  ['minTurns', 'length-gated optimization'],
  ['keepRecent', 'legacy recent-turn threshold'],
  ['window.webkit?.messageHandlers', 'native JS bridge'],
  ['replaceChildren(', 'DOM replacement'],
  ['.innerHTML =', 'innerHTML replacement'],
  [".removeAttribute('src')", 'media source unloading'],
];

for (const [needle, description] of forbidden) {
  if (source.includes(needle)) fail('forbidden ' + description + ': ' + needle);
}

console.log(JSON.stringify({
  ok: true,
  version: pkg.version,
  bytes: Buffer.byteLength(source),
  architecture: 'Safari + userscript',
  stateModel: 'running > waiting_user > settling > completed_unread > completed_read',
}, null, 2));
