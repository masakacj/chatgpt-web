# ChatGPT Web Optimized Execution Plan

Date: 2026-10-13
Status: approved plan; implementation not started

## Sequencing

| Phase | Work | Completion gate |
|---|---|---|
| F0 | Freeze mirror signed/source/test/rollback baseline | Existing 0.7.2 artifact and rollback are fully traceable and reinstallable |
| F1 | Add isolated Web Optimized target/bundle/scheme/tests | Both apps compile/install side by side; target boundary check passes; mirror unchanged |
| F2 | Create CM v2 fixture corpus and Swift owner/reducer/store | PC Node and Swift produce identical decisions/projections for every case |
| F3 | Build clean WKWebView shell and observation-only adapter | Independent login/navigation works on device; no network/DOM mutation hook |
| F4 | Add manual recovery, process lifecycle, diagnostics and metrics | Zero automatic reload/replay; stale events rejected; diagnostics redacted |
| F5 | Candidate signing, real-device functional/performance acceptance | Signed 0.1.0 Build1 passes complete physical matrix before stable promotion |
| F6 | Remove Web/Safari/old-Companion code from mirror | Mirror cleanup candidate preserves all SharedTab data/behavior and can roll back |

## F0 — Baseline

- Use `fac5b787...` as current main and `8440857...` as signed app-source identity.
- Capture existing IPA hash, size, profile, certificate, entitlements, manifest and stable-index backup.
- Archive current SharedTab policy/UI result bundle and Release device compile.
- Keep mirror stable, PC Bridge and user data unchanged.

## F1 — Target isolation

- Add `ChatGPTWebOptimized`, unit tests and UI tests to `project.yml`.
- Sources: `OptimizedApp/`; resources: `OptimizedResources/` only.
- Set `com.masakacj.chatgptweb.optimized`, 0.1.0 Build1, separate app icon/scheme.
- No Safari target dependency, App Group, shared Keychain or shared container.
- Add CI target-membership/forbidden-dependency checks.

## F2 — Conversation Manager contract

- Create `Contracts/ConversationManager/v2` JSON corpus from PC CM protocol2/version0.2.2 semantics.
- Implement typed Swift events/state/reducer/store and a single `ConversationManagerOwner` actor.
- Preserve conservative restore, owner generation, document/sequence/revision, task/read/evidence separation and bounded retention.
- Make Node and Swift consume the same corpus and verify its hash/upstream identity.

## F3 — WK shell

- Build a small new WKWebView stack instead of copying the existing monolith.
- Use a dedicated content controller and named isolated world.
- JS emits bounded facts only; no state store, text extraction, CSS, click, localStorage, fetch/XHR or React mutation.
- Support persistent login, navigation, popup, upload, download, keyboard and scene lifecycle.
- Release inspector is off by default.

## F4 — Native capability layer

- State and persistence remain native-owned.
- Loading error produces a native manual-confirmation candidate only.
- Revalidate twice and click only the current official load panel's Retry once.
- WebContent termination requires a separate confirmed rebuild and bounded budget.
- Add local bounded diagnostics and performance metrics; no remote telemetry by default.
- Keep webpage status display 100% ChatGPT-native.

## F5 — Acceptance/release

- Run contract/unit/synthetic WK/Release compile and physical-device matrices.
- Measure long-chat cold start, interaction readiness, input, scroll, CPU, memory, energy and process termination.
- Create a separate signer key, candidate/stable record and rollback index.
- Confirm existing mirror stable metadata is byte-for-byte unchanged by new-app candidate signing.
- Promote only after real-device acceptance.

## F6 — Mirror cleanup

- Extract SharedTab DTOs/policies from legacy files.
- Make SharedTab the direct mirror root.
- Delete mirror WK fallback, userscript/hot updater, native resilience fallback, Safari Action and old Companion runtime/tests.
- Keep actual upgrade migration for one stable version behind a migration marker.
- Release as a separately verified mirror cleanup candidate; preserve 0.7.2 rollback.

## First implementation increment

Implement only F0–F2 first. Do not copy the old large WK coordinator/userscript and do not remove any mirror code in this increment.

## Evidence discipline

Record source, simulator, device compile, signed candidate, downloadable IPA, physical install, physical acceptance and stable promotion as separate states. No phase becomes passed without an evidence reference in `DEVELOPMENT_STATUS.json`.
