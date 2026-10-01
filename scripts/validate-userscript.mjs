import fs from 'node:fs';

const sharedPath =
  'safari/chatgpt-safari.user.js';
const contentViewPath =
  'App/ContentView.swift';
const safariContainerPath =
  'App/SafariContainerView.swift';
const projectPath =
  'project.yml';
const actionInfoPath =
  'SafariScriptAction/Info.plist';
const actionHandlerPath =
  'SafariScriptAction/ActionRequestHandler.swift';

const shared =
  fs.readFileSync(sharedPath, 'utf8');
const contentView =
  fs.readFileSync(contentViewPath, 'utf8');
const safariContainer =
  fs.readFileSync(safariContainerPath, 'utf8');
const project =
  fs.readFileSync(projectPath, 'utf8');
const actionInfo =
  fs.readFileSync(actionInfoPath, 'utf8');
const actionHandler =
  fs.readFileSync(actionHandlerPath, 'utf8');
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
  'SafariContainerView()',
  'in-app Safari root'
);

if (
  contentView.includes('SafariAutoLaunchView()') ||
  contentView.includes('ChatGPTWebView()')
) {
  fail('external Safari or WKWebView root is active');
}

requireText(
  safariContainer,
  'import SafariServices',
  'SafariServices framework'
);
requireText(
  safariContainer,
  'SFSafariViewController',
  'in-app Safari controller'
);
requireText(
  safariContainer,
  '.ActivityButton(',
  'script injection action button'
);
requireText(
  safariContainer,
  '"com.masakacj.chatgptweb.scriptaction"',
  'script action extension id'
);

if (
  safariContainer.includes('UIApplication.shared.open(') ||
  safariContainer.includes('WKWebView')
) {
  fail('in-app Safari container must not jump out or use WKWebView');
}

requireText(
  project,
  '- SafariAutoLaunchView.swift',
  'external Safari launcher exclusion'
);
requireText(
  project,
  'ChatGPTScriptAction:',
  'script action target'
);
requireText(
  project,
  'Build Safari Injection Script',
  'script injection resource build'
);
requireText(
  project,
  'ExtensionPreprocessingJS',
  'Safari action preprocessing object'
);
requireText(
  project,
  'window.__CHATGPT_SAFARI_CONTAINER__ = true;',
  'Safari container bootstrap'
);

requireText(
  actionInfo,
  '<string>com.apple.services</string>',
  'Safari action extension point'
);
requireText(
  actionInfo,
  'NSExtensionJavaScriptPreprocessingFile',
  'Safari action preprocessing file'
);
requireText(
  actionInfo,
  '<key>CFBundleExecutable</key>',
  'action executable'
);
requireText(
  actionHandler,
  'NSExtensionRequestHandling',
  'action request handler'
);

requireText(
  shared,
  'const IS_SAFARI_CONTAINER =',
  'Safari container mode'
);
requireText(
  shared,
  'IS_SAFARI_CONTAINER ||',
  'Safari minimal runtime mode'
);
requireText(
  shared,
  'function showSafariInjectionConfirmation(',
  'visible Safari injection confirmation'
);
requireText(
  shared,
  "'优化已启用'",
  'first injection confirmation text'
);
requireText(
  shared,
  "'优化已重新加载'",
  'reinjection confirmation text'
);
requireText(
  shared,
  'window.__CHATGPT_UNIFIED_INJECTED__ = {',
  'injection diagnostic marker'
);
requireText(
  shared,
  "'data-cgpt-runtime-version'",
  'DOM runtime version marker'
);

requireText(
  shared,
  'function processToolMutationNode(node)',
  'tool/MCP optimization'
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
        'in-app SFSafariViewController + script Action Extension',
      sharedBytes:
        Buffer.byteLength(shared),
    },
    null,
    2
  )
);
