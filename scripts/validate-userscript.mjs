import fs from 'node:fs';

const sharedPath = 'safari/chatgpt-safari.user.js';
const gesturePath = 'safari/chatgpt-ios-gestures.user.js';

const shared = fs.readFileSync(sharedPath, 'utf8');
const gesture = fs.readFileSync(gesturePath, 'utf8');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));

function fail(message) {
  console.error('[validate] ' + message);
  process.exit(1);
}

function requireText(source, text, description) {
  if (!source.includes(text)) {
    fail('missing ' + description + ': ' + text);
  }
}

function versionOf(source) {
  return {
    metadata: source.match(
      /^\/\/\s*@version\s+([^\s]+)$/m
    )?.[1],
    runtime: source.match(
      /const VERSION = ['"]([^'"]+)['"];/
    )?.[1],
  };
}

const sharedVersion = versionOf(shared);
const gestureVersion = versionOf(gesture);

if (!sharedVersion.metadata) {
  fail('shared @version not found');
}
if (!sharedVersion.runtime) {
  fail('shared runtime VERSION not found');
}
if (sharedVersion.metadata !== pkg.version) {
  fail('shared @version does not match package.json');
}
if (sharedVersion.runtime !== pkg.version) {
  fail('shared runtime VERSION does not match package.json');
}

if (!gestureVersion.metadata) {
  fail('gesture @version not found');
}
if (!gestureVersion.runtime) {
  fail('gesture runtime VERSION not found');
}
if (gestureVersion.metadata !== gestureVersion.runtime) {
  fail('gesture metadata/runtime versions differ');
}

requireText(
  shared,
  '// @name         ChatGPT Web Unified',
  'shared userscript name'
);
requireText(
  shared,
  '// @match        https://chatgpt.com/*',
  'shared chatgpt.com match'
);
requireText(
  shared,
  '// @run-at       document-start',
  'shared document-start injection'
);
requireText(
  shared,
  '// @grant        none',
  'shared grant none'
);
requireText(
  shared,
  'content-visibility: auto',
  'conservative rendering hint'
);
requireText(
  shared,
  "const liveTurn = streaming ? turns[turns.length - 1] : null;",
  'streaming turn protection'
);
requireText(
  shared,
  "perfLabel.textContent = '常驻平衡优化';",
  'always-on control label'
);
requireText(
  shared,
  'const SETTLE_MS = 2800;',
  'settling window'
);
requireText(
  shared,
  'const READ_DWELL_MS = 1200;',
  'read dwell'
);
requireText(
  shared,
  'new BroadcastChannel(STATE_CHANNEL)',
  'cross-tab state sync'
);
requireText(
  shared,
  "window.addEventListener('storage', onStorageSync)",
  'storage-event sync fallback'
);
requireText(
  shared,
  "attachShadow({ mode: 'open' })",
  'isolated control UI'
);
requireText(
  shared,
  "const GLOBAL_KEY = 'ChatGPTWeb';",
  'shared global API'
);
requireText(
  shared,
  "window[LEGACY_GLOBAL_KEY] = api;",
  'legacy iOS API alias'
);
requireText(
  shared,
  'setNativeStatus',
  'native status API'
);
requireText(
  shared,
  'requestNativeUpdateCheck()',
  'S-triggered native update check'
);
requireText(
  shared,
  "case 'timeout': return '检查超时 · 使用当前版本';",
  'update timeout UI state'
);
requireText(
  shared,
  "failed ? '重试更新'",
  'manual update retry button state'
);
requireText(
  shared,
  "makeInfoRow('脚本版本')",
  'shared script version row'
);
requireText(
  shared,
  "makeInfoRow('iOS 手势')",
  'optional iOS gesture version row'
);
requireText(
  shared,
  'data-cgpt-tool-collapsed',
  'completed tool compaction'
);
requireText(
  shared,
  'optimizeToolGroups(turns, liveTurn)',
  'tool compaction refresh'
);

for (const status of [
  'running',
  'waiting_user',
  'settling',
  'completed_unread',
  'completed_read',
]) {
  requireText(
    shared,
    status,
    'conversation state ' + status
  );
}

const sharedForbidden = [
  ['SIDEBAR_GESTURE', 'iOS gesture config in shared script'],
  ["addEventListener('touchstart'", 'touch gesture listener in shared script'],
  ["addEventListener('touchmove'", 'touch gesture listener in shared script'],
  ['function openSidebar()', 'sidebar opener in shared script'],
  ['function closeSidebar()', 'sidebar closer in shared script'],
  ['function isSidebarOpen()', 'sidebar state detector in shared script'],
  ['ChatGPTIOSGestures', 'iOS gesture global in shared script'],
  ['minTurns', 'length-gated optimization'],
  ['keepRecent', 'legacy recent-turn threshold'],
  ['replaceChildren(', 'DOM replacement'],
  ['.innerHTML =', 'innerHTML replacement'],
  [".removeAttribute('src')", 'media source unloading'],
];

for (const [needle, description] of sharedForbidden) {
  if (shared.includes(needle)) {
    fail('forbidden ' + description + ': ' + needle);
  }
}

requireText(
  gesture,
  '// @name         ChatGPT Web iOS Gestures',
  'iOS gesture userscript name'
);
requireText(
  gesture,
  '// @match        https://chatgpt.com/*',
  'gesture chatgpt.com match'
);
requireText(
  gesture,
  '// @run-at       document-start',
  'gesture document-start injection'
);
requireText(
  gesture,
  '// @grant        none',
  'gesture grant none'
);
requireText(
  gesture,
  "const GLOBAL_KEY = 'ChatGPTIOSGestures';",
  'gesture global API'
);
requireText(
  gesture,
  'const CONFIG = Object.freeze({',
  'gesture tuning config'
);
requireText(
  gesture,
  'edgeStartPx: 96',
  'edge-based swipe start zone'
);
requireText(
  gesture,
  "gesture.edge === 'left'",
  'left-edge swipe semantics'
);
requireText(
  gesture,
  "gesture.edge === 'right'",
  'right-edge swipe semantics'
);
requireText(
  gesture,
  "window.addEventListener('touchstart'",
  'window-capture touchstart listener'
);
requireText(
  gesture,
  "window.addEventListener('touchmove'",
  'window-capture touchmove listener'
);
requireText(
  gesture,
  'function openSidebar()',
  'sidebar opener'
);
requireText(
  gesture,
  'function closeSidebar()',
  'sidebar closer'
);
requireText(
  gesture,
  'function isSidebarOpen()',
  'sidebar state detector'
);
requireText(
  gesture,
  'event.stopImmediatePropagation();',
  'ChatGPT gesture suppression'
);
requireText(
  gesture,
  'window.__CHATGPT_NATIVE__?.hotUpdate',
  'native-only execution gate'
);

const gestureForbidden = [
  ['content-visibility', 'performance logic in gesture script'],
  ['BroadcastChannel', 'conversation state logic in gesture script'],
  ['data-cgpt-tool-collapsed', 'tool compaction in gesture script'],
  ['messageHandlers?.chatGPTNative', 'native update bridge in gesture script'],
];

for (const [needle, description] of gestureForbidden) {
  if (gesture.includes(needle)) {
    fail('forbidden ' + description + ': ' + needle);
  }
}

console.log(JSON.stringify({
  ok: true,
  sharedVersion: pkg.version,
  gestureVersion: gestureVersion.metadata,
  sharedBytes: Buffer.byteLength(shared),
  gestureBytes: Buffer.byteLength(gesture),
  architecture: 'shared runtime + iOS-only gesture runtime',
  sharedSource: sharedPath,
  iosGestureSource: gesturePath,
}, null, 2));
