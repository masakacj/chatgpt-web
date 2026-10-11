# Deployment rules — current PC/iOS routing

## LATEST IMPLEMENTATION — standalone PC Bridge development 0.1.0

The user has started development and requests efficiency, reuse of tested modules and concise factual handoff. Read **docs/PC_BRIDGE_IMPLEMENTATION_STATUS.md** first, then the independent project's **masakacj/chatgpt-pc-bridge/docs/HANDOFF.md**. Independent implementation is in mcpoffice `D:\workspace\py\chatgpt-pc-bridge`, workspace `ws_53924e782d`. Standalone Node service, actual MV3 extension/direct WebSocket and settings are implemented; 37 Node, 23 legacy mobile MV3 and 6 actual standalone-extension scenarios passed locally, with 22 JavaScript files checked. Tests use isolated synthetic pages, zero real user Sends. The older long native-state MV3 suite timed out and is not counted as passed.

**Not deployed.** Optional Orchestrator executor adapter, production cutover and iOS0.7 changes remain pending. The independent GitHub repository is initialized but complete source import is still pending; the full local implementation and development ZIP are the actual code at this milestone. Do not recreate the project or reconstruct code from prose. Existing production remains the same Default Profile extension and Orchestrator-owned3211 until a tested migration. Preserve essential duplicate-Send, wrong-chat and user-data protections without adding speculative frameworks.

## ACTIVE PLAN — iOS official-like native UX parity v0.7.0 (2026-10-11)

User explicitly requires a ChatGPT-official-app-like native layout, arbitrary account-history chat selection (not only currently mounted PC sidebar), ordinary and in-project new chat creation, and **mobile-local draft with one-way submit ONLY on mobile Send**. PC editor drafts must never be echoed into or overwrite iPhone composer. No automatic sync-draft or adopt-PC-draft UX. The authoritative development / test / release / rollback plan is **docs/IOS_070_NATIVE_UX_PARITY_HANDOFF.md**; read it before implementing this iOS work.

The iOS0.7 changes remain planning only, not an implemented feature or signed IPA. Recorded release baseline is **v0.6.0 Build221** via install-center GET on 2026-10-11. New0.6.1 Mobile Controls CI runs were failing/cancelled at that inspection; recheck before claiming a later release. Target v0.7.0 is provisional until validated end-to-end on a real paired iPhone. Retain existing PC extension, browser, NPM/WG channel, sending idempotency journals, WebKit fallback and user data.

## ACTIVE WORKSTREAM — standalone PC Chrome Bridge extraction

Read `docs/PC_CHROME_BRIDGE_DECOUPLING_HANDOFF.md` for M0–M6 scope and **docs/PC_BRIDGE_IMPLEMENTATION_STATUS.md for actual progress**, which supersedes older planning-only descriptions. The independent extension and local service are now implemented and tested in isolation. The repository and local project exist, but full remote source import, optional3210 executor adapter, same-ID production migration and iOS compatibility acceptance remain unfinished.

Never install a second competing production extension, delete existing chrome.storage.local state, reinitialize pairing keys or command reservations, start two services writing3211, or disrupt Orchestrator workflows. Keep `/v1/` external origin and WebKit fallback unchanged. Any released iOS client must be reconciled against exactly tested Bridge service/protocol versions. Independent runtime tests are not evidence that production has migrated.

## Historical iOS PC companion baseline (2026-10-11)

`IOS_PC_COMPANION_050_HANDOFF.md` and `IOS_PC_COMPANION_RELEASE.json` record the earlier0.5.0 Build219 beta, not necessarily the latest signed release. Selected native acceptance8/8 and42+30 policy assertions passed at that milestone. Do not confuse mocked authenticated simulator tests with the real unauthenticated public TLS test or physical-phone authenticated Send acceptance.

The existing dedicated API origin is `https://chatgpt-pc.781751.xyz:58443`. NPM is on192.168.233.127, not Debian. Do not rebuild DNS, proxy or VPN merely to update iOS. Pairing key stays local/Keychain and must never appear in source, logs or public handoff. Native PC mode has no hidden WKWebView; original web mode is an optional fallback. Unknown Sends are queried, never replayed; late replies must not overwrite new drafts.

## PC rules retained

- PC is **Chrome extension only**, explicitly confirmed by the user. Never request Tampermonkey installation/update or reactivate Desktop Lite/Unified userscripts.
- Current production installation remains mcpoffice `D:\workspace\py\chatgpt-orchestrator\extension`, ID `hkpkilpjbeneliaiafdbkaomedgkkcmi` in Administrator Chrome Default. Read its current `PC_DEPLOYMENT.json`, `MOBILE_STRUCTURE_HANDOFF.md`, `MOBILE_CHANNEL_HANDOFF.md` and `PC_BRIDGE_DECOUPLING_HANDOFF.md` before production work. New Bridge development belongs in the independent workspace above.
- The old `D:\workspace\chrome-extension-bridge` ChatGPT optimization profile is retired, not production. Preserve unrelated workflows and credentials.
- Do not delete messages, prune historical MCP DOM, block iframes, clear website/login data, or introduce idle full-transcript polling. Do not revive destructive debug experiments.
- A source edit or GitHub release is not proof of actual PC extension activation. Use the same installed extension's live audit when production changes are explicitly requested.
- Do not change or release iOS for PC-only symptoms. The user's later explicit iOS companion request is a separate authorization, not evidence that old PC symptoms occurred on iPhone.

## Build, tests and release

Keep iOS sources in GitHub. Do not create iOS checkouts or save IPA files to MCP project directories. Existing remote hosts may run metadata-only checks and stream-check archive integrity without persisting binaries. The independent PC Bridge project is explicitly authorized on mcpoffice.

`pc-companion-check.yml` runs exact/idempotent preparation, native policy tests, device compilation and real simulator tests, then commits tested source. `prepare-companion-beta.mjs` is the historical beta integration helper; inspect current sources/workflow before reusing it. `fix-pc-companion-invariants.mjs` is prototype code, not a current integration command. The one-off finalizer was removed; historical failed runs are not acceptance evidence.

Merge only tested source SHA. Use the existing signing/install-center workflow, verify latest version/build and actual GET manifest/IPA. The install server does not implement HEAD or byte ranges; HEAD404 is not proof the GET artifact is missing. Report incomplete full-device or network acceptance honestly.

Update release JSON and handoff after verified changes. Preserve previous signed builds as rollback references, checking certificate validity before reuse. Rollback must not clear pending-command journals, restore PC userscripts, or undo the functioning NPM channel. Install updates in place, without uninstalling.
