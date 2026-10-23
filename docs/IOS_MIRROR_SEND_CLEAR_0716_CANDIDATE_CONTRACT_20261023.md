# iOS Mirror 0.7.16 Build 18 — Confirmed Send Composer Clear (Candidate Build Contract)

Date: 2026-10-23 Asia/Taipei

## User request / frozen goal
User observed that a message sent successfully from the native mirrored iPhone app remains visible in its input box after successful PC Send. User requested **start compile closed loop**.

Expected: after authenticated command receipt `state=done, result.status=sent_confirmed` matching the original command ID, the exact submitted draft is cleared and the on-screen native SwiftUI TextField becomes empty, without requiring a tap/switch. If POST response times out after PC recorded success, read `GET /v1/commands/{originalCommandID}` only and clear when the result is confirmed; never resend. Failed/unknown sends and newer edits keep their text; an old A conversation receipt cannot clear B's currently displayed draft. Model/effort, Stop, history, attachment, notifications, native sidebar and bridge remain unchanged.

## Baseline
- Owner repository: `masakacj/chatgpt-web`
- Branch for authorized *candidate* delivery: `fix/mirror-send-state-20261023-composer-clear`
- Base commit: `e2a01bb4a521b49680c63284972451ac983348e9` (Oct 23 latest actual `feature/mirror-r55-0712-20261020`), descendant of R87 commit `644dc5dc4ae24e749f33ea698b749306331d27dd`.
- Worktree: `C:\Users\Administrator\.devspace\worktrees\chatgpt-web-901b347b`, isolated; do not alter original dirty local project or reuse the **superseded R83** trial at `chatgpt-web-861d2d90`.
- Version: `0.7.16 (18)`, main + extension consistent, Bundle ID `com.masakacj.chatgptweb`.
- Delivery intent: **candidate_release**; compile/test/sign candidate only, stable is NOT authorized for promotion.

## Source modifications / tests
- `App/SharedTabModel.swift`: successful receipt clears only the matching local ledger revision and increments `composerResetToken` for currently displayed composer; on POST error query original command ID once, reconcile only verified `sent_confirmed`. Reuse current `affectsCurrentConversation` check and preserve A/B cross-conversation isolation.
- `App/SharedTabScreen.swift`: `.id(model.composerResetToken)` bound to existing SwiftUI composer, force fresh TextField state only after positive clear.
- `App/SharedTabFixtureProtocol.swift`: lost-successful-POST-response test fixture, one send, read-only GET positive receipt.
- `UITests/SharedTabUITests.swift`: confirmed send clears focused composer and allows next draft; lost POST response but stored successful receipt clears with exactly 1 send.
- `project.yml`, `.github/workflows/ios.yml`, `scripts/sign-candidate-r78.py`: candidate-only version bump 0.7.16 Build 18 and dedicated CI branch; sign step only if validated macOS build succeeded, append candidate receipts, never promote stable.
- Existing fail/unknown Send, late old receipt in B, Stop and Model tests remain in original suite and must continue passing.

## Required closed loop
1. Local: `npm run check`, Git scoped diff check, version / YAML syntax.
2. Push exact candidate branch and SHA without modifying existing r55/main; begin Actions watch *before* external push when supported, or register exact run-specific tracking without disturbing previous CI monitor.
3. GitHub `ios.yml` macOS `validate-build`: Swift policies + Xcodegen + full `SharedTabUITests` + iPhone Release + unsigned candidate artifact.
4. Candidate `sign-candidate`: only if validate-build success; verify source SHA, version/build/bundle/IPA signature and stable-before == stable-after.
5. Independent GPT-6 CC/Web source Review on exact commit SHA; source changes after QA/review require new SHA and new review. Failure → reproduce from actual logs and minimum fix, rerun.
6. Device acceptance remains separate: user should confirm after installing candidate. Do not claim completed release unless actual candidate URL, signature, CI tests and independent review are observed.

## Status
Developer local Windows source checks passed on initial isolated candidate. macOS/XCTest cannot run on Windows and must not be marked PASS until GitHub Actions actual results arrive. Old R81 monitor currently scoped to another R87 SHA / branch; do not overwrite it without verifying its lifecycle.
