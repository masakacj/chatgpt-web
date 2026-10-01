import fs from 'node:fs';

const sharedPath =
  'safari/chatgpt-safari.user.js';
const safariContainerPath =
  'App/SafariContainerView.swift';
const contentViewPath =
  'App/ContentView.swift';
const projectPath =
  'project.yml';
const actionInfoPath =
  'SafariScriptAction/Info.plist';
const actionHandlerPath =
  'SafariScriptAction/ActionRequestHandler.swift';

const shared =
  fs.readFileSync(sharedPath, 'utf8');
const safariContainer =
  fs.readFileSync(
    safariContainerPath,
    'utf8'
  );
const contentView =
  fs.readFileSync(
    contentViewPath,
    'utf8'
  );
const project =
  fs.readFileSync(
    projectPath,
    'utf8'
  );
const actionInfo =
  fs.readFileSync(
    actionInfoPath,
    'utf8'
  );
const actionHandler =
  fs.readFileSync(
    actionHandlerPath,
    'utf8'
  );
const pkg =
  JSON.parse(
    fs.readFileSync(
      'package.json',
      'utf8'
    )
  );

function fail(message) {
  console.error(
    '[validate] ' + message
  );
  process.exit(1);
}

function requireText(
  source,
  text,
  description
) {
  if (!source.includes(text)) {
    fail(
      'missing ' +
      description +
      ': ' +
      text
    );
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

const sharedVersion =
  versionOf(shared);

if (
  !sharedVersion.metadata ||
  !sharedVersion.runtime
) {
  fail(
    'shared script version missing'
  );
}

if (
  sharedVersion.metadata !==
    pkg.version ||
  sharedVersion.runtime !==
    pkg.version
) {
  fail(
    'shared script/package versions differ'
  );
}

requireText(
  shared,
  '// @name         ChatGPT Web Unified',
  'unified userscript'
);
requireText(
  shared,
  '// @match        https://chatgpt.com/*',
  'ChatGPT URL match'
);
requireText(
  shared,
  'const IS_SAFARI_CONTAINER =',
  'Safari container mode'
);
requireText(
  shared,
  'window.__CHATGPT_SAFARI_CONTAINER__ === true',
  'Safari injection bootstrap flag'
);
requireText(
  shared,
  'IS_SAFARI_CONTAINER ||',
  'Safari extreme mode'
);
requireText(
  shared,
  'function createControl()',
  'control function'
);
requireText(
  shared,
  'IS_SAFARI_CONTAINER ||\n      (',
  'Safari container control suppression'
);
requireText(
  shared,
  'function processToolMutationNode(node)',
  'tool/MCP DOM optimization'
);
requireText(
  shared,
  'data-cgpt-tool-summary-only',
  'summary-only tool rendering'
);
requireText(
  shared,
  'function flushPendingBottomScroll()',
  'event-driven bottom alignment'
);
requireText(
  shared,
  'function onSendPointerDown(event)',
  'send touch acknowledgement'
);

const sharedForbidden = [
  [
    "addEventListener('touchstart'",
    'custom touch gesture'
  ],
  [
    "addEventListener('touchmove'",
    'custom touch gesture'
  ],
  [
    'ChatGPTIOSGestures',
    'legacy gesture runtime'
  ],
  [
    'INITIAL_BOTTOM_SCROLL_DELAYS',
    'duplicate bottom timers'
  ],
  [
    'bottomScrollTimers',
    'duplicate bottom timers'
  ],
];

for (
  const [needle, description]
    of sharedForbidden
) {
  if (shared.includes(needle)) {
    fail(
      'forbidden ' +
      description +
      ': ' +
      needle
    );
  }
}

requireText(
  contentView,
  'SafariContainerView()',
  'Safari root view'
);

if (
  contentView.includes(
    'ChatGPTWebView()'
  )
) {
  fail(
    'WKWebView root is still active'
  );
}

requireText(
  safariContainer,
  'import SafariServices',
  'SafariServices framework'
);
requireText(
  safariContainer,
  'SFSafariViewController',
  'Safari view controller'
);
requireText(
  safariContainer,
  '.ActivityButton(',
  'script injection activity button'
);
requireText(
  safariContainer,
  '"com.masakacj.chatgptweb.scriptaction"',
  'script action extension id'
);
requireText(
  safariContainer,
  'modalPresentationStyle =\n            .fullScreen',
  'modal Safari presentation'
);

if (
  safariContainer.includes(
    'WKWebView'
  )
) {
  fail(
    'Safari container must not use WKWebView'
  );
}

requireText(
  project,
  'ChatGPTWebView.swift',
  'legacy WKWebView exclusion'
);
requireText(
  project,
  'UnifiedScriptStore.swift',
  'legacy store exclusion'
);
requireText(
  project,
  'ChatGPTScriptAction:',
  'script action target'
);
requireText(
  project,
  'type: app-extension',
  'action extension target type'
);
requireText(
  project,
  'embed: true',
  'embedded script action'
);
requireText(
  project,
  'Build Safari Injection Script',
  'generated injection script'
);
requireText(
  project,
  'window.__CHATGPT_SAFARI_CONTAINER__ = true;',
  'injection bootstrap'
);
requireText(
  project,
  'ExtensionPreprocessingJS',
  'Safari preprocessing object'
);

requireText(
  actionInfo,
  '<key>CFBundleExecutable</key>',
  'extension executable key'
);

requireText(
  actionInfo,
  '<string>com.apple.services</string>',
  'non-UI action extension point'
);
requireText(
  actionInfo,
  'NSExtensionJavaScriptPreprocessingFile',
  'JavaScript preprocessing file'
);
requireText(
  actionInfo,
  'NSExtensionActivationSupportsWebPageWithMaxCount',
  'webpage activation'
);
requireText(
  actionInfo,
  '<string>InjectChatGPT</string>',
  'injection script name'
);

requireText(
  actionHandler,
  'NSExtensionRequestHandling',
  'action request handler'
);
requireText(
  actionHandler,
  'context.completeRequest(',
  'non-UI completion'
);

console.log(
  JSON.stringify(
    {
      ok: true,
      version: pkg.version,
      architecture:
        'SFSafariViewController + Action Extension script injection',
      sharedBytes:
        Buffer.byteLength(shared),
    },
    null,
    2
  )
);
