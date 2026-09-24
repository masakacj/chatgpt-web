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
requireText('attachShadow({ mode: \'open\' })', 'isolated control UI');

const forbidden = [
  ['window.webkit?.messageHandlers', 'native JS bridge'],
  ['replaceChildren(', 'DOM replacement'],
  ['.innerHTML =', 'innerHTML replacement'],
  [".removeAttribute('src')", 'media source unloading'],
  ['WKWebView', 'native WebView dependency'],
];

for (const [needle, description] of forbidden) {
  if (source.includes(needle)) fail('forbidden ' + description + ': ' + needle);
}

console.log(JSON.stringify({
  ok: true,
  version: pkg.version,
  bytes: Buffer.byteLength(source),
  architecture: 'Safari + userscript',
}, null, 2));
