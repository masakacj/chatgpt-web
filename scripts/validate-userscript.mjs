import fs from 'node:fs';

const sharedPath =
  'safari/chatgpt-safari.user.js';
const contentViewPath =
  'App/ContentView.swift';
const launchViewPath =
  'App/SafariAutoLaunchView.swift';
const projectPath =
  'project.yml';
const extensionInfoPath =
  'SafariWebExtension/Info.plist';
const extensionHandlerPath =
  'SafariWebExtension/SafariWebExtensionHandler.swift';
const manifestPath =
  'SafariWebExtension/manifest.json';

const shared =
  fs.readFileSync(
    sharedPath,
    'utf8'
  );
const contentView =
  fs.readFileSync(
    contentViewPath,
    'utf8'
  );
const launchView =
  fs.readFileSync(
    launchViewPath,
    'utf8'
  );
const project =
  fs.readFileSync(
    projectPath,
    'utf8'
  );
const extensionInfo =
  fs.readFileSync(
    extensionInfoPath,
    'utf8'
  );
const extensionHandler =
  fs.readFileSync(
    extensionHandlerPath,
    'utf8'
  );
const manifest =
  JSON.parse(
    fs.readFileSync(
      manifestPath,
      'utf8'
    )
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
    pkg.version ||
  manifest.version !==
    pkg.version
) {
  fail(
    'shared/package/manifest versions differ'
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
  'Safari extension mode'
);
requireText(
  shared,
  'window.__CHATGPT_SAFARI_CONTAINER__ === true',
  'Safari extension bootstrap flag'
);
requireText(
  shared,
  'IS_SAFARI_CONTAINER ||',
  'Safari extreme mode'
);
requireText(
  shared,
  'IS_SAFARI_CONTAINER ||\n      (',
  'Safari control suppression'
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

const forbiddenShared = [
  "addEventListener('touchstart'",
  "addEventListener('touchmove'",
  'ChatGPTIOSGestures',
  'INITIAL_BOTTOM_SCROLL_DELAYS',
  'bottomScrollTimers',
];

for (
  const needle of forbiddenShared
) {
  if (shared.includes(needle)) {
    fail(
      'forbidden shared runtime token: ' +
      needle
    );
  }
}

requireText(
  contentView,
  'SafariAutoLaunchView()',
  'Safari launcher root'
);

if (
  contentView.includes(
    'SafariContainerView()'
  ) ||
  contentView.includes(
    'ChatGPTWebView()'
  )
) {
  fail(
    'legacy embedded browser root is active'
  );
}

requireText(
  launchView,
  'UIApplication.shared.open(',
  'system browser launch'
);
requireText(
  launchView,
  'https://chatgpt.com/',
  'ChatGPT launch URL'
);
requireText(
  launchView,
  '.contains("--ui-testing")',
  'UI-test launch suppression'
);

requireText(
  project,
  '- SafariContainerView.swift',
  'legacy Safari view exclusion'
);
requireText(
  project,
  '- ChatGPTWebView.swift',
  'legacy WKWebView exclusion'
);
requireText(
  project,
  '- UnifiedScriptStore.swift',
  'legacy store exclusion'
);
requireText(
  project,
  'ChatGPTSafariWebExtension:',
  'Safari web extension target'
);
requireText(
  project,
  'embed: true',
  'embedded web extension'
);
requireText(
  project,
  'Build Safari Web Extension Resources',
  'web extension resource build'
);
requireText(
  project,
  'window.__CHATGPT_SAFARI_CONTAINER__ = true;',
  'automatic content bootstrap'
);
requireText(
  project,
  'content.js',
  'automatic content script output'
);
requireText(
  project,
  'manifest.json',
  'web extension manifest output'
);

requireText(
  extensionInfo,
  '<string>com.apple.Safari.web-extension</string>',
  'Safari web extension point'
);
requireText(
  extensionInfo,
  'SafariWebExtensionHandler',
  'Safari web extension handler'
);
requireText(
  extensionInfo,
  '<key>CFBundleExecutable</key>',
  'extension executable'
);
requireText(
  extensionHandler,
  'NSExtensionRequestHandling',
  'native web extension handler'
);

if (
  manifest.manifest_version !== 3
) {
  fail(
    'Safari web extension must use manifest v3'
  );
}

const contentScripts =
  manifest.content_scripts || [];

if (contentScripts.length !== 1) {
  fail(
    'expected one automatic content script'
  );
}

const contentScript =
  contentScripts[0];

if (
  contentScript.run_at !==
    'document_start'
) {
  fail(
    'content script must run at document_start'
  );
}

const expectedMatch =
  'https://chatgpt.com/*';

if (
  !contentScript.matches
    ?.includes(expectedMatch) ||
  !contentScript.js
    ?.includes('content.js')
) {
  fail(
    'content script must target chatgpt.com with content.js'
  );
}

if (
  !manifest.host_permissions
    ?.includes(expectedMatch)
) {
  fail(
    'manifest host permission missing chatgpt.com'
  );
}

console.log(
  JSON.stringify(
    {
      ok: true,
      version: pkg.version,
      architecture:
        'system Safari + automatic Safari Web Extension content script',
      sharedBytes:
        Buffer.byteLength(shared),
      runAt:
        contentScript.run_at,
    },
    null,
    2
  )
);
