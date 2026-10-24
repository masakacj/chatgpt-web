# iOS Mirror 0.7.18 (20) — Latest Reply Viewport Alignment Contract

Date: 2026-10-24 Asia/Taipei. Delivery intent: candidate only. Ponytail full, minimal native SwiftUI scrolling adjustment, preserve stable and mobile drafts.

## User symptom
Opening the **already current** conversation in the iOS mirror app still leaves the final portion of the latest assistant reply below the viewport, requiring finger swipe up to see it.

## Confirmed source issues
1. `SharedTabModel.open(_ chat:)` early returns when `snapshot?.conversationId == chat.id`. Prior `SharedTabScreen` waited on ID/document/last-text changes or its own first appearance to align the latest reply. Re-selecting the currently displayed chat could therefore retain an earlier scroll position. This is a reachable deterministic behavior.
2. `LazyVStack` has demand-driven cell height/layout. The prior `scrollTo(lastMessage.id, anchor:.bottom)` may execute before final rendered cell bounds stabilize. `STTranscriptContentHeight` observed estimated whole-stack height, and existing XCTest accepted even partial intersection with the viewport instead of checking the true message footer.

## Exact repair
- On sidebar conversation selection (including **same conversation ID**), explicitly set `followLatest=true` and increment `latestScrollRequest`; the transcript's `ScrollViewReader` handles it without PC navigation/Send.
- Add a bounded geometry-based correction: measure the actual *last message* bottom in named scroll viewport coordinates, and trigger one more native `scrollTo` only when the footer is still BELOW the viewport. Continue existing dynamic content height/last-ID/last-text tracking. Never scroll while user intentionally browses older turns; queued callbacks revalidate `followLatest` and last message identity.
- No blanket view reload, no removal of `LazyVStack`, no forced PC browser scroll, no history prefetch, no app version transition unrelated to the signed candidate.

## Test and release gates
- `UITests/SharedTabUITests.swift`: `testReopeningAlreadySelectedLongChatReturnsToActualLastReply` navigates into history then chooses the same sidebar chat, asserts return-to-latest control disappears and latest reply footer is above composer; this fails logically on original code because model.open returns without changed IDs.
- `testTallFinalReplyFooterIsVisibleWithoutManualSwipeUp`: fixture adds a tall final answer with explicit ending marker, asserts it is within viewport and above composer, no manual swipe.
- Tighten existing `testOpenLongChatPositionsLatestAnswerInViewport` to require the actual reply footer, not merely an intersecting frame.
- Keep all other ShareTabUITests, draft/Send/Stop/concurrent receipts/new chat/image/URL acceptance; require macOS Xcodegen, full simulator UITests and iPhone Release SUCCESS on exact source SHA.
- Independent CC GPT-6 review bound to final source, any review findings repaired/retested. Candidate signing only after verified CI and narrowly restricted Debian signer branch/workflow/SHA; actual IPA+manifest/public installation verification, stable unmodified.
- Repo `masakacj/chatgpt-web`, baseline `d7efdf7a00f60bce2d3e87212b4fc337c4377869` (previous signed 0.7.17/19), new branch `fix/mirror-latest-scroll-0718-20261024`, version `0.7.18 Build20`, unchanged main bundle ID `com.masakacj.chatgptweb`.

## First actual macOS CI findings and minimum correction
- Original candidate Git SHA `6e9a7be77b03fb0ce8944908c58f47d43f27da57`, Actions Run `40087825448`: **78/79 Simulator UI tests PASS**, including every new latest-reply strict viewport/reopen/tall-last-message test. The only failure was existing `testR35ReviewFixModelSelectNilEvidenceRemainsUnconfirmed`, which long-pressed the model picker and did not observe its model option within 8 seconds. This is not a failed latest-reply alignment assertion; do not label the entire fix rejected for scrolling.
- Suspected interaction: tracking the last cell bottom in `@State` caused a parent/composer re-render on each scrolling geometry frame while the model popover was being opened. Minimum correction removes that per-frame `@State` write, uses the preference change solely for conditional corrective `scrollTo`, skips corrective jumps while model picker is visible, and only tracks material (>1pt) viewport size changes. Preserve all long-reply scrolling alignment behavior.
- Added `testModelPickerRemainsAvailableDuringLongTranscriptLayoutCorrection`: during a long loaded transcript, the model picker must remain available and produce the existing unconfirmed selection behavior; no real PC model change. Full macOS Simulator and device build must rerun on the new Git SHA before signing. Do not mislabel the first failing run as passed.

## Safety
Don't send real user ChatGPT messages, don't navigate or reload foreground PC tab, don't change phone Keychain or stored drafts, don't promote stable. Do not claim on-device acceptance until real iPhone user verifies visual scroll.
