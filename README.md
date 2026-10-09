# ChatGPT Web

## Shared web userscript (0.4.38)

- Desktop "recent chats" shows a compact project-name label when the sidebar
  exposes a trustworthy project mapping.
- Project names come from visible project links; chat membership comes from a
  project chat URL, an explicit project marker, or a project chat that was opened.
  The local cache survives page refreshes and updates project names on rename.
- The feature does **not** fetch undocumented ChatGPT endpoints or intercept
  application requests. It does not infer a name when membership is unknown.
  For an old chat with only a generic /c/ link and no project metadata, opening
  the project chat can populate the mapping.
- Sidebar labels are drawn with CSS rather than additional DOM nodes. Existing
  sidebar mutation handling is incremental and the desktop status fallback
  interval is reduced from once every 7 seconds to once every 15 seconds;
  settling/completion checks are scheduled directly.
- The new labels are desktop-only. The iOS result-only/runtime path remains
  disabled for sidebar project scanning.


## Current iOS runtime (0.4.35)

The default iOS app runtime is again the developer-first WKWebView shell:

- inspectable WKWebView (Safari Web Inspector enabled);
- persistent ChatGPT website data / login state;
- native JavaScript bridge;
- cached + multi-source remote userscript hot update;
- latest userscript is injected into the current page immediately;
- returning the app to foreground triggers a throttled hot-update check;
- Result Only mode hides normal reasoning/tool process UI while keeping explicit approval interactions;
- completed historical reasoning/tool DOM is destructively pruned in small idle chunks to reduce WebKit memory pressure;
- modern ChatGPT activity blocks use a WSA regression-tested boundary: MCP/thinking activity DOM is removed while non-process content hash remains unchanged;
- separate popup WKWebView for links/files, plus WebKit content-process recovery.

The SFSafariViewController + Action Extension implementation remains in the repository as a fallback/reference path, but it is no longer the default app root.


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
- current streaming final answer remains fully live;
- focused / interactive content remains fully live;
- iOS native / Safari-container runtime uses **Result Only mode**: normal MCP, tool, reasoning, and process blocks are hidden instead of rendered as summaries;
- tool blocks that require explicit user approval / confirmation remain visible and interactive;
- the Result Only status keeps a lightweight per-request elapsed-time and tool-call summary in the control panel;
- desktop userscript runtime keeps the lightweight one-line tool summary behavior;
- final assistant answers remain intact;
- no `innerHTML` snapshots;
- no `replaceChildren`;
- no media source unloading.

The shared script is the same on PC and iOS, with Result Only presentation enabled only for the native/Safari-container runtime.

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
3. race multiple trusted update sources in parallel;
4. validate metadata/runtime version;
5. choose the newest valid result;
6. cache and hot-inject the newer script.

The native updater races GitHub Raw, jsDelivr CDN, jsDelivr Fastly, and GitHub Contents API. A single blocked endpoint no longer blocks the update path.

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
- each runtime also races four trusted download sources in parallel;
- each source has a 6-second timeout;
- the S panel has a 10-second UI watchdog;
- timeout falls back to the current cached/bundled runtime;
- a failed gesture update does not block the shared runtime, and vice versa.


## Manual update retry

The S panel includes a dedicated update action:

- `检查更新` in the normal state;
- `检查更新中…` while a check is running;
- `重试更新` after offline / timeout / error;
- `再次检查更新` after a successful or latest check.

The button invokes the native updater directly and restarts the update watchdog without requiring the S panel to be closed and reopened.


## Popup browser overlay

Starting with iOS shell 0.3.11 build 14, ChatGPT pages opened as a new browser page/window are presented in a separate native WKWebView layered above the main ChatGPT WKWebView.

Typical cases include:

- viewing a file generated by ChatGPT;
- opening an external website from a ChatGPT answer;
- links using `target=_blank`;
- pages created with `window.open()`.

The main ChatGPT page remains alive underneath. The popup layer shows a floating native browser control with:

- back;
- forward;
- reload;
- close.

Closing destroys only the popup WKWebView and immediately reveals the original ChatGPT page underneath, without relying on browser history.

The floating browser control appears only for this popup layer. Normal ChatGPT navigation does not show it.

Shared and iOS gesture runtimes also explicitly exit on non-ChatGPT hosts so external popup pages do not run ChatGPT-specific optimization or gesture code.
