# ChatGPT Web

ChatGPT Web now uses a two-layer runtime architecture:

1. **Shared core userscript**
   - `safari/chatgpt-safari.user.js`
   - used by desktop Tampermonkey / Violentmonkey and the iOS IPA
   - owns performance optimization, conversation state, tool-process compaction, the floating S panel, and the narrow native hot-update bridge

2. **iOS-only gesture userscript**
   - `safari/chatgpt-ios-gestures.user.js`
   - injected only by the iOS IPA shell
   - owns sidebar gesture recognition, sidebar DOM detection, open/close behavior, and gesture tuning
   - never runs on desktop

This separation keeps PC behavior independent from iOS gesture experiments while preserving one shared optimization/state implementation.

## Shared core install URL

`https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-safari.user.js`

Use this URL for desktop Tampermonkey / Violentmonkey.

The shared script includes `@updateURL` and `@downloadURL` pointing to the same canonical file.

Desktop users do **not** install the iOS gesture script.

## iOS gesture script

Canonical source:

`https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-ios-gestures.user.js`

The IPA shell injects this script automatically. It is gated by the native IPA environment and is not part of the desktop runtime.

Gesture script versioning is independent from the shared core version. For example:

- shared core: `0.3.8`
- iOS gestures: `0.1.0`
- IPA shell: `0.3.8 (11)`

Changing only the iOS gesture script does not require bumping the shared script version and does not require rebuilding the IPA.

## Shared performance behavior

The shared optimization layer starts from the first conversation turn:

- always-on `content-visibility: auto` for eligible turns;
- current streaming turn remains fully live;
- focused / interactive content remains fully live;
- completed MCP / DevSpace / tool-call process blocks collapse to a lightweight one-line summary;
- running or approval-waiting tool blocks remain live;
- final assistant answers remain intact;
- no `innerHTML` snapshots;
- no `replaceChildren`;
- no media source unloading.

The shared script is the same on PC and iOS.

## Shared conversation-state model

Both PC and iOS use the same state machine:

`running → waiting_user → settling → completed_unread → completed_read`

Rules:

- settling window: 2.8 seconds;
- visible read dwell: 1.2 seconds;
- state persists in `localStorage`;
- cross-tab sync uses `BroadcastChannel`;
- browser `storage` events are the fallback;
- sidebar status dots and the floating S control use the same state store.

## iOS gesture behavior

The iOS gesture script owns all sidebar touch handling.

Current tuning starts with:

- opening gesture start region: left 96 px;
- horizontal trigger distance: 20 px;
- horizontal/vertical intent ratio: 0.95;
- maximum gesture duration: 1.4 seconds;
- when the sidebar is open, the close gesture can start within the left-side sidebar region.

WebKit back/forward navigation gestures remain disabled in the native shell.

Because the thresholds live in `chatgpt-ios-gestures.user.js`, future sensitivity changes are delivered by gesture-script hot update without a new IPA.

## iOS hot update

The iOS shell maintains two independent cached runtimes:

- shared core userscript;
- iOS gesture userscript.

Startup order for each runtime:

1. use the newest valid cached copy;
2. fall back to the copy bundled in the IPA;
3. fetch the latest GitHub Raw source;
4. validate metadata and runtime version;
5. cache and hot-inject the newer script.

The shared core additionally validates against `package.json`.

A failure to update one runtime does not block the other runtime.

Opening the floating **S** panel triggers a native update check for both scripts.

The S panel displays:

- shared script version;
- IPA shell version;
- shared update status;
- tool-process compaction count;
- iOS gesture version and gesture update status when running inside the IPA.

## Microphone permission

The IPA includes `NSMicrophoneUsageDescription` and grants WKWebView microphone capture only to `chatgpt.com` / its subdomains.

Camera capture is not automatically granted.

## Release assets

Each shared-core release publishes:

- `ChatGPT-Web-Unified.user.js`
- `ChatGPT-Web-Unified.user.js.sha256`
- `ChatGPT-Web-Unified.zip`
- `ChatGPT-Web-Unified.zip.sha256`
- `ChatGPT-Web-iOS-Gestures.user.js`
- `ChatGPT-Web-iOS-Gestures.user.js.sha256`
- `ChatGPT-Web-iOS-Gestures.zip`
- `ChatGPT-Web-iOS-Gestures.zip.sha256`

Native-shell releases also attach the unsigned IPA and its SHA-256 file.

## Maintenance rule

- Shared optimization/state changes belong only in `chatgpt-safari.user.js`.
- iOS gesture changes belong only in `chatgpt-ios-gestures.user.js`.
- Native Swift changes should be limited to shell capabilities such as WebKit configuration, permissions, and loading/updating the two runtime scripts.


## Update check fail-safe

Update checks are fail-safe starting with shared core 0.3.9 / iOS shell 0.3.9.

- shared core and iOS gesture updates are checked in parallel;
- each GitHub Raw request has an 8-second timeout;
- the S panel has a 10-second UI watchdog;
- timeout falls back to the current cached/bundled runtime;
- a failed gesture update does not block the shared runtime, and vice versa.
