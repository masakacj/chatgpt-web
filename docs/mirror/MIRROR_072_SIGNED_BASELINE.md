# Mirror 0.7.2 Signed Baseline

Date: 2026-10-13
Status: frozen production baseline; no runtime change in this planning update
Product: ChatGPT Web structured mirror

## Authoritative identity

- Repository: `masakacj/chatgpt-web`
- Current `main`: `fac5b7873ff0e7b643187ad1f852a234dec767e1`
- Source used for the signed release: `8440857cf0bf485ce79d408b74b8380069eb08dc`
- Tag: `v0.7.2`
- Bundle ID: `com.masakacj.chatgptweb`
- Version/build: `0.7.2 (4)`
- IPA ID: `12112229-485f-49e1-afba-896caa875853`
- Signing run: `38327609864`
- Official install center: `https://ipa.78175132.xyz/`
- PC backend: independent PC Bridge 0.3.10

`main` is one cleanup/metadata commit ahead of the signed source. The cleanup removed historical workflows, patch scripts and stale handoffs; it did not rewrite the signed application source under `App/`, `Resources/`, `SafariScriptAction/`, or the bundled web runtime. A build from `main` is not the already-signed artifact and must never be presented as the exact existing IPA.

## Product boundary

This product is the native structured remote desktop for one explicitly bound PC Chrome ChatGPT tab. The PC webpage is the sole execution and rendered-content source. The phone mirrors already-mounted content and forwards deliberate user interactions with durable command receipts.

The mirror line owns:

- SharedTab native UI and transport
- per-conversation phone-local drafts
- unknown-send and interaction receipt protection
- official search/new-chat/project-new-chat remote actions
- structured message, code, table, link and media presentation
- connection lifecycle and offline snapshots

It must not be changed as a side effect of the new Web Optimized line.

## Data that must remain untouched

- `ChatGPTWeb.PCCompanion.v1` Keychain pairing item
- `SharedPC.clientID`
- `SharedPCCompanion/state.json`
- current endpoint and selected-tab preferences
- pending/unknown command receipts
- formal Bridge pairing and journal
- current signed IPA and stable index

The new Web Optimized target will not read, write, copy or migrate any of these.

## Existing compatibility debt

The mirror binary currently also compiles:

- a release-reachable WKWebView fallback;
- a Safari Action extension and bundled userscript;
- release-unreachable old PC Companion UI/model used only by DEBUG fixtures;
- shared wire DTOs declared inside legacy-named source files;
- a release-visible stage-Bridge selector.

These are not removed until the independent Web Optimized app has passed physical-device acceptance. Cleanup is tracked separately and remains blocked.

## Missing baseline evidence to collect in F0

Before implementation work is marked beyond planning, record:

- official IPA SHA-256 and exact byte count;
- signing certificate fingerprint and Team ID;
- provisioning profile UUID, expiry and entitlements;
- installer manifest and stable-index backup identifier;
- current SharedTab policy/UI result bundle;
- current generic-device Release compilation result.

## Rollback rule

The preserved signed 0.7.2 Build 4 IPA is the mirror rollback artifact. No new schema or cleanup may make existing mirror data unreadable by that release. Web Optimized development, signing or promotion must never update the mirror stable pointer.
