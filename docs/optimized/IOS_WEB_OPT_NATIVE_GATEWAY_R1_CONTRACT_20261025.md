# IOS-WEB-OPT-NATIVE-R1-20261025 · Native Supervisor / Resource Gate / Real-device Candidate

**Date:** 2026-10-25. **Status:** FROZEN for candidate development + physical iPhone acceptance (NOT production stable). **Style:** Ponytail FULL. **User authorization:** “可以，出完整开发合同，直接进入实机测试。”
**Roles:** Developer=AGY (native Gemini), Reviewer=CC (independent GPT-6 separate run), Repairer=AGY (new unique run). Host owns QA/Controller; no agent self-approval.

## 0. Grounded baseline and scope
- Product: independent `ChatGPT Web Optimized`, bundle `com.masakacj.chatgptweb.optimized`; preserve signed Mirror `com.masakacj.chatgptweb` and PC Bridge unmodified. No shared cookies, Keychain, app groups, or pairing credentials.
- **Frozen real signed source baseline:** `masakacj/chatgpt-web` commit `7f54b2ac60ff636a209822d0849e7cfdffd11193`, independently signed candidate `0.1.2 (3)`, GitHub run `38382619322`, candidate ID `ce533fdb-a113-4423-9ed0-0343f7d4643a`. Signer `ipa-signer.service`/tunnel healthy 2026-10-25, existing signed candidate download 200; this is **not** evidence of physical acceptance.
- Existing files already include `OptimizedApp/Application/ChatGPTWebOptimizedApp.swift`, `OptimizedApp/Application/OptimizedAppModel.swift`, `OptimizedApp/Web/OptimizedWebView.swift`, `OptimizedApp/Web/WebConfigurationFactory.swift`, `OptimizedApp/Diagnostics/OptimizedTelemetry.swift`, `ConversationManagerOwner` (sole state writer), and a bounded observation adapter. **Defect at baseline:** `markProcessTerminated()` automatically changes `webViewGeneration` for the first two terminations, defeating safe recovery; remove this failure loop.
- iOS deployment target 17.0. Keep 17+ working; WebExtension host is capability-gated to iOS 18.4+ and is NOT a prerequisite for R1 failure survival. External WebKit refs: WebKit Safari 18.4 announcement for `WKWebExtensionController`; Apple `WKNavigationDelegate.webViewWebContentProcessDidTerminate`; `WKContentRuleListStore`.
- Work only in isolated candidate based on exact signed 7f54 SHA. Main working checkout has unrelated dirty Mirror edits; do not touch, reset, cherry-pick, or publish those. Do not claim real iPhone test without device, OS version, install and measured test receipt.

## 1. Desired architecture and invariants
```
SwiftUI Native Shell (app process)
  |-- Native Optimization Supervisor (durable crash/session policy, safe UI)
  |-- Resource Gate (WKContentRuleList compiled allowlisted rules, opt-in A/B)
  |-- Diagnostics + local test report (reuse OptimizedTelemetry; content-free)
  |-- User-chosen fallback: native safe screen / open separate Mirror app
  +-- replaceable WKWebView  (WebContent process can die)
       |-- official ChatGPT DOM/UI, authenticated site data
       |-- existing bounded observer/CM only
       +-- later experimental port of PC extension core when available
```
- Control plane must survive **WebContent** termination. No permanent background daemon claim; whole-app iOS jetsam cannot be intercepted. On next launch durable crash journal controls safe landing. Preserve site login without copying cookies or touching website data store.
- One state owner: `ConversationManagerOwner` for chat state; Native Supervisor owns ONLY failure/recovery state. No second CM, no second Bridge/Browser executor, no duplicate WebView foreground loads; keep Mirror separately installable.
- Preserve send/draft/turn/approval safety: never auto-replay POST, Send, tool approval, retry, regenerate; never reset an uncertain send to “not sent”. `WebContent` invalidation must retire stale message handler, observation epoch and pending recovery candidate before new WebView appears.
- Apply no arbitrary network content rewriting, TLS MITM, proxy CA, interception of chat history or modification of official React-owned DOM, script fetch/XHR hooks, forced content pruning, hard-kill of WebContent, or WebKit private selectors.
- Limits are truthful: WK content rules can stop matching subresources, NOT reduce arbitrary JS heap of official page. Network proxy is a later optional spike only if A/B proves benefit; not needed in R1.

## 2. Work package N1 — Native Supervisor (mandatory, first device build)
**Owned:** `OptimizedApp/Application/NativeOptimizationSupervisor.swift` (new); `OptimizedApp/Application/OptimizedAppModel.swift`; `OptimizedApp/Application/ChatGPTWebOptimizedApp.swift`; `OptimizedApp/Web/OptimizedWebView.swift`; tests only under `OptimizedTests/NativeSupervisorTests.swift` and `OptimizedUITests/NativeSupervisorUITests.swift`.
1. Remove the first-two automatic generation rebuilds. On `webViewWebContentProcessDidTerminate`, invalidate document, record event **once**, detach any stale WebContent and present a **native** safe state that remains interactive. No initial automatic rebuild, no repeat loop. User must explicitly confirm before one rebuild. Recovery retains WKWebsiteDataStore.
2. Durable bounded journal in **Optimized-only UserDefaults**: timestamp, launch lifecycle and anonymized error/route category, bounded recent termination count. No raw conversation ID, URL, title, draft, token. On repeated verified WebContent terminations (provisional: 2 within 10 minutes), circuit remains open across app restart; default to native safe landing (not re-enter failing chat). App relaunch after unknown/unclean shutdown may show cautious recovery choice but MUST NOT falsely label iOS jetsam/OOM as proven.
3. Native safe UI options: retry once after explicit confirmation (initial destination home or safely retained route only if document identity and draft safety verified), remain safe / close sheet, diagnostics export, and “Use installed Mirror” optional link **only if actual bundle-declared deep link exists**. Otherwise show plain instruction to open the separately installed Mirror app. No automatic pairing/share credential/cookie. Do not block native diagnosis behind the dead WK view.
4. Add a **user-initiated synthetic WebContent termination fixture** from native diagnostics; MUST be explicitly labeled SIMULATED, not fake memory OOM; it must exercise the same Supervisor transition but not call a private WebKit kill API. Keep ability to test true delegate termination separately through real device / Instruments.
5. App background/foreground, web loading cancellation, normal navigation, existing official Retry confirmation, native button interactions, app relaunch must not reset safety state. New rules cannot suppress login or ChatGPT normal navigation when healthy.

## 3. Work package N2 — Native Resource Gate (after/beside N1, opt-in only)
**Owned:** `OptimizedApp/Web/NativeResourceGate.swift` (new), `OptimizedApp/Web/WebConfigurationFactory.swift`, `OptimizedTests/NativeResourceGateTests.swift`.
1. Use **only** public `WKContentRuleListStore` / `WKUserContentController.add` with a bundled, versioned, static, reviewable list. Compile outside WebContent; fail-open on compile/apply errors. Default is **observe/control (no block)**. No arbitrary user-supplied regex, runtime remote update, recursive proxy, or wildcard block of `chatgpt.com`, login, streaming, conversation REST, MCP, attachments or critical scripts.
2. A/B switch independent from N1: disabled/off by default. Only allow rules with a fixture proving the resource is nonessential (cosmetic third-party category; not inferred by name alone). No approved allowlist => zero blocking rules and explicit “no verified savings”.
3. Persist policy version + enabled flag in app sandbox; a startup safe-mode always disables optional optimizations. On WebContent termination, rule set must be removable from subsequent WebViews; never leave stale handler references.
4. Never claim `WKURLSchemeHandler` intercepts https, or CONNECT proxy can inspect HTTPS content without decryption.

## 4. Work package N3 — Extension parity spike (after safety device gate)
- Inventory **deployed** Chrome 0.3.33 CM content/worker and **independently approved candidate** latest-scroll module. Do not re-enable abandoned 0.3.32 `long-chat-performance.js`. Verify actual 0.3.34 deployment/approval before selecting code.
- On iOS >= 18.4, prove a trimmed `WKWebExtensionController` environment can host an allowed package; detect unsupported `chrome.runtime`, `tabs`, `storage`, `alarms`, `webRequest`, `debugger`. Adapt only the platform-bound interfaces. Keep iOS17 native-safe first.
- Shared functionality under this follow-on gate: bounded per-turn observation, scroll positioning, content-free performance benchmark. Do not bundle the whole PC Bridge remote send/CM owner. The existing Swift CM remains sole status reducer.
- Ship Extension parity in a **separate** candidate and real-device A/B after N1/N2; a dead WebContent cannot be required to report or recover itself.

## 5. Work package N4 — candidate and physical test pathway
**Delivery intent:** `candidate_release`; targets: isolated `masakacj/chatgpt-web` feature branch, GitHub macOS CI, separate optimized-only signed candidate IPA, installer verification, **physical iPhone E2E**. Prior review + independent Host QA must pass before push/sign; version bump candidate from 0.1.2 (3) to at least 0.1.3 (4) consistently in CI and Info.plist/project settings. **Never promote stable** or overwrite Mirror index.
- Reuse `.github/workflows/web-optimized-candidate.yml` with macOS XcodeGen, Simulator test, Release iPhone target compile, signer, signature + IPA/manifest hash. Signed = candidate readiness, not physical acceptance.
- Real device: record model, iOS version, install timestamp, exact IPA SHA/run/build, storage data isolation, Cold launch/home, ordinary/project/long chat, 5 switches, 30-minute MCP/stream-heavy use, keyboard/draft, login/MFA, upload/download, foreground/background, re-launch.
- Two different failure tests: (a) native **synthetic** termination fixture with immediate safe UI and explicit retry; (b) actual WebContent process termination if reproducible via public device test/developer tools or natural event. Never invoke undocumented force-kill APIs; if (b) not observed => mark **NOT VERIFIED** rather than faking.
- Whole-app termination: simulate via normal app force-quit/start to check persist/reentry behavior, but do not call this WebContent OOM. Unknown death is not proof of cause.
- Performance A/B vs signed 0.1.2(3): compare same iPhone and same two long conversation IDs, same network and warm/cold modes, P50/P95 time-to-last-usable-message, scroll jank, UI responsiveness, five-switch memory trend, actual WebContent exit rate; don't infer WebContent heap solely from host task RSS. Instruments externally when accessible. Native safety acceptance independent of benchmark gain. Enabled resource rules must not worsen P95 >10% nor break tools/attachments.
- Reporting: `candidate_source_sha`, AGY task/run/receipt, Host QA, independent CC REVIEW, CI job, signed IPA hash, install link, device model/iOS, test case results, metrics/artifacts, exact unknowns. If no connected real iPhone, provide installable candidate and in-app self-test/export; final gate remains `PHYSICAL_DEVICE_PENDING`, not E2E_ACCEPTED.

## 6. Independent QA and acceptance matrix
Host independent assertions (at minimum):
- QA01 normal fresh launch boots original ChatGPT official page once; no second CM/status writer.
- QA02 one WebContent terminal event => no auto WebView reload; native safe interface usable with web layer destroyed.
- QA03 user-confirmed rebuild exactly once, no automatic send/retry/approval, old handlers removed.
- QA04 2 terminations in 10 min => circuit open and persisted; new app launch does not reopen failing route.
- QA05 stale/duplicate callback ignored by generation; scene background alone does not count as crash; unknown shutdown not falsely attributed OOM.
- QA06 synthetic fixture labelled as synthetic and generates content-free diagnostic event.
- QA07 storage/Keychain/login/pairing/mirror namespaces unmodified; no Mirror target code, bundle ID changes.
- QA08 resource compile/apply failure fail-open; disabled = exact base behavior; unsafe wildcard/resource rules rejected; safe mode disables optional filter.
- QA09 no real user Send, no network POST replay, no TLS interception, no WebKit private API, no extra telemetry sensitive fields.
- QA10 simulator unit/UI normal flows + existing CM corpus pass; Release iphoneos compile passes; CI candidate signing/source/hash verified.
- QA11 real iPhone ordinary/project/long chat send/scroll/attachment/camera/popup/audio + 30-minute use; no content loss; unknown side effects never replayed.
- QA12 real iPhone safe UI remains responsive after actual WebContent termination (if observed), repeated recovery/force-quit restore, report export succeeds. No device receipt => FAIL TO CLAIM physical acceptance.
- QA13 resource optimizations A/B only after verified nonessential resources and separate iPhone measurements; report latency/energy/memory as measured, not invented.
- QA14 signer and release before/after: Mirror stable immutable, optimized candidate unpromoted, fresh installer link and SHA verified.

**Gates:** G0 source/signed baseline preserved; G1 AGY source+isolated tests; G2 independent Host QA exact SHA; G3 independent CC/Web Review verdict; G4 authorized feature-branch push and macOS CI; G5 signed **candidate** verifiable; G6 installed real iPhone test receipt; G7 performance A/B report and rollback rehearsal. Only G6+G7 may set `E2E_ACCEPTED`; no stable promotion within this contract.

## 7. Out of scope / rollback
- No real ChatGPT chat Send during AGY/CI/Host automated test. Only user's manual test on own iPhone may actually Send.
- No Chrome/Bridge production reload, app's Mirror stable release, app delete/data wipe, credential migration, local CA installation, system VPN/always-on daemon, request-body logging, synthetic “fake OOM” claims.
- Rollback switches candidate code/policy, restores prior optimized candidate pointer only when authorized; existing signed `0.1.2(3)` serves A/B baseline. Do not auto-reinstall/remove apps or change Mirror stable pointer.
- If physical test device not accessible, report honest blocker and precise install/self-test instructions; continue development/CI without pretending simulator is physical.
