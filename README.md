# ChatGPT Web

A self-signed iOS client for ChatGPT built around `WKWebView`, with a remotely updatable performance engine for very long conversations.

## Goals

- Keep ChatGPT's web UI and normal account/session behavior.
- Make long chats smoother on iPhone by controlling rendering cost, media lifetime, and far-offscreen turns.
- Keep the native shell stable while allowing the performance engine and thresholds to update remotely.
- Produce an unsigned IPA in GitHub Actions for self-signing.

## Architecture

```text
SwiftUI shell
  └─ WKWebView (persistent WKWebsiteDataStore)
      ├─ native config injection
      ├─ remote/cached Perf Engine
      └─ JS -> Native metrics bridge

Remote update channel
  remote/manifest.json
      ├─ engine version
      ├─ SHA-256
      ├─ remote thresholds
      └─ remote/perf.js
```

The app downloads `remote/manifest.json`, validates `remote/perf.js` with SHA-256, and keeps a last-known-good copy in Application Support. A bad or unavailable remote update never replaces the bundled fallback.

## Performance modes

- **Auto**: selects a level from conversation length and iOS memory pressure.
- **Balanced**: `content-visibility` and containment; low risk.
- **Aggressive**: freezes far-offscreen turns and unloads old media.
- **Extreme**: can package very old, very distant turns into static snapshots. Recent turns stay untouched.
- **Off**: restores the normal page.

The default remote policy keeps destructive packing disabled in Auto. Manual Extreme mode and iOS memory warnings may use the deeper path.

## Updating only the performance engine

1. Edit `remote/perf.js`.
2. Increment `ENGINE_VERSION`.
3. Update `remote/manifest.json` version + SHA-256.
4. Push to `main`.

No IPA rebuild is required. The app checks the remote manifest, downloads a verified engine, and can apply it with one reload.

## Native app updates

The Settings sheet displays:

- App version/build.
- Cached Perf Engine version.
- Live DOM/turn/tier metrics.
- Remote performance update controls.
- GitHub Release update check.
- Cache cleanup that keeps login cookies.

## Build

GitHub Actions generates the Xcode project with XcodeGen and builds with code signing disabled. The produced IPA is intended for your own signing workflow.

A tag such as `v0.1.0` publishes:

- `ChatGPTWeb-<version>-<build>-unsigned.ipa`
- SHA-256 checksum

## Notes

This is a personal WebView client, not an OpenAI API client. It does not need to export ChatGPT cookies or store account credentials itself.
