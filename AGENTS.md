# Deployment rules — current PC/iOS routing

## USER SCOPE CORRECTION — ONLY extract the bridge (2026-10-11)

User: “为什么会影响编排器？只是要剥离桥接的部分。” The assistant incorrectly expanded this into replacing the original executor and rebuilding Orchestrator as an optional adapter. **Cancel that scope.** The latest authority is **masakacj/chatgpt-pc-bridge/docs/HANDOFF.md**, section “最新范围纠正”. It supersedes old M3/adapter/single-extension-ID proposals in the previous plans and implementation status documents.

KEEP Orchestrator's existing executor extension, original ID/storage,3210,/executor,workflow execution,queues,archive/delete and PC resilience. ONLY extract paired mobile bridge modules and the embedded3211 service. A separate bridge-only extension with its own ID is intended; two different-purpose extensions may coexist. At cutover disable/remove ONLY the old mobile initialization/handlers and embedded3211 listener. Do not make Orchestrator depend on the Bridge to execute its existing workflows and do not move its executor code into the new repository.

The current0.1.0 development package still contains copied PC resilience registration and legacy `__ORCH_MOBILE_*` globals. Remove duplicate non-bridge registration and isolate the bridge namespace before co-installation. Do not install the unmodified prototype alongside production and call it tested coexistence. Preserve the old executor storage/ID; retain server pairing and command journal, and reconcile ONLY mobile-specific reservations needed by the new Bridge. Same-tab conflicts need a small check against actual task/input/generation/approval state, not an executor rewrite or distributed-lock framework.

This clarification updates scope/handoff only. No runtime change, production migration or coexistence test has occurred in this correction turn.

## Implemented baseline — standalone PC Bridge development0.1.0

Independent code: mcpoffice `D:\workspace\py\chatgpt-pc-bridge`, workspace `ws_53924e782d`. Read local docs/HANDOFF.md and the latest scope above before following DEVELOPMENT_STATUS.json or previous milestone descriptions. Standalone service/direct MV3 connection/settings are implemented and reusable. Prior isolated results:37 Node,23 legacy mobile MV3,6 actual standalone-extension cases passed;22 JavaScript files checked. Those results describe the prototype, not the corrected two-extension coexistence target. The longer native-state MV3 suite timed out and was not counted as passed. No real user Sends.

Production remains unchanged. Full GitHub source import was still pending at the last milestone; complete local code and ZIP exist. Do not recreate the project or reconstruct code from prose. Next: slim to bridge-only, finish source publication, disable old mobile-only handlers at controlled cutover, verify original executor and new Bridge coexist, continue iOS. **No optional executor adapter task.**

## iOS native UX plan v0.7.0

User requires official-app-like layout, arbitrary account-history chat selection rather than only mounted sidebar rows, ordinary/in-project new chat, and **mobile-local draft submitted ONLY on explicit mobile Send**. PC editor text must not echo into the iPhone composer. No sync-draft/adopt-PC-draft UX. Read docs/IOS_070_NATIVE_UX_PARITY_HANDOFF.md for iOS behavior, using the bridge-only scope correction above for PC architecture.

These iOS0.7 changes remain unimplemented at the recorded milestone. Recorded signed baseline is v0.6.0 Build221 as checked on2026-10-11; recheck live release metadata for any newer claim. Prior0.6.1 CI failures are not successful releases. Do not describe simulated authenticated UI/TLS tests as physical-phone acceptance.

## Network and production boundaries

Existing iOS API origin: `https://chatgpt-pc.781751.xyz:58443`. NPM is on192.168.233.127, not Debian. Keep DNS,proxy,VPN and external `/v1/` route; only the owner of local3211 changes when actual migration is tested. Pairing keys stay local/Keychain and never appear in logs/source. Native PC mode has no hidden WKWebView; original web fallback remains. Unknown Sends are queried, never replayed; late receipts must not erase newer drafts.

Original executor installation: mcpoffice `D:\workspace\py\chatgpt-orchestrator\extension`, ID `hkpkilpjbeneliaiafdbkaomedgkkcmi`, Administrator Chrome Default. Keep this executor and ID, rather than migrating them to Bridge. Read current PC_DEPLOYMENT.json, MOBILE_STRUCTURE_HANDOFF.md, MOBILE_CHANNEL_HANDOFF.md and AGENTS.md before modifying the old mobile wiring. The old chrome-extension-bridge test Profile is retired, not production.

PC remains extension-based; never reactivate Tampermonkey/Desktop Lite/Unified. Do not delete history, prune MCP DOM, block iframes, clear login/site data, introduce idle transcript polling, replay generation/tool requests, or restart/close user Chrome. Existing page status/performance behavior remains in the old extension. Source edits and release tags are not proof of live activation. PC-only symptoms do not authorize unrelated iOS release changes.

## Build, tests and release

iOS sources remain in GitHub; do not create iOS checkouts or save IPA files to MCP project directories. The independent PC project is authorized on mcpoffice. Build/test the changed modules, reuse existing tests, and record exactly what ran. Do not add speculative frameworks or make full executor migration a release prerequisite for bridge-only work.

Inspect current workflows before reusing historical preparation scripts. Prototype fix-pc-companion-invariants.mjs and historical failed finalizers are not current integration commands. Merge tested source SHA and use the existing iOS signing/install-center path. Verify GET latest/version/build/manifest and actual signed package; HEAD404 on the install server is not proof of missing GET artifact. Report incomplete true-device/network acceptance honestly.

Keep previous signed builds and Bridge package combinations as rollback references with certificate/compatibility verification. Never clear pending journals, restore retired userscripts or rebuild the working network for rollback. Update local/GitHub handoff with actual changes,tests,commit/package,deployed yes/no and next step; current scope above overrides older planning records.
