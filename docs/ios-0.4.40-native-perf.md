# iOS v0.4.40 — opt-in WKWebView cold-start diagnostics

This version adds **measurement**, not a replacement for ChatGPT's native renderer or a claim of faster cold startup. It uses the existing WKWebView app shell, Safari userscript, Cloudflare telemetry Worker and IPA install center. It does **not** intercept or block ChatGPT API requests, erase history, or change MCP approvals.

## How to enable diagnostics on the phone

Open ChatGPT Web → the floating **S** control → **设置** → enable **匿名性能诊断**. The existing online diagnostic status displays the upload state. Then refresh or open a slow conversation and leave it on until the end of the load. The setting is opt-in and persists until disabled; turning it off stops native sampling and upload too. It is not activated by installing the new version.

## Native sampling

Using WKNavigationDelegate events and five bounded one-shot samples (3, 8, 15, 30, 60 seconds after navigation), native diagnostics submit only:

- ios_nav_start, ios_nav_commit, ios_nav_finish.
- ios_03_empty, ios_03_text, ios_03_visible, or ios_03_timeout / ios_03_error (and equivalent 08/15/30/60 checkpoints).
- ios_web_terminated when the WebKit content process is killed.
- Elapsed navigation milliseconds, approximate main-JS callback latency, and count of currently mounted native turns.

Sampling has a seven-second timeout and is skipped while the app is not active. When diagnostics is disabled, no JS sampling timers or uploads are added by this feature.

Samples use the existing /v1/telemetry schema and D1 table, identified only by a pseudonymous local install ID and per-launch session ID. **No chat body, conversation IDs, URLs, headers, cookies, API tokens, image content, or raw WebKit error data** are transmitted.

A main-frame JavaScript message perf-debug-opt-in synchronizes native consent with the existing telemetry switch. The bridge only accepts the ChatGPT top frame.

## Limitations

- Native scheduling and timeout detection work on the real device even if the ChatGPT page's JavaScript is overloaded; evaluateJavaScript itself can still be delayed by that overloaded renderer.
- Remote telemetry is not Safari Web Inspector. Source-level debugging, breakpoints, heap snapshots and network inspection still require a paired Mac and Web Inspector (the app keeps isInspectable true).
- Some completed answers use other DOM than DilResponseRoot. An ios_XX_empty event means this particular selector found no text, **not** proof that the user visually sees a blank page.
- The current iOS Result Only mode is unchanged; no additional destructive pruning or iframe intercept is added.
- Telemetry retrieval from Cloudflare D1 requires authorized operator access. There is intentionally no unauthenticated read endpoint.

## Testing and release process

- All five mcpoffice WebKit Twin scenarios pass with v0.4.40.
- iOS GitHub Actions produces the unsigned device IPA and simulator smoke tests. When merged to main, the existing installation center signs and publishes if signing remains available.
- Desktop Lite remains 0.2.2. Only an outdated test expectation of 0.2.0 was corrected; its runtime code was not touched.
