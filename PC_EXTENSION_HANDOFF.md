# PC Chrome extension-only handoff — 2026-10-10

## Canonical target

The user explicitly retired the Tampermonkey/script optimization approach. PC symptoms are in Chrome, not iOS. The only production PC target is the already installed **ChatGPT Orchestrator Executor** in Chrome Default:

- mcpoffice workspace: `D:\workspace\py\chatgpt-orchestrator`
- extension source: `extension`
- extension ID: `hkpkilpjbeneliaiafdbkaomedgkkcmi`
- backend: local Orchestrator on port 3210
- detailed operational truth: `PC_DEPLOYMENT.json` and `PC_EXTENSION_HANDOFF.md` in that local workspace; check live `/api/health` and extension audit before work.

The old Desktop Lite project under `D:\workspace\chrome-extension-bridge` was an independent test profile, not the user's active Chrome. Its publishing and deployment entries are retired. A previous update there did not update the user's actual extension.

## Cleanup completed in this task

The default Chrome Tampermonkey dashboard was inspected through a one-shot native UI session. Only `ChatGPT Desktop Lite - Conversation Status` and `ChatGPT Web Unified` were deleted. The unrelated script was retained. The two entries had been disabled, but still posed a future reactivation risk. No cookies, site histories or unrelated extension data were cleared.

Local userscript download/meta entries are retirement notices. The old publisher fails closed, the old test extension has no content script, and its deployment registry entry was removed. Historical source rollback archives are outside the active workspaces under `D:\workspace\chatgpt-rollback`. This repository's old Desktop Lite download now also contains no executable optimizer; its test enforces retirement.

The iOS unified script remains for the existing self-signed WKWebView app. It must not be installed into desktop Tampermonkey or modified to address PC-only symptoms.

## PC extension changes

Three new extension-owned modules implement persistent status and guarded saved-conversation load recovery without rebuilding the Orchestrator. Status uses `chrome.storage.local`, migrates known legacy status records, preserves confirmed completion on refresh/close/restart, and treats stale unverified running status as '待同步'. It does not pretend to learn a completion while the browser is closed.

Read failures are observed passively using the extension webRequest API: no headers, bodies, credentials, request blocking, prompt replay or MCP interception. Only a recent transient error on the exact saved-conversation GET plus a visible, empty native conversation-load error can authorize the original Retry button. Drafts, active generation, approvals, existing answers, auth failures, rate limits and active Orchestrator work prevent auto-retry. A persisted two-attempt/five-minute budget prevents refresh loops. There is no automatic whole-page reload.

## Validation boundaries

Node policy and existing workflow tests passed (56 cases at the recorded gate). Isolated **real Chromium MV3** tests passed for tab close/reopen with late sidebar, whole-browser restart, SPA route state verification, one failed GET followed by native retry success, retry budget persistence across refresh, auth non-retry and unsent draft preservation. These are real browser-extension tests with synthetic pages, not claims that every intermittent ChatGPT production failure is fixed.

The actual default Chrome extension has been reloaded and queried; final live version/acceptance records are in the local handoff. No original user ChatGPT tab was refreshed or closed for deployment. Remaining unsupported failures must be captured through that same extension, not diagnosed via iOS logs or the retired test profile.
