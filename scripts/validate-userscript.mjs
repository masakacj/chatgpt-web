import fs from 'node:fs';

const sharedPath = 'safari/chatgpt-safari.user.js';
const swiftPath = 'App/ChatGPTWebView.swift';
const storePath = 'App/UnifiedScriptStore.swift';

const shared = fs.readFileSync(sharedPath, 'utf8');
const swift = fs.readFileSync(swiftPath, 'utf8');
const store = fs.readFileSync(storePath, 'utf8');
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
  store,
  '"nativeGestures": false',
  'native gesture capability disabled'
);

const gestureArtifacts = [
  [shared, 'ChatGPTIOSGestures', 'gesture global in shared script'],
  [shared, 'gestureVersion', 'gesture version in shared script'],
  [store, 'gestureScriptPath', 'gesture script path in native store'],
  [store, 'bestLocalGestureScript', 'gesture cache selection'],
  [store, 'fetchLatestGestureScript', 'gesture remote update'],
  [store, 'gestureVersion', 'gesture version status'],
  [swift, 'UIGestureRecognizer', 'custom native gesture recognizer'],
  [swift, 'UIPanGestureRecognizer', 'custom native pan gesture'],
  [swift, 'ChatGPTEdgeSwipeGestureRecognizer', 'native edge swipe recognizer'],
  [swift, 'onDragBegan', 'floating control drag gesture'],
  [swift, 'onDragChanged', 'floating control drag gesture'],
  [swift, 'onDragEnded', 'floating control drag gesture'],
  [swift, 'handleBrowserControlPan', 'external browser drag gesture'],
  [swift, 'leftSidebarEdgeGesture', 'left sidebar gesture'],
  [swift, 'rightSidebarEdgeGesture', 'right sidebar gesture'],
  [swift, 'twoFingerNavigationGesture', 'two-finger navigation gesture'],
];

for (
  const [source, needle, description]
    of gestureArtifacts
) {
  if (source.includes(needle)) {
    fail(
      'forbidden ' +
      description +
      ': ' +
      needle
    );
  }
}

requireText(
  shared,
  'const HAS_NATIVE_LIFECYCLE =',
  'native lifecycle capability gate'
);
requireText(
  shared,
  'function nativeLifecycle(',
  'native lifecycle runtime entrypoint'
);
requireText(
  shared,
  'function suspendRuntime()',
  'native background suspension'
);
requireText(
  shared,
  'function resumeRuntime(',
  'native foreground recovery'
);
requireText(
  shared,
  'function pauseTelemetryForLifecycle()',
  'background telemetry pause'
);
requireText(
  shared,
  'function resumeTelemetryForLifecycle()',
  'foreground telemetry resume'
);
requireText(
  shared,
  'if (!HAS_NATIVE_LIFECYCLE) {\n      document.addEventListener(',
  'visibility fallback only for non-native lifecycle'
);
requireText(
  store,
  '"nativeLifecycle": true',
  'native lifecycle capability bootstrap'
);
requireText(
  store,
  '"lowPowerMode":',
  'native low power mode state'
);
requireText(
  store,
  '"thermalState":',
  'native thermal state'
);
requireText(
  swift,
  'UIApplication\n                        .didEnterBackgroundNotification',
  'native background notification'
);
requireText(
  swift,
  'UIApplication\n                        .didBecomeActiveNotification',
  'native active notification'
);
requireText(
  swift,
  'NSProcessInfoPowerStateDidChange',
  'native low power state notification'
);
requireText(
  swift,
  'thermalStateDidChangeNotification',
  'native thermal state notification'
);

if (
  store.includes(
    'const next = (json);'
  ) ||
  store.includes(
    'api?.nativeLifecycle?.(\n            (String(reflecting: phase))'
  )
) {
  fail(
    'forbidden broken native lifecycle interpolation'
  );
}

requireText(
  shared,
  'function flushPendingBottomScroll()',
  'event-driven native bottom scroll'
);
requireText(
  shared,
  'pendingBottomConversationId',
  'pending native bottom scroll state'
);
requireText(
  shared,
  'EXTREME_NATIVE_MODE ||\n      state.statusTimer',
  'native conversation-state heartbeat disabled'
);
requireText(
  shared,
  'if (!EXTREME_NATIVE_MODE) {\n      evaluateConversationState();',
  'desktop-only phase conversation-state evaluation'
);
requireText(
  shared,
  'if (turnStructureChanged) {\n      flushPendingBottomScroll();',
  'turn-driven bottom alignment'
);

if (
  shared.includes(
    'INITIAL_BOTTOM_SCROLL_DELAYS'
  ) ||
  shared.includes(
    'bottomScrollTimers'
  ) ||
  shared.includes(
    '700,\n  ];'
  )
) {
  fail(
    'forbidden timer-driven duplicate bottom scrolling'
  );
}

requireText(
  shared,
  'const SEND_CONTROL_QUERY = [',
  'send control fast selector'
);
requireText(
  shared,
  'function onSendPointerDown(event)',
  'send pointer acknowledgement'
);
requireText(
  shared,
  "type: 'send-touch-ack'",
  'native send haptic message'
);
requireText(
  shared,
  '[data-cgpt-send-ack="1"]',
  'instant send visual acknowledgement'
);
requireText(
  swift,
  'case "send-touch-ack":',
  'native send haptic handler'
);
requireText(
  swift,
  'webView.topAnchor.constraint(\n                equalTo:\n                    safeAreaLayoutGuide\n                        .topAnchor',
  'WebView top safe-area constraint'
);

if (
  swift.includes(
    'webView.topAnchor.constraint(\n                equalTo: topAnchor'
  )
) {
  fail(
    'forbidden WebView top-edge overlap with status area'
  );
}

console.log(JSON.stringify({
  ok: true,
  sharedVersion: pkg.version,
  sharedBytes: Buffer.byteLength(shared),
  architecture: 'shared runtime + gesture-free iOS shell',
  sharedSource: sharedPath,
}, null, 2));
