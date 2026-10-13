# ChatGPT Web Optimized Product Contract

Date: 2026-10-13
Status: approved product definition; implementation not started

## One sentence

**ChatGPT Web Optimized is an independent iOS WKWebView app that runs ChatGPT locally in its own app sandbox and uses native Swift to provide PC-Conversation-Manager-equivalent state safety, lifecycle recovery, diagnostics and measured performance discipline wherever WebKit permits.**

## Product identity

- Display name: `ChatGPT Web Optimized`
- Target/scheme: `ChatGPTWebOptimized`
- Bundle ID: `com.masakacj.chatgptweb.optimized`
- Initial version/build: `0.1.0 (1)`
- Repository: same `masakacj/chatgpt-web` repository
- Installation: side by side with the existing `ChatGPT Web` mirror app
- Platform: iOS 17+, iPhone

## Mandatory isolation

Web Optimized has its own:

- app sandbox;
- persistent `WKWebsiteDataStore.default()`;
- first-time ChatGPT login;
- Keychain namespace;
- UserDefaults keys;
- Application Support directory;
- app icon, scheme, version and build;
- signing App ID/profile;
- install-center key, candidate/stable pointer and rollback archive;
- tests and release evidence.

It does not use App Groups, shared Keychain access groups, shared containers, cross-app migration or shared WebKit process/data stores.

It must not read or write mirror namespaces such as:

- `PCCompanion.*`
- `SharedPC.*`
- `SharedPCCompanion/`
- `ChatGPTWeb.PCCompanion.v1`
- `ChatGPTWebUnified/`

## Included scope

- persistent ChatGPT WKWebView login;
- ordinary and project conversations;
- ChatGPT-native composer, messages, tools and attachments;
- one native Swift Conversation Manager owner;
- observation-only isolated-world JavaScript;
- turn/document/sequence/revision safety;
- durable state and read evidence;
- explicit user-confirmed native Retry for verified load-error UI;
- explicit user-confirmed WebContent-process recovery;
- popup, upload, download and media-permission policies;
- local redacted diagnostics and performance metrics;
- optional Web Inspector through an explicit developer diagnostics setting.

## Excluded scope

- SharedTab or PC Bridge transport;
- structured mirror UI;
- PC pairing, remote drafts, remote Send or command receipts;
- Safari Action, Safari Web Extension or SFSafariViewController;
- old userscript hot update;
- Result Only, historical DOM pruning, iframe blocking or alternate rendering;
- fetch/XHR monkey patches;
- local HTTPS proxy or request interception;
- request replay;
- automatic full-page reload;
- automatic Regenerate, tool Retry or MCP actions;
- cross-app login, Cookie, Keychain, draft, receipt or state migration;
- remote telemetry by default.

## Conversation Manager parity definition

“PC Chrome-equivalent” means semantic and safety parity where the platform supplies equivalent evidence:

- the same event vocabulary and conservative task/read model;
- stale/duplicate/wrong-document/wrong-generation rejection;
- no completion inference from silence;
- answer-body evidence before completion;
- bounded persistence and owner generation;
- native-only webpage presentation;
- no destructive performance interventions;
- privacy-bounded diagnostics;
- no unsafe network replay.

It does **not** mean that WKWebView has Chrome `webRequest`. The app must not claim exact saved-conversation GET recovery when WebKit cannot provide trustworthy internal-request evidence.

## Loading recovery contract

When the observer reports a visible, empty, current-document official conversation-load error with its own Retry button:

1. Swift records `manualConfirmationRequired`.
2. Native UI asks the user to retry.
3. Before showing and immediately before execution, the app verifies route, document, sequence, visibility, error panel, exact Retry button and the absence of draft/running/waiting/approval/answer blockers.
4. One confirmation may click that exact official Retry once.
5. At most two confirmed attempts are allowed per five minutes.
6. There is no delayed or automatic retry.
7. No request is constructed or replayed.
8. If the official button cannot be verified, no click occurs.

WebContent-process termination is a separate failure class. It invalidates the document generation and may rebuild the WebView only after explicit confirmation; it must never be described as saved-conversation GET recovery.

## Visual contract

- ChatGPT remains the sole visual authority inside the webpage.
- The observer adds no styles, badges, state attributes or hidden native markers.
- Native Swift may show diagnostics, retry confirmation and process-recovery UI outside the webpage DOM.

## Release boundary

Web Optimized may not become stable until a signed candidate passes the physical-iPhone acceptance matrix. Simulator, compilation, signing, installation or HTTP checks do not substitute for real-device acceptance.

The existing mirror product, IPA, PC Bridge route and user data remain unchanged throughout Web Optimized development.
