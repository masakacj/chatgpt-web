# ChatGPT Web Optimized Architecture

Date: 2026-10-13
Status: planned architecture; no target or runtime exists yet

## Repository and target layout

```text
App/                              existing mirror target
Resources/                        existing mirror resources
OptimizedApp/                     new target only
  Application/
  Web/
  ConversationManager/
  Platform/
  Diagnostics/
OptimizedResources/
  Assets.xcassets
  Observation/
Contracts/ConversationManager/v2/ test-only cross-platform semantics
OptimizedTests/
OptimizedUITests/
```

`project.yml` must explicitly prevent target crossover. `ChatGPTWebOptimized` must not depend on `ChatGPTScriptAction` or compile any SharedTab/PCCompanion/Bridge source. The existing mirror must not compile `OptimizedApp` or `OptimizedResources`.

## Runtime ownership

```text
WKWebView official ChatGPT DOM
  → isolated-world observation adapter (facts only)
  → trusted Swift message gateway
  → ConversationManagerOwner actor (sole reducer/writer)
  → CMStore versioned envelope
  → immutable native projection / diagnostics / manual recovery UI
```

### Observation adapter

The JavaScript adapter is not a state manager. It may emit only bounded facts:

- conversation ID;
- document epoch and monotonic sequence;
- turn key and explicit new-turn evidence;
- native turn state;
- answer-ready boolean;
- visible/selected flags;
- draft/running/waiting/approval booleans;
- route/submit/stop/input lifecycle events;
- verified empty load-error panel and exact Retry-button existence.

It must not:

- retain durable records;
- read message or draft text;
- inspect Cookie/token/header/body data;
- write localStorage;
- paint or hide webpage UI;
- click anything without a fresh native authorization;
- wrap fetch/XHR;
- modify React-owned DOM or history;
- infer completion from silence.

### Swift owner

One `ConversationManagerOwner` actor owns:

- event validation and normalization;
- owner generation;
- conversation/turn/document/sequence/revision checks;
- task/read/evidence state;
- bounded seen-event IDs;
- persistence;
- stale-active projection;
- manual-recovery budget;
- redacted audit counters.

WK JavaScript and SwiftUI never write CM state directly.

### Storage

Use one versioned Application Support envelope containing:

- schema/protocol/CM version;
- persisted owner generation;
- records;
- recovery budgets;
- bounded audit counters.

The state is nonsecret and does not belong in Keychain. Authentication stays in the new app's independent WKWebsiteDataStore. Any app-specific credential uses a new optimized-only Keychain service.

## PC CM semantic contract

Create `Contracts/ConversationManager/v2` as content-free JSON fixtures. Swift and PC Node tests consume byte-identical vendored cases and must produce identical decisions/projections.

Contract topics:

- event privacy and canonical status;
- running/waiting/completed/error/stopped/unknown;
- task/read separation;
- submit/new turn and late old answer;
- completion awaiting mounted answer;
- read acknowledgement;
- duplicate/out-of-order/stale sequence/wrong generation;
- ambiguous turn and terminal regression;
- cancellation error versus ordinary stop;
- restore active state as unknown;
- URL/failure/recovery-policy classification.

The JSON corpus is a test contract only. No JavaScript reducer is embedded as production shared runtime.

## WKWebView configuration

- new app's persistent default website data store;
- dedicated process pool within the optimized app only;
- dedicated `WKUserContentController`;
- named `WKContentWorld("ChatGPTWebOptimized.Observation.v1")`;
- strict main-frame, HTTPS, `chatgpt.com` origin and current-document checks;
- Release Web Inspector off by default;
- no remote userscript updates;
- no Safari Action dependency;
- no mirror/Bridge code.

## Recovery model

### Official load-error Retry

The observer may identify an official empty conversation-load panel and its own Retry button. That produces a candidate, not authorization. Swift requires explicit user confirmation, then asks the current adapter to revalidate and click the same button once.

No network request is captured, constructed or replayed. The action is recorded as `user_confirmed_native_retry`.

### WebContent process recovery

On process termination:

- invalidate the document epoch;
- retain native CM state and diagnostics;
- retire the old adapter;
- show native recovery UI;
- rebuild the WebView only after confirmation;
- enforce a bounded budget and stop instead of looping.

Record as `user_confirmed_webcontent_rebuild`, not network recovery.

### Top-level navigation errors

`WKNavigationDelegate` errors and responses are diagnostic evidence for top-level navigation only. They may not authorize saved-conversation retry or be generalized to internal fetch/XHR.

## Permissions, popup and downloads

- Camera/microphone decisions require exact trusted origin and use normal prompt behavior; never blanket grant.
- File upload remains a user-driven WebKit picker flow.
- Supported popups use a child WKWebView sharing only the optimized app's own website data store.
- Unsupported schemes/origins show native explanation rather than silent navigation.
- Downloads use `WKDownloadDelegate`, sanitized names, temporary app-local storage, explicit Files/share export and cleanup.

## Diagnostics and performance

Diagnostics are local and bounded by default. They may contain categories, timestamps, revisions, sequence counts and aggregates, but no message, title, draft, Cookie, token or full URL/query.

Metrics:

- document-ready / DOMContentLoaded / load-end;
- mounted turn and iframe count;
- reducer latency;
- observer-to-native latency;
- main-thread stalls;
- WebContent termination;
- manual recovery outcome;
- memory, thermal and low-power state.

Performance metrics never become state evidence and never automatically approve release.

## Mirror isolation and later cleanup

The mirror remains unchanged until Web Optimized physical acceptance. After acceptance, mirror-only DTOs are extracted from legacy files, `SharedTabScreen` becomes its direct root, and the WK/Safari/old-companion stacks are removed from the mirror candidate. The signed 0.7.2 IPA remains its independent rollback.
