# iOS Mirror 0.7.17 (19) / PC Bridge · Confirmed send & native refresh R142

**Date:** 2026-10-24 Asia/Taipei
**User symptom:** iOS mirror sends once; PC ChatGPT shows the new user message and is Thinking, while phone still shows old draft and stale transcript.
**Delivery intent:** candidate release for iOS; separately reviewed, narrow Bridge Node service patch. Stable App and unsent drafts shall not be replaced/deleted.

## Evidence obtained without real Sends
- Live Bridge 0.3.33 runtime service 0.3.31, authenticated phone endpoint 13213/public HTTPS healthy, 1 bound Chrome tab.
- Private local journal checked for metadata only (no draft/message printed): 352 historical records; 14 compose/unknown/pc_result_unknown plus 7 compose/unknown/sent_unconfirmed, several recent. Some compose/done/sent_confirmed normal.
- Read-only subscription returned status=running, responsePhase=responding, messageCount=9, proving PC mounted messages exist while remote cache may require refresh.
- Existing Bridge `composeSend` clicks PC once then waits bounded 6.5 seconds for a matching native user bubble; a late or absent callback leaves journal unknown, even if PC accepted the message. Existing iOS GET confirmation is one-shot and failed POST path never requests fresh PC capture.

## PC Bridge correction (source checkout)
- `service/mobile-bridge.js` only: reserve a nonce-scoped authenticated baseline (same session/tab/conversation/document, old tail ID, source revision, HMAC of text using existing pairing secret, bounded prior user IDs) before dispatch.
- An authenticated NEW PC-native user turn following the baseline and matching the exact HMAC can settle an unknown original command `sent_confirmed`, never trigger a second POST and never infer from a spinner alone.
- If Chrome delivers a genuinely positive result AFTER the RPC timeout, its original opaque request binding can settle that original journal entry. Pre-click errors, unrelated old messages, different route/ID/sha and unknown callbacks remain unknown.
- The durable per-command journal is retained and should never be rewritten by a speculative classifier.
- Tests: `test/shared-protocol.test.js` new positive-snapshot proof, mismatched/other chat must remain unknown, post-timeout positive Chrome result, no replay. Host `npm test` passed 509/509 initially. Recheck after any change.

## iOS 0.7.17 candidate
- Exact base commit `cb57875e0e8b7eef753bc222a17ba27f0b0e6a83`, original 0.7.16 Build 18 signed candidate.
- `App/SharedTabModel.swift`: same-session, read-only `GET /v1/sessions/:id?after=-1&refresh=1` after Send; bounded 3-attempt asynchronous GET of ORIGINAL pending command ID for uncertain result; never send a second compose. Cancel this reconciliation on pause/rebind and scope by epoch/session/pairing.
- `App/SharedTabFixtureProtocol.swift`: PC already accepted/Thinking but first Send response lost, positive receipt materializes after forced native refresh, single send.
- `UITests/SharedTabUITests.swift`: after send, PC's user bubble and Thinking state appears on phone; exact submitted draft clears; fixture send count remains 1. Preserve existing 75+ tests, Stop, model, attachments, history, per-chat drafts, no background foreground Chrome operations.
- Version 0.7.17 Build19, Bundle ID `com.masakacj.chatgptweb` and extension same.
- New isolated candidate branch `fix/mirror-receipt-sync-20261024`, dedicated CI `ios.yml` and signer `sign-candidate-r78.py`. Stable promotion not authorized.

## QA/Release requirements
- Independent CC source Review on exact SHA and Host QA; policy full Ponytail.
- GitHub macOS simulator Xcodegen/policy/UI suite, iPhone Release compile, unsigned IPA hash, candidate signer restricted by existing Debian exact branch/workflow/SHA allowlist update, public candidate download+plist+IPA ZIP signature and untouched stable index.
- Bridge patch must be deployed only after independent Review and strict zero-session/zero-pending checks, backup and rollback. Prefer Node-only replacement; do not reload Chrome extension or modify project URL/Keychain.
- Do not test with a real user ChatGPT Send without explicit authorization. Test only with synthetic fixtures and read-only live snapshots.
