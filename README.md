# ChatGPT Web iOS — 0.7.2 (Build 4)

This repository contains the **current iOS app**. Historical experiments, one-off patch scripts and older release plans are not part of the current source tree.

**Official signed version:** **0.7.2 Build 4**  
**Install / update:** https://ipa.78175132.xyz/  
**Bundle ID:** `com.masakacj.chatgptweb`  
**Exactly signed and verified application source:** `8440857cf0bf485ce79d408b74b8380069eb08dc`  
**Verified signing pipeline:** [GitHub Actions run 38327609864](https://github.com/masakacj/chatgpt-web/actions/runs/38327609864).

## How it works

The iPhone's native SwiftUI interface is a **structured remote desktop** for an explicitly paired **PC Chrome ChatGPT tab**. The PC webpage is the sole execution and message source. The phone mirrors already-mounted page content and sends deliberate interactions back to that same tab. No automatic history crawling, second ChatGPT chat database, or background webpage takeover.

The app retains its signed-version Safari/WKWebView fallback, embedded web script, local-draft protections, and opt-in performance telemetry. The independent **PC Bridge** is maintained outside this iOS repository.

**Official PC endpoint:** `https://chatgpt-pc.781751.xyz:58443`  
**PC-only pairing page:** `http://127.0.0.1:13213/local/pair` (open on the PC, not on the iPhone).

## Source layout

- `App/`: native client, remote-page mirror, composer, local drafts, web fallback.
- `Resources/`, `SafariScriptAction/`, `safari/chatgpt-safari.user.js`: current iOS resources and embedded Safari fallback.
- `UITests/`, `scripts/`: checks and fixtures for current features.
- `telemetry-worker/`: backend for the current app's **opt-in** performance diagnostics.
- `project.yml`, `package.json`, `.github/workflows/ios.yml`: repeatable builds, source checks and simulator tests.

## Development

Run `npm run check` and `xcodegen generate` on macOS, then build with Xcode. CI **does not sign or publish an IPA on push**; official signing and production promotion are separate, explicit deployment actions.

The **iOS app version is 0.7.2**. The embedded web userscript retains its independently versioned runtime **0.6.0**, matching the already signed app. The repository clean-up changes metadata/CI/docs, not the exact verified application source under `App/`, `Resources/` or the included browser script.

**Acceptance boundary:** simulator/build, signed IPA and PC HTTPS have been checked. Full real-iPhone remote operation and latency acceptance have not been claimed. Details: [Current release notes](docs/CURRENT_RELEASE.md).
