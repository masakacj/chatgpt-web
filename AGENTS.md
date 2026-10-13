# Current iOS repository — ChatGPT Web 0.7.2

Only maintain the **current signed iOS release** source and its actual build/test dependencies. The source of the signed 0.7.2 Build 4 is `8440857cf0bf485ce79d408b74b8380069eb08dc`; official install center https://ipa.78175132.xyz/. Do not silently mix previous 0.4.x/0.5.x artifacts or start a second PC Bridge.

**Product:** iOS native structured remote desktop for the existing logged-in PC ChatGPT Chrome tab, not an independent ChatGPT client. PC DOM is sole business/data source; the phone mirrors actually mounted content and forwards explicit user actions to the bound tab. Never prefetch full private history, force Chrome foreground, overwrite the PC input, or replay unknown sends/approvals.

**Code:** `App/`, `Resources/`, `SafariScriptAction/`, `safari/chatgpt-safari.user.js`, `UITests/`, and `telemetry-worker/` are in active use. The embedded Safari script (independent script version 0.6.0) and opt-in telemetry worker remain necessary for the existing app. Backend PC Bridge 0.3.10 and its private pairing data are **not** stored in this repository.

**Build safety:** `npm run check`, `xcodegen generate`, simulator UI tests, Release device compilation. The GitHub workflow is **verification only**; never publish/sign to the stable install center merely because code was pushed. Physical iPhone verification remains separate. Preserve app Bundle ID and existing Keychain/unsent drafts in updates.

See `README.md` and `docs/CURRENT_RELEASE.md` for the sole current release record.
