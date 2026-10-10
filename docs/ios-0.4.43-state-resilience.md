# iOS v0.4.43 — state persistence and startup data safety

## User symptom
After closing and reopening the signed iOS ChatGPT Web app, its sidebar loses observed running/completed statuses. Some conversations intermittently fail to hydrate and require repeated browser refresh / Retry.

## Confirmed code-level causes
1. The app's `EXTREME_NATIVE_MODE` bypassed the saved conversation status sidebar renderer and state synchronization even though the unified userscript had a localStorage-backed state map. On restart, badges could not be restored.
2. A legacy one-time sidebar migration, if its cookie was absent, called a **deep client-site cleanup**, wiping ChatGPT localStorage, sessionStorage, Cache Storage, IndexedDB, and forcibly reloading. Although this is unlikely to explain every repeated failure (the cookie is long-lived), it is incompatible with preserving the user's cached sessions and local conversation UI. It has been disabled for all iOS startup paths and removed from the executable script. Explicit user-invoked cache clearing remains available separately.
3. The native WKNavigationDelegate silently dropped most navigation errors. Existing periodic native probes marked unloaded/missing DOM text but could not distinguish known navigation-error classes or explicit ChatGPT Retry/error views.

## Targeted v0.4.43 changes
- Reuse existing `cgpt-safari-conversation-state-v1` localStorage state. Re-enable small **sidebar-only** state badge restoration and the existing BroadcastChannel/storage synchronizer on native iOS. Do not activate full project indexing or the old 12-second status polling.
- Only mark active/running if the user explicitly sends a message or the **latest** native turn shows `in_progress`/`running`; only mark completed when latest native turn reports `complete`/`completed` AND contains a readable assistant response. No fake completion from an empty/loading page.
- When a chat was observed active before closure but not verified after 90 seconds, render a neutral **待确认** state rather than a false perpetual `running` or invented `completed`. Previously observed completed-read chat renders muted gray status instead of an unread blue marker.
- Reuse the existing scoped conversation MutationObserver and schedule one deferred status check at a time. A 2.4-second self-rescheduling tick is used **only while the current chat is actually running**, automatically stopping after a verified completion or navigation.
- On SPA chat switching, ignore a still-mounted old turn's key until the new conversation's turn is available.
- Remove implicit reset of app-level site storage and forced startup reload.
- Extend consent-based native telemetry with coarse whitelisted `ios_nav_timeout`, `ios_nav_lost`, `ios_nav_offline`, `ios_nav_connect`, `ios_nav_tls`, `ios_http_auth`, `ios_http_limit`, `ios_http_server` and explicit `ios_XX_retry` marker. No URLs, cookie, chat text, tokens, payloads, or exact HTTP response content are logged. No automatic clicking Retry, navigation interception, or background retry loops.

## Testing
- Actual Playwright WebKit status persistence test: observed active on chat A → close page → reopen homepage restores `running`; after 90s without evidence shows `uncertain` without mutating stored state; incomplete hydration leaves `uncertain` (not completed); verified completed answer produces `completed_read`; close and reopen homepage preserves completed state. PASS.
- Existing WebKit Twin initial / 3x pressure / churn / slow / lifecycle: 5/5 PASS.
- Long synthetic page + 280 chat links in sidebar, 4 A/B trials: first-prune median v0.4.42 666ms vs v0.4.43 703ms, both kept all 280 links, preserved final answer, and completed MCP cleanup. This **does not show major speed gain**, but avoids obvious first-load regression in synthetic WebKit.
- GitHub macOS iOS branch CI build #213: source validation + real device compilation / unsigned packaging PASS. Simulator UI smoke should be checked for final status before declaring complete.

## Limitations and next data
- Status after iOS force-close is the **last observed state**. If the server completes while the phone is fully closed, the client cannot confirm that change without a trusted fresh response. Stale running states deliberately show "待确认"; opening a conversation can verify it.
- Intermittent failed chat hydration was not reproduced in the signed-in physical iPhone during this coding session; the new failure diagnostics will distinguish recoverable navigation/network problems and explicit ChatGPT Retry UI. Removal of destructive client-site reset eliminates one known unsafe path, but **does not prove that all ChatGPT server/UI load failures have been fixed**.
- Existing instant long-chat acceleration/Result Only behavior and current script hot updater are unchanged except for the targeted state and data-safety behavior. No extra MCP iframe deletion or network requests.
- User should update **in place** to preserve existing site data; do not uninstall the app.
