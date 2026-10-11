# iOS PC companion 0.5.0 — beta handoff (2026-10-11)

This is the user's explicitly requested continuation of native iOS development after the dedicated NPM/AliDNS channel was built. PC remains the original Chrome extension, not Tampermonkey. The original iOS WebKit mode remains an explicit fallback; PC mode does not retain a hidden WKWebView.

## Existing endpoint — DO NOT rebuild infrastructure

Default origin: **https://chatgpt-pc.781751.xyz:58443**. The port is required. It is an API origin, not the IPA install page.

NPM is on **192.168.233.127**, not Debian itself. The pre-existing channel routes only `/v1/` through NPM host15/certificate8, the dedicated relay and WireGuard to the same Orchestrator's restricted loopback3211. Admin3210, `/executor`, and the pairing management page are not public. The new iOS client does not change PC extension/backend or network configuration.

PC local setup page: http://127.0.0.1:3210/mobile.html (localhost:3210 also works). Explicitly reveal/copy the pairing key there, then paste it into the native PC connection sheet. The app pre-fills the domain. No real pairing token is embedded in app source, logs, CI, screenshots, or this handoff. Keychain holds the key after a successful read-only tab-list check; URLSession pins the validated origin/key per connection and refuses redirects. Editing the sheet does not redirect an in-flight request to the new origin.

## Implemented native client

- `App/PCCompanionPolicy.swift`: pure Codable draft reducer and HTTPS/read-retry policy, compiled outside UIKit for tests.
- `App/PCCompanionView.swift`: native selectable message text, safe clickable links, copy button, recent snapshot, native editor, connection sheet, same-chat restore, explicit draft sync/Send/receipt lookup.
- `App/PCCompanionTestProtocol.swift`: DEBUG-only URLSession fixture; only installed when BOTH UI-testing and network-fixture flags exist. Never connects to the real PC. Release build excludes its implementation.
- Existing `PCCompanionRootView.swift` and `ContentView.swift` retain lazy original WebKit fallback. Default Web mode remains; PC mode opt-in is persisted.
- `scripts/prepare-companion-beta.mjs`: exact-match integration for safe local receipt persistence and version alignment, applied in GitHub CI, committed only after tests succeed.
- `scripts/companion-ui-test-support.mjs`: installs DEBUG-only counters and keeps the offline fixture isolated from actual pairing state.

Version package/project/shared menu metadata aligns to0.5.0. The old iOS menu script receives only a version bump, not a new PC injection path. Retired desktop userscript files remain inert.

## Draft and send guarantees

Phone input is local; Sync Draft and Send are separate actions. Every local edit has an integer revision, conversation owner and expected PC draft hash. A late PC snapshot from before a successful sync cannot overwrite the newer phone text. Typing while a sync or Send is outstanding remains local; a subsequent confirmed receipt clears only the exact originally submitted text/revision, not the next draft.

The app stores draft/owner/hash/expected-echo and pending Send in protected Application Support files, excluded from backup. A Send is not dispatched if its local pending receipt reservation cannot be written. Existing PC/server idempotency reservation mechanisms are unchanged. Unknown results trigger receipt GETs only. The UI includes an explicit 'already checked on PC' confirmation to unblock a permanently ambiguous receipt; this does not replay the request or delete the server's reservation.

Incoming page data is rendered as text, not executable HTML. Existing images/attachments/complex MCP controls remain on PC. Native read/unread/task flags are not fabricated; the client displays the PC snapshot status. It does not fetch ChatGPT API directly.

## Reconnect and lifecycle

Only session reads receive bounded reconnect attempts (1/2/4/8 second delays, four attempts).401/403/429, certificate trust problems, invalid schema and conflicting pages do not trigger blind retries. No queued offline Send: ephemeral URLSession fails promptly when connectivity is absent.

Backgrounding cancels the read task and stores local content. Foregrounding resumes the same session; on410 it queries already-open tabs and resubscribes to the SAME previously selected conversation. It never navigates PC to another conversation. No global browser/profile recreation, cache wipe, or user tab refresh.

The selected conversation is persisted for app reopen. Still-unresolved cases, including changed PC route or an occupied old subscription after a lost connection, preserve the offline view and show a reconnect/reselect instruction. Connection generation numbers reject stale asynchronous callbacks. Snapshot persistence is throttled rather than writing every streamed character.

## Validation distinctions

The native policy executable checks HTTPS port/origin rejection; latest-draft vs stale-snapshot; typing during sync/Send; local restart data; first empty-editor pairing; cross-conversation draft ownership; read-only retry classification; and opaque receipt path validation.

Real iPhone Simulator UI tests use the DEBUG URLProtocol to test the native URLSession decoding and UI together: offline native view has0 WebViews, transient503 GET recovers with0 Sends, expired session resubscribes once,409 draft conflict preserves input, and a503-after-Send only checks its receipt (single Send; later draft preserved). An additional test calls the REAL public endpoint WITHOUT ANY KEY and requires401 using Apple's normal TLS validation. Original WKWebView preservation and native emergency-menu UI regressions are retained.

The real PC public-channel test was re-run from the office with the user's key staying local: all11 cases passed, including actual readonly content, bearer auth, admin-path isolation and20-second long polling. No real editor edits or test prompts were sent.

**This is not yet a physical iPhone authenticated roundtrip to a real ChatGPT Send.** A signed beta is intended to enable that last user-device acceptance. Do not claim that public401 plus mocked authenticated UI is the same as full physical end-to-end verification.

## Release and rollback

Keep source in GitHub, using the existing Actions build/sign/install-center pipeline. Do not check out iOS code or download IPA onto MCP machines. After branch validation succeeds, merge the tested source and verify actual package version/build, signing result and install manifest before reporting availability.

The beta keeps original web mode available; users can install in place without uninstalling or clearing login state. The previous signed0.4.44 build remains a fallback, subject to certificate validity. Revert only iOS companion changes if needed; do not roll back the working PC extension, remove NPM host15, restore Tampermonkey, or clear pending-command journals.

Final CI run IDs, release build and manifest verification are appended below only after they are observed.
