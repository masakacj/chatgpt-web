# Deployment rules — current PC/iOS routing

## Current iOS PC companion (2026-10-11)

The user explicitly authorized the structured-PC native iOS client. Read `IOS_PC_COMPANION_050_HANDOFF.md` and `IOS_PC_COMPANION_RELEASE.json` FIRST for this feature. They supersede the old prototype notes saying the external channel or IPA is unavailable.

Version0.5.0 Build219 is signed and uploaded through the existing main workflow. Exact release verification and any still-running full CI status are in the release JSON/run. Selected native acceptance8/8 and42+30 policy assertions passed. This is a BETA for physical-phone pairing; authenticated real-iPhone send/receive is not yet user-verified. Do not confuse mocked authenticated simulator tests with the real unauthenticated public TLS test.

The existing dedicated API origin is `https://chatgpt-pc.781751.xyz:58443`. NPM is on192.168.233.127, not Debian. Do not rebuild DNS, proxy, VPN or the PC extension merely to update iOS. Pairing key stays local/Keychain and must never appear in source, logs or public handoff. Native PC mode has no hidden WKWebView; original web mode is an optional fallback. Unknown Sends are queried, never replayed; late replies must not overwrite new drafts.

## PC rules retained

- PC is **Chrome extension only**, explicitly confirmed by the user. Never request Tampermonkey installation/update or reactivate Desktop Lite/Unified userscripts.
- Live PC source: mcpoffice `D:\workspace\py\chatgpt-orchestrator\extension`, ID `hkpkilpjbeneliaiafdbkaomedgkkcmi` in Administrator Chrome Default. Read its current `PC_DEPLOYMENT.json`, `MOBILE_STRUCTURE_HANDOFF.md` and `MOBILE_CHANNEL_HANDOFF.md` before work.
- The old `D:\workspace\chrome-extension-bridge` ChatGPT optimization profile is retired, not production. Preserve unrelated workflows and credentials.
- Do not delete messages, prune historical MCP DOM, block iframes, clear website/login data, or introduce idle full-transcript polling. Do not revive destructive debug experiments.
- A source edit or GitHub release is not proof of actual PC extension activation. Use the same installed extension's live audit when PC changes are explicitly requested.
- Do not change or release iOS for PC-only symptoms. The user's later explicit iOS companion request is a separate authorization, not evidence that old PC symptoms occurred on iPhone.

## Build, tests and release

Keep iOS sources in GitHub. Do not create iOS checkouts or save IPA files to MCP project directories. Existing remote hosts may run metadata-only checks and stream-check archive integrity without persisting binaries.

`pc-companion-check.yml` runs exact/idempotent preparation, native policy tests, device compilation and real simulator tests, then commits the tested source. `prepare-companion-beta.mjs` is the current integration helper. `fix-pc-companion-invariants.mjs` is historical prototype code; do not run it against current sources. The one-off finalizer was removed and its historical failed run is not acceptance evidence.

Merge only the tested source SHA. Use the existing signing/install-center workflow, verify latest version/build and actual GET manifest/IPA. The install server does not implement HEAD or byte ranges; HEAD404 is not proof the GET artifact is missing. Report incomplete full-device or network acceptance honestly.

Update the release JSON and local iOS handoff after verified changes. Preserve0.4.44 Build218 as a rollback reference, checking certificate validity before reuse. Rollback must not clear pending-command journals, restore PC userscripts, or undo the functioning NPM channel. Install updates in place, without uninstalling.
