# iOS v0.4.42: SPA trace + genuine official-mode fallback

This is a conservative, opt-in diagnostic and comparison release aimed at identifying why the signed iOS WKWebView still feels slower than the original PC browser. It is **not** a claim that all ChatGPT long-chat cold-start latency has been solved.

## Context / established evidence
- In the user's iOS v0.4.40 telemetry, a WebKit content-process termination occurred at 10:10:33 Asia/Taipei 2026-10-10, followed by reload. Native WebKit JavaScript response delays reached 1.0s, and the injected telemetry event-loop delay reached 9.7s. Long old chat DOM mutation spikes were observed.
- v0.4.41 corrected the huge blank region caused by scrolling an entire long turn (rather than its final answer) and reduced redundant hot script reinjection and repeated silent reloads.
- The native v0.4.41 perf probe saw full navigations, but ChatGPT sidebar switching is often History API SPA navigation, leaving its native 3/8/15/30/60 second traces missing.
- A two-round, five-variant Playwright WebKit comparison removed several redundant Result Only scans; it **did not** show a stable performance improvement. Those changes were **not** promoted to production.

## Changes
1. Native opt-in diagnostic SPA trace: the existing onRoute event posts only {type: 'perf-route',routeKind:'home'|'conversation'} to the authorized native message bridge. Never send URLs, conversation IDs, message text, cookies or tokens. Native starts a new one-shot trace on each SPA change, recording ios_spa_open and checks at 1/3/8/15/30/60 seconds. No new permanent timers or passive global DOM listeners.
2. Native reports ios_memory_warning only if diagnostics are enabled. Existing WebContent process termination event remains.
3. Native answer visibility probe recognizes current DOM layouts (DIL roots, some markdown roots) and separately labels fallback assistant text as 'alt' instead of making an unsupported claim that the screen is blank. Existing 'above', 'below', and 'visible' states remain.
4. **Actual OFF switch**: historically, disabling the iOS '极速模式' / '恢复官方页面显示' only disabled tool button annotations, while Result Only still deleted historic MCP/Thinking DOM. In v0.4.42, destructive pruning/modern process observers and static CSS are gated by the setting. OFF then reloading restores the authentic HTML structure. This is a diagnostic A/B option, not the new default; keeping hundreds of MCP iframe nodes can increase memory pressure or trigger WebKit recovery, so avoid it for already problematic mega conversations unless intentionally comparing.
5. Default setting remains as v0.4.41. No touching credentials, underlying ChatGPT API networking, MCP approvals, history storage, or iOS gestures.

## Tests
- 5 WebKit Twin scenarios (initial/pressure/churn/slow/lifecycle) pass.
- Dedicated JS bridge synthetic SPA test: opt-in route to conversation emits a 2-key enum only, back to home emits home; disabled diagnostics emits no SPA metrics. Pass.
- Official-mode WebKit A/B: with enabled=false at document start, 96 MCP iframes and three Thinking blocks remain intact (2800 DOM nodes). Enabling cleans old process DOM (0 MCP). Disabling and reloading preserves original 96 MCP, and stable non-process answer hash is identical. Pass.
- Exact Git commit SHA pinned during tests to avoid raw GitHub CDN branch caching between rapid edits.

## Runtime / safety
- Native version 0.4.42 needs a fresh signed IPA for the new SPA handling and memory warnings. JS-only OFF-mode corrections can hot update without reinstalling.
- Cloudflare telemetry schema remains unchanged (existing 24-character reason and enumeration route kind). No telemetry unless the user enables the existing S -> 设置 -> 匿名性能诊断 setting.
- This trace doesn't provide Safari Web Inspector breakpoints; real fine-grained WebKit debugging still requires a paired Mac and iPhone.
- Important limitation: native route diagnostics do not speed up ChatGPT's own React frontend. To match desktop perceived speed on pathological long chats, a future native latest-answer reader independent of the page main thread may be necessary, with trustworthy completed-answer verification and fallback.
