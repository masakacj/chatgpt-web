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
  "HOST.endsWith('.chatgpt.com')",
  'shared ChatGPT host gate'
);
requireText(
  shared,
  'const ChatGPTDOMAdapter =',
  'central ChatGPT DOM adapter'
);
requireText(
  shared,
  'function turnCandidates(force = false)',
  'cached turn discovery'
);
requireText(
  shared,
  'state.turnCacheDirty',
  'incremental turn cache invalidation'
);
requireText(
  shared,
  'const EXTREME_NATIVE_MODE =',
  'native subtractive performance mode'
);
requireText(
  shared,
  'data-cgpt-tool-hidden',
  'native static process hiding'
);
requireText(
  shared,
  'const INITIAL_BOTTOM_SCROLL_DELAYS = [',
  'fixed bottom-scroll schedule'
);
requireText(
  shared,
  "perfLabel.textContent = '极速模式';",
  'extreme mode setting label'
);
requireText(
  shared,
  'function bindScopedObservers(',
  'scoped conversation/sidebar observers'
);
requireText(
  shared,
  'overscroll-behavior-y: none',
  'hard vertical overscroll boundary'
);
requireText(
  shared,
  'state.conversationObserver.observe(',
  'conversation-root observer'
);
requireText(
  shared,
  'state.sidebarObserver.observe(',
  'sidebar-root observer'
);
requireText(
  shared,
  'function scheduleStateEvaluation(',
  'debounced event-driven state evaluation'
);
requireText(
  shared,
  'function schedulePhaseTwoRuntime()',
  'two-phase startup'
);
requireText(
  shared,
  'window.requestIdleCallback',
  'idle-delayed heavy runtime startup'
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
  'function completionStatusForCurrentView(id)',
  'visible completion read-state helper'
);
requireText(
  shared,
  'function shouldRenderConversationState(id, status)',
  'active unread-dot suppression helper'
);
requireText(
  shared,
  'function sameConversationCycle(left, right)',
  'cross-tab generation-cycle helper'
);
requireText(
  shared,
  'sameConversationCycle(current, record)',
  'read state downgrade protection'
);
requireText(
  shared,
  'const nextStatus = completionStatusForCurrentView(id);',
  'visible completion direct-read transition'
);
requireText(
  shared,
  'next.runStartedAt = now;',
  'generation cycle timestamp'
);
requireText(
  shared,
  "window.addEventListener('storage', onStorageSync)",
  'storage-event sync fallback'
);
requireText(
  shared,
  'if (!EXTREME_NATIVE_MODE) {\n    setupConversationStateSync();',
  'desktop-only cross-tab state sync'
);
requireText(
  shared,
  "attachShadow({ mode: 'open' })",
  'isolated control UI'
);
requireText(
  shared,
  'function nativeAnchorSupported()',
  'native anchor capability gate'
);
requireText(
  shared,
  'function toggleNativePanel(anchor)',
  'native-anchor script panel bridge'
);
requireText(
  shared,
  'function nativePanelRenderState()',
  'native panel rendered-state self-check'
);
requireText(
  shared,
  'state.ui?.update',
  'native panel update-action readiness'
);
requireText(
  shared,
  'state.ui?.clearCache',
  'native panel cache-action readiness'
);
requireText(
  shared,
  'function closeNativePanel()',
  'native-anchor panel close bridge'
);
requireText(
  shared,
  'shadow.append(style, panel);',
  'native-anchor direct panel mount'
);
requireText(
  shared,
  "'ChatGPT Web 菜单'",
  'script panel dialog accessibility'
);
requireText(
  shared,
  "panel.setAttribute(\n      'aria-hidden',",
  'script panel visibility accessibility'
);
requireText(
  shared,
  "'ChatGPT Web 控制'",
  'fallback browser control accessibility'
);
requireText(
  shared,
  "'clear-cache'",
  'script-owned cache action bridge'
);
requireText(
  shared,
  "'pointermove'",
  'script-owned draggable control'
);
requireText(
  shared,
  'function ensureControlMounted()',
  'self-healing script control mount'
);
requireText(
  shared,
  'function scheduleControlRecovery(',
  'script control recovery scheduler'
);
requireText(
  shared,
  'cleanupDetachedControl();',
  'detached control cleanup'
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
  "update.textContent = '检查更新';",
  'single explicit update action'
);
requireText(
  shared,
  "settings.textContent = '设置';",
  'settings entry in first-layer menu'
);
requireText(
  shared,
  "reload.textContent = '重新加载 ChatGPT';",
  'first-layer reload action'
);
requireText(
  shared,
  "case 'timeout': return '检查超时 · 使用当前版本';",
  'update timeout UI state'
);
requireText(
  shared,
  "'重试检查更新'",
  'manual update retry button state'
);
requireText(
  shared,
  "makeInfoRow('脚本')",
  'settings script version row'
);
requireText(
  shared,
  "makeInfoRow('容器')",
  'settings container version row'
);
requireText(
  shared,
  "makeInfoRow('iOS 手势')",
  'optional iOS gesture version row'
);
requireText(
  shared,
  'function processToolMutationNode(node)',
  'one-shot process node classification'
);
requireText(
  shared,
  'data-cgpt-tool-summary-only',
  'summary-only tool rendering'
);
requireText(
  shared,
  'function compactToolSummary(label)',
  'compact tool/MCP name extraction'
);
requireText(
  shared,
  "data-cgpt-static",
  'static no-animation native mode'
);
requireText(
  shared,
  'SIDEBAR_DEEP_RESET_COOKIE',
  'one-time deep sidebar client-state reset'
);
requireText(
  shared,
  'localStorage.clear();',
  'deep client local state cleanup'
);
requireText(
  shared,
  'indexedDB.databases()',
  'deep IndexedDB cleanup'
);
requireText(
  shared,
  'caches.keys()',
  'deep CacheStorage cleanup'
);
requireText(
  shared,
  "processToolMutationNode(node);",
  'added-node-only process handling'
);
requireText(
  shared,
  'conversationLinks: new Map()',
  'indexed sidebar conversation links'
);
requireText(
  shared,
  'diagnostics: {',
  'runtime diagnostic state'
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
  ['nodes.some((other, otherIndex)', 'quadratic turn containment scan'],
  ['state.observer.observe(document.documentElement', 'global documentElement subtree observer'],
  ['IOS_TOOL_SWEEP_MS', 'periodic whole-thread tool sweep'],
  ['replaceChildren(', 'DOM replacement'],
  ['.innerHTML =', 'innerHTML replacement'],
  [".removeAttribute('src')", 'media source unloading'],
  ['开始性能诊断', 'manual debug UI in subtractive runtime'],
  ['检查 IPA 更新', 'separate IPA update action'],
  ['scheduleToolScan(', 'repeated tool rescan scheduler'],
  ['data-cgpt-passive-turn', 'intrinsic-height passive turn virtualization'],
  ['contain-intrinsic-size: auto 320px', 'estimated historical turn height'],
  ['conversationScroller(', 'dynamic scroll-container probing'],
  ['animation: cgpt-safari-pulse', 'sidebar pulse animation'],
  ['aggressiveWindowing', 'removed second virtualization setting'],
  ['new IntersectionObserver(', 'removed second virtualization observer'],
  ['data-cgpt-windowed', 'removed second virtualization marker'],
  ['scheduleRefresh(', 'removed redundant performance refresh pipeline'],
  ['data-cgpt-tool-collapsed', 'removed legacy tool collapse mode'],
  ['function registerToolGroup(', 'removed legacy tool group pipeline'],
  ['function toolSummary(', 'removed legacy tool summary pipeline'],
  ['function finalizeTrackedToolGroups(', 'removed legacy tool finalizer'],
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
  "HOST.endsWith('.chatgpt.com')",
  'gesture ChatGPT host gate'
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
  'triggerPx: 8',
  'fast edge swipe trigger'
);
requireText(
  gesture,
  'axisRatio: 0.72',
  'responsive horizontal intent threshold'
);
requireText(
  gesture,
  'twoFingerTriggerPx: 6',
  'two-finger global scroll threshold'
);
requireText(
  gesture,
  'twoFingerNavTriggerPx: 42',
  'two-finger navigation threshold'
);
requireText(
  gesture,
  "scroll.mode = 'navigation'",
  'two-finger horizontal mode lock'
);
requireText(
  gesture,
  "if (totalDx <= -CONFIG.twoFingerNavTriggerPx) {\n          window.history.forward();",
  'two-finger left swipe forward'
);
requireText(
  gesture,
  "} else if (totalDx >= CONFIG.twoFingerNavTriggerPx) {\n          window.history.back();",
  'two-finger right swipe back'
);
requireText(
  gesture,
  'function globalScrollCandidates',
  'global scroll candidate discovery'
);
requireText(
  gesture,
  'function pickScrollContainer',
  'dynamic scroll-container selection'
);
requireText(
  gesture,
  'return null;',
  'directional scroll boundary stop'
);
requireText(
  gesture,
  'document.elementsFromPoint',
  'touch-point scroll targeting'
);
requireText(
  gesture,
  'function beginTwoFingerScroll',
  'two-finger scroll start'
);
requireText(
  gesture,
  'function moveTwoFingerScroll',
  'two-finger scroll movement'
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
  'function findSidebarDrawer()',
  'robust sidebar drawer detector'
);
requireText(
  gesture,
  'function dispatchEscape()',
  'escape close fallback'
);
requireText(
  gesture,
  'function clickSidebarBackdrop()',
  'backdrop close fallback'
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
  "function openSidebar() {\n    return clickFirst([",
  'direct sidebar open fast path'
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
  "} else if (rightEdgeClose) {\n      closeSidebar();",
  'unconditional right-edge close attempt'
);
requireText(
  gesture,
  'window.__CHATGPT_NATIVE__?.hotUpdate',
  'native-only execution gate'
);
requireText(
  gesture,
  'function eventTargetsScriptControl(event)',
  'gesture exclusion for script-owned control'
);
requireText(
  gesture,
  'function eventTargetsInteractiveControl(',
  'gesture exclusion for interactive controls'
);
requireText(
  gesture,
  "window.addEventListener('touchstart', start, {\n      passive: true,",
  'passive touchstart for zero-cost taps'
);

const gestureForbidden = [
  ['if (isSidebarOpen()) return true;', 'eager sidebar-open layout check'],
  ["open: isSidebarOpen()", 'eager sidebar layout query on edge touchstart'],
  ["window.addEventListener('touchstart', start, {\n      passive: false,", 'blocking touchstart listener'],
  ['content-visibility', 'performance logic in gesture script'],
  ['BroadcastChannel', 'conversation state logic in gesture script'],
  ['data-cgpt-tool-collapsed', 'tool compaction in gesture script'],
  ['messageHandlers?.chatGPTNative', 'native update bridge in gesture script'],
  ['const next = pickScrollContainer(', 'scroll chaining beyond the active container'],
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
