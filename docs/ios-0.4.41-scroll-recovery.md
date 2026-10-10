# iOS v0.4.41 — long conversation scroll and recovery hotfix

## Real-device findings (2026-10-10, Asia/Taipei)

Using the existing authorized Cloudflare D1 telemetry database, confirmed the following **real v0.4.40** events without reading chat text, URLs, tokens, or identifiers:

- 10:10:11 opt-in diagnostic enabled; native WKWebView process terminated at **10:10:33**.
- A fresh native navigation immediately followed, finishing its base document by approximately 10:10:34.
- 3/8/15/30/60-second probes all returned an empty last-DIL-root marker. This is selector-specific and **does not prove the entire screen was visually blank**.
- One 15-second window saw **923 conversation DOM mutations**. Native bridge telemetry separately recorded event-loop delays up to **425ms**, **1302ms**, and eventually **9725ms**. No corresponding high custom sidebar-observer mutation count was present; drawer latency is consistent with severe main-page stalls, not a proven sidebar-specific script loop.
- Process termination is a confirmed trigger for automatic page reload. The previous recovery policy allowed two silent reloads per 30 seconds and cleared the app URLCache / WKWebsiteDataStore memory cache before reloading, which could exacerbate repeated cold initialization if the page crashes again.
- Root cause of the underlying WebKit termination remains uncertain (likely memory/renderer pressure from a heavy chat, but no resident memory counters or crash log proving OOM).

## Directly reproduced scroll bug

Existing iOS injection invoked scrollIntoView(block: end) against the **entire last conversation turn**. That turn can contain a huge trailing virtual spacer; this pushes the real last answer 1–2 screens *above* the visible viewport.

An A/B synthetic Playwright WebKit test using a complete 180px final answer followed by a 1800px virtual spacer:

| | 0.4.40 old | 0.4.41 candidate |
| --- | ---: | ---: |
| window.scrollY | 2348px | 136px |
| final answer bottom relative to viewport | -1360px (offscreen) | +852px (on screen) |
| final answer survived | yes | yes |

This is a genuine WebKit rendering test (though not the user's signed-in real device). Test source: mcpoffice D:\workspace\py\chatgpt-ios-twin\test_scroll_anchor_041.py.

## Hotfix

1. Scroll only a readable *last-answer descendant* (DIL/Markdown roots), never the entire long turn. If content isn't ready, do not forcibly scroll. Re-attempt only when an answer is added through the existing scoped conversation observer. One pending rAF maximum.
2. Only one automatic scroll per conversation visit; route-rebind and late layout changes no longer repeatedly snap it to the bottom. User pointer interaction cancels pending scroll.
3. The native Swift hot-update code now re-injects into the current page only if the remote userscript actually changed. Previously it unconditionally destroyed/recreated the page-side script after every update check, even for the same version.
4. The WebKit crash recovery policy now allows only **one silent reload per three-minute window**, then offers explicit manual retry or home. Automatic recovery no longer purges app-level URLCache and WebKit memory cache, and cancels delayed reload if the user has since navigated elsewhere.
5. Add opt-in native diagnostic reason values (ios_XX_above/ios_XX_below) to distinguish a readable last answer rendered outside the viewport from an actual missing DIL-root answer. Existing telemetry schema and consent behavior remain unchanged.
6. No new iframe blocking, historical DOM pruning, MCP interception, app gestures, sidebar rewrites, cookie clearing or account data changes.

## Limitations

- Synthetic WebKit A/B confirms the old scroll defect and new scroll target; the signed-in user's iPhone requires an after-install reproduction to verify the layout under real content.
- This removes a known source of extra scroll and repeated native script re-initialization. It does not yet solve ChatGPT's main-thread React history hydration cost, which can make the native sidebar unresponsive for multiple seconds.
- Existing Result Only pruning remains unchanged; avoid assuming MCP content or approval safety beyond previous synthetic tests.
- Live telemetry is available only after the user opts in, and is not equivalent to remote Safari Inspector breakpoints.
