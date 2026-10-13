# ChatGPT Web Optimized Implementation Handoff

Date: 2026-10-13
Status: source/Simulator/unsigned Release passed at `7e855d6`; candidate signing blocked only on deployment of tested signer commit `13d56ac`; see `SIGNER_DEPLOYMENT_HANDOFF_010.md`
Audience: iOS architecture, WKWebView, Conversation Manager, CI/signing and release maintainers

## Current decision

Keep the existing `ChatGPT Web` structured-mirror app as a stable independent line and add a second side-by-side iOS app in the same repository.

New product:

- Name: ChatGPT Web Optimized
- Target/scheme: `ChatGPTWebOptimized`
- Bundle ID: `com.masakacj.chatgptweb.optimized`
- Initial version/build: `0.1.0 (1)`
- WKWebView only
- no Safari target
- no SharedTab/PC Bridge code
- independent login and all local data
- conservative manual loading recovery where WebKit lacks Chrome request evidence

These decisions supersede any assumption that the existing mirror app should gain another Web mode or share login/data with the new app.

## Authoritative documents

1. `docs/mirror/MIRROR_072_SIGNED_BASELINE.md`
2. `docs/optimized/PRODUCT_CONTRACT.md`
3. `docs/optimized/ARCHITECTURE.md`
4. `docs/optimized/EXECUTION_PLAN.md`
5. `docs/optimized/ACCEPTANCE_PLAN.md`
6. `docs/optimized/SIGNER_DEPLOYMENT_HANDOFF_010.md`
7. root `DEVELOPMENT_STATUS.json`

The existing `docs/CURRENT_RELEASE.md` remains authoritative for the current stable mirror release.

## Source baseline

- Repository main: `fac5b7873ff0e7b643187ad1f852a234dec767e1`
- Signed mirror source: `8440857cf0bf485ce79d408b74b8380069eb08dc`
- Mirror stable: 0.7.2 Build4, bundle `com.masakacj.chatgptweb`
- Mirror IPA ID: `12112229-485f-49e1-afba-896caa875853`
- Signing run: `38327609864`
- PC Bridge: 0.3.10
- PC CM: protocol2 / 0.2.2

No code, target, signing metadata, IPA or live service was changed by this planning handoff.

## Existing code classification

### Mirror core — keep untouched through F5

- `App/SharedTabModel.swift`
- `App/SharedTabScreen.swift`
- `App/SharedTabDraftLedger.swift`
- `App/SharedTabFixtureProtocol.swift`
- SharedTab UI and policy tests

### Genuine upgrade compatibility — keep initially

- old `PCCompanion.lastTab` read, later replace with private `STLegacyTab`
- old `PCCompanion/draft.json` one-time import
- current pairing Keychain and SharedPC state
- optional wire fields needed for old caches/rollback

### Release-unreachable legacy — remove only during F6

- `PCCompanionView.swift`
- `NativeConversationScreen.swift`
- `PCSidebarView.swift`
- `PCCompanionTestProtocol.swift`
- corresponding old UI tests/launch flags

Before deletion, move wire DTOs and the hash/origin policy still used by SharedTab into mirror-owned neutral files.

### Release-reachable WK fallback — source reference only

- `ChatGPTWebView.swift`
- `UnifiedScriptStore.swift`
- `ConversationResilienceStore/Bridge.swift`
- `NativePerformanceProbe.swift`
- `NativeConversation*.js`
- bundled userscript
- Safari Action target

Do not copy this stack wholesale into Web Optimized. It is a reference for WebKit lifecycle, popups, permissions and process recovery. The new app deliberately excludes old userscript hot update, DOM pruning and Safari.

## PC CM portability boundary

Can reproduce semantically in Swift/WK:

- event/reducer semantics;
- task/read separation;
- document/sequence/revision/owner protection;
- bounded observation;
- persistence;
- native-only webpage visual policy;
- recovery blockers/budget;
- redacted diagnostics/performance metrics.

Cannot honestly reproduce with current WK APIs:

- Chrome `webRequest` evidence for internal page fetch/XHR;
- exact automatic saved-conversation GET recovery.

Therefore Web Optimized uses explicit user-confirmed official Retry only and never wraps or replays requests.

## Phase state

- F0 mirror baseline: `in_progress` — source identity and CI mirror evidence recorded; signed artifact/profile/hash evidence remains
- F1 target isolation: `passed` — target boundary, both schemes and Release compiles passed in run 38351064043
- F2 CM corpus/Swift owner: `passed` — contract, unit tests and Simulator passed in run 38351064043
- F3 WK shell: `in_progress` — UI tests and Release compile passed; physical-device login/navigation pending
- F4 recovery/debug/performance: `in_progress` — synthetic tests passed; physical recovery/performance acceptance pending
- F5 candidate/physical acceptance: `blocked` — unsigned candidate passed run 38351063992; deploy signer commit 13d56ac and rerun
- F6 mirror cleanup: `blocked` until F5 passes

## First implementation increment

Perform only F0–F2:

1. finish signed mirror artifact/profile baseline;
2. add empty isolated `ChatGPTWebOptimized` target and boundary checks;
3. add independent data namespace declarations;
4. create CM v2 JSON contract corpus;
5. implement Swift event/state/reducer/store/owner;
6. run corpus parity tests;
7. update this handoff and status JSON with exact evidence.

Do not begin by copying the old 3233-line WebView coordinator or 7395-line userscript.

## Release and rollback boundary

- New app needs its own Apple App ID/Profile and signer application key.
- Candidate signing must not alter the existing `chatgpt-web` stable record.
- Physical-iPhone acceptance is mandatory before first stable promotion.
- Mirror cleanup starts only after Web Optimized is accepted.
- Mirror rollback remains the preserved signed 0.7.2 Build4 IPA.
- Web Optimized has a separate candidate/stable index and rollback artifact.

## Prohibited claims

Do not claim:

- signed candidate or installation-center publication exists before a successful post-deployment workflow;
- WK has Chrome `webRequest` parity;
- simulator/build/signing equals physical acceptance;
- performance improved before measured A/B;
- a user-confirmed page action is network replay recovery;
- mirror fallback can be removed before Web Optimized acceptance;
- any login, Cookie, Keychain, draft or state is shared between products.

## Next action

Deploy tested signer commit `13d56ac` on mcpdebian exactly as documented in `SIGNER_DEPLOYMENT_HANDOFF_010.md`, verify mirror stable unchanged, then rerun `web-optimized-candidate.yml`. Stop after publishing and verifying an unpromoted candidate; physical-iPhone acceptance remains the next gate.
