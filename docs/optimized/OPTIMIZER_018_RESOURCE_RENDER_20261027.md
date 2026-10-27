# Optimizer 0.1.8 Build 9 — Native Resource Gate + Bounded History Rendering

Date: 2026-10-27. Source baseline: `82e437f9c3f0fc609d1485b9b5c6f5ee4bac4756`. Ponytail FULL.

## Authorized delivery
Publish an **Optimizer-only signed candidate** to the preexisting independent `chatgpt-web-optimized` install center, version 0.1.8 Build 9. Do not alter Mirror stable 0.7.18 Build 20, account cookies, proxy fail-closed policy, message/retry/stop, MCP approvals or conversations. Physical device performance remains an independent E2E gate; no unmeasured performance improvement claims.

## Minimal implementation
- NativeResourceGate (WKContentRuleList before first navigation): seven simple non-alternating host/path patterns for Google Analytics `g/collect` and `collect`, DoubleClick `pagead` and `activityi`, Google Tag Manager `gtm.js`, Microsoft Clarity `collect` and `tag`.
- All triggers are restricted to ChatGPT top document domains and third-party script/image/raw resources. First-party ChatGPT/OpenAI, login, attachments and MCP resources are deliberately out of scope. Existing previously saved OFF preference wins; initial opt-in default is ON now that valid rules exist. Safe mode disables; rules compile before navigation; failure allows normal page load.
- Native diagnostics shows declared vs actually installed rule count. Resource filtering remains reversible at next WebView construction.
- 24+ turn history: keep latest 12 untouched; stable historical DOM skips redundant full approval scans until a bounded check; `:not(:has(...))` CSS immediately restores painting on dynamically inserted approval/iframe elements; no details folding, iframe unmounting, DOM deletion, or network overrides.

## Evidence and gates
- Local `npm run check`: PASS; telemetry-worker tests: 24/24 PASS.
- Independent CC review first: CHANGES_REQUESTED, rejected unsafe details-fold logic and risky WebKit rule syntax. Follow-up re-review: CHANGES_REQUESTED for URL-filter alternation. Third read-only CC review of exact worktree diff: APPROVE after removing details folding and using seven simple patterns with script/image/raw resource types. Review was static; not a Mac/iPhone result.
- GitHub workflow must compile and install rules in `OptimizedTests/NativeResourceGateTests.swift`, run iPhone simulator XCTest, Release iOS build, sign via existing Home/Office direct signer, verify signed IPA, manifest, bundle ID, version, build and Mirror stable unchanged.
- A successful CI candidate still requires physical-iPhone E2E before any claim of reduced RSS/heat or stable promotion.

## Rollback
If first-party functionality regresses, turn off `第三方统计资源过滤` in Optimizer diagnostics and reconstruct WebView. If history rendering causes issues, turn off `历史内容布局减负` and rebuild. Previous signed Optimizer candidate remains retrievable via its immutable candidate URL.
