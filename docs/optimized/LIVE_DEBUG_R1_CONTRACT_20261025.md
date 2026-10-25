# Web Optimized · Live Debug R1 (2026-10-25)

Scope: **development candidate**, independent of Mirror and PC Bridge. Base source: `c83fa21832c8a169cb6cf0cb71b55820dcde3bc2`.
Ponytail Full: reuse the existing telemetry Worker URL and isolated Optimized App, no new always-on proxy and no remote JS execution.

## Behavior

- User explicitly enables **允许远程只读性能采样** in Optimized diagnostics. Default OFF. Debug stops in background; no background task or persistent timer when disabled.
- App generates independent 128-bit opaque room ID and 256-bit random secret locally. Copy pairing code manually; do not put it in URLs, source control, logs, messages or CI.
- Existing Cloudflare telemetry D1 collection is unchanged. New `/v1/live/:room/*` requests go to a per-room Cloudflare Durable Object. Its transient memory ring stores max 80 numeric-only events from the last 10 minutes, no D1 query or database write.
- Poll every 3 seconds while app foreground and opted in. Test host submits **only** `kind=snapshot`, app returns numeric DOM/mount/navigation/Resource Gate metrics. No arbitrary commands, URLs, HTML, cookies, chat content, taps or sends.
- If WebContent crashes, Supervisor and the native channel survive; remote snapshot can still show WebView absent. No auto-rebuild or retry of live ChatGPT sends.
- Existing resource gate uses `approvedRuleCount=0` and `r1-empty`: user can leave it ON, but it does not filter any request. Report separate `resourceGateEnabled` and `resourceRuleCount`.

## Endpoints

```
POST /v1/live/{room}/request    body {"kind":"snapshot"} -> {"id":"..."} 202
GET  /v1/live/{room}/poll       -> {"requests":[{"id":"...","kind":"snapshot"}]}
POST /v1/live/{room}/response   body {"id":"...","measurement":{"kind":"snapshot","turns":100,...}}
GET  /v1/live/{room}/result?id=...
POST /v1/live/{room}/events     body {"events":[{"kind":"nav_finish","navMs":450}, ...]}
GET  /v1/live/{room}/events     -> bounded recent sanitized events
```

All methods require header `X-Optimizer-Debug-Key` with the pairing secret; no CORS permission is granted on live routes. `/v1/telemetry` and `/health` are untouched.
Only event kinds `nav_start`, `nav_finish`, `nav_error`, `snapshot`, `memory_warning`, `web_terminated` are admitted. Only fixed finite numeric fields are retained.

## Test host

1. Deploy Cloudflare Worker with `LIVE_DEBUG` Durable Object migration (not done by source edits alone).
2. Sign and install Optimized candidate containing `OptimizedLiveDebug.swift` (not done by source edits alone).
3. On phone: enable **允许远程只读性能采样**, foreground app, copy pairing code to trusted Office test host through a secure channel.
4. Set `OPTIMIZER_PAIRING_CODE` in the trusted process environment, not CLI argv or log.
5. `node scripts/optimized-live-probe.mjs snapshot` (requests one native+DOM numeric probe, waits up to 30s for response).
6. `node scripts/optimized-live-probe.mjs events` (reads recent navigation, memory, termination metrics).
7. Turn live debug OFF at the end.

## Performance test interpretation and safety

- `navMs`: WKNavigationDelegate start-to-finish, **not** full ChatGPT SPA-conversation readiness. DOM `turns` and `lastTurnVisible` are independent snapshots, and cannot be called time-to-latest-answer without an additional route-ready timer.
- `domNodes` counts current DOM nodes; one-off sampling can cost some main-thread time. Do not run high-frequency repeated snapshots in long conversations.
- New access is ephemeral and possession-of-secret authorized: if pairing is leaked, disable debug, rotate pairing credentials in a future candidate, and do not disclose them in telemetry. Access should be additionally rate-limited at Cloudflare if made available beyond single-user lab.
- Failure acceptance: no raw text/URLs exported, no privileged remote UI action, no Mirror target changes, no D1 dependency, wrong credential rejected, request returns only fixed snapshot metrics, turning OFF stops answering.
- Authenticated remote endpoint must be checked on actual deployed worker, with test session and physical iPhone, prior to claiming **E2E_ACCEPTED**.
- For full A/B timing, follow-up phase must measure SPA route-to-last-turn-visible and render-long-task latency, compare repeated same-conversation warm/cold scenarios, and validate scroll/click functionality.

## Development verification

Run `node --test telemetry-worker/test/live-debug.test.mjs`, `npm run check:optimized`. Source-level JS tests are **not** signed iPhone/Xcode proof; require macOS CI and independent review before candidate installation. Do not publish Mirror stable or Optimized stable on this feature alone.
