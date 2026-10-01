import fs from 'node:fs';

const sharedPath =
  'safari/chatgpt-safari.user.js';
const contentViewPath =
  'App/ContentView.swift';
const webViewPath =
  'App/ChatGPTWebView.swift';
const scriptStorePath =
  'App/UnifiedScriptStore.swift';
const projectPath =
  'project.yml';

const shared =
  fs.readFileSync(sharedPath, 'utf8');
const contentView =
  fs.readFileSync(contentViewPath, 'utf8');
const webView =
  fs.readFileSync(webViewPath, 'utf8');
const scriptStore =
  fs.readFileSync(scriptStorePath, 'utf8');
const project =
  fs.readFileSync(projectPath, 'utf8');
const pkg =
  JSON.parse(
    fs.readFileSync('package.json', 'utf8')
  );

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
    metadata:
      source.match(
        /^\/\/\s*@version\s+([^\s]+)$/m
      )?.[1],
    runtime:
      source.match(
        /const VERSION = ['"]([^'"]+)['"];/
      )?.[1],
  };
}

const sharedVersion = versionOf(shared);

if (
  !sharedVersion.metadata ||
  !sharedVersion.runtime ||
  sharedVersion.metadata !== pkg.version ||
  sharedVersion.runtime !== pkg.version
) {
  fail('shared script/package versions differ');
}

requireText(
  contentView,
  'ChatGPTWebView()',
  'WKWebView root'
);

if (
  contentView.includes('SafariContainerView()') ||
  contentView.includes('SafariAutoLaunchView()')
) {
  fail('Safari container is still the active root');
}

requireText(
  webView,
  'import WebKit',
  'WebKit framework'
);
requireText(
  webView,
  'WKWebViewConfiguration()',
  'WKWebView configuration'
);
requireText(
  webView,
  'WKWebsiteDataStore.default()',
  'persistent website data store'
);
requireText(
  webView,
  'webView.isInspectable = true',
  'Safari Web Inspector support'
);
requireText(
  webView,
  'WKScriptMessageHandler',
  'native JavaScript bridge'
);
requireText(
  webView,
  'startHotUpdate(',
  'hot-update runtime'
);
requireText(
  webView,
  'injectCurrentPage: true',
  'immediate current-page hot injection'
);
requireText(
  webView,
  'webViewWebContentProcessDidTerminate',
  'WebKit process recovery'
);
requireText(
  webView,
  'presentExternalWebView(',
  'separate popup browser layer'
);

requireText(
  scriptStore,
  '"hotUpdate": true',
  'native hot-update bootstrap'
);
requireText(
  scriptStore,
  'fetchAllRemoteTexts(',
  'multi-source remote updater'
);
requireText(
  scriptStore,
  'saveCachedScript(',
  'cached runtime'
);

if (
  project.includes(
    '- ChatGPTWebView.swift'
  ) ||
  project.includes(
    '- UnifiedScriptStore.swift'
  )
) {
  fail('WKWebView developer files are still excluded from the app target');
}

requireText(
  shared,
  'const RESULT_ONLY_MODE =',
  'Result Only runtime mode'
);
requireText(
  shared,
  'function processToolMutationNode(node)',
  'tool/MCP process filtering'
);
requireText(
  shared,
  '[data-testid*="reasoning" i]',
  'reasoning render suppression'
);
requireText(
  shared,
  '[data-testid*="thinking" i]',
  'thinking render suppression'
);
requireText(
  shared,
  '[data-testid*="tool-progress" i]',
  'tool-progress suppression'
);
requireText(
  shared,
  'function renderResultOnlyCompletionSummary()',
  'result completion summary'
);
requireText(
  shared,
  'function flushPendingBottomScroll()',
  'event-driven bottom alignment'
);

for (
  const needle of [
    "addEventListener('touchstart'",
    "addEventListener('touchmove'",
    'ChatGPTIOSGestures',
    'INITIAL_BOTTOM_SCROLL_DELAYS',
    'bottomScrollTimers',
  ]
) {
  if (shared.includes(needle)) {
    fail('forbidden runtime token: ' + needle);
  }
}

console.log(
  JSON.stringify(
    {
      ok: true,
      version: pkg.version,
      architecture:
        'WKWebView developer shell + native JS bridge + hot update',
      inspectable: true,
      sharedBytes:
        Buffer.byteLength(shared),
    },
    null,
    2
  )
);
