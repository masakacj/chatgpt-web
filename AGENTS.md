# Current iOS repository — two independent product lines

**USER-APPROVED NEW PRODUCT PLAN 2026-10-13:** Keep the existing signed `ChatGPT Web` structured-mirror app frozen as an independent stable line and add a second side-by-side target named **ChatGPT Web Optimized**, bundle `com.masakacj.chatgptweb.optimized`, in this same repository. The new app is WKWebView-only, has independent login/site data/storage/signing/release, and must contain no SharedTab/PC Bridge or Safari code. Read `docs/optimized/PRODUCT_CONTRACT.md`, `ARCHITECTURE.md`, `EXECUTION_PLAN.md`, `ACCEPTANCE_PLAN.md`, `IMPLEMENTATION_HANDOFF.md`, root `DEVELOPMENT_STATUS.json`, and `docs/mirror/MIRROR_072_SIGNED_BASELINE.md`. Planning/handoff only so far: no optimized target/runtime/signing exists, and mirror cleanup is blocked until optimized physical-device acceptance.

For the existing **mirror line**, maintain only the current signed iOS release source and its actual build/test dependencies. The source of signed 0.7.2 Build4 is `8440857cf0bf485ce79d408b74b8380069eb08dc`; official install center https://ipa.78175132.xyz/. Do not silently mix previous 0.4.x/0.5.x artifacts, change its stable pointer for Web Optimized work, or start a second PC Bridge.

**Mirror product:** iOS native structured remote desktop for the existing logged-in PC ChatGPT Chrome tab, not an independent ChatGPT client. PC DOM is sole business/data source; the phone mirrors actually mounted content and forwards explicit user actions to the bound tab. Never prefetch full private history, force Chrome foreground, overwrite the PC input, or replay unknown sends/approvals.

**Current mirror code:** `App/`, `Resources/`, `SafariScriptAction/`, `safari/chatgpt-safari.user.js`, `UITests/`, and `telemetry-worker/` remain frozen through Web Optimized F5. Backend PC Bridge 0.3.10 and private pairing data are not stored here. Web Optimized source must live only under its isolated target directories and cannot import mirror/Bridge/Safari code.

**Build safety:** `npm run check`, `xcodegen generate`, simulator UI tests, and Release device compilation are verification only; never publish/sign because code was pushed. Preserve mirror Bundle ID, Keychain, drafts and receipts. Web Optimized requires its own App ID/profile/signer/stable index and physical-iPhone gate.

See `README.md` and `docs/CURRENT_RELEASE.md` for the current mirror release; see `docs/optimized/IMPLEMENTATION_HANDOFF.md` for the planned second product.
