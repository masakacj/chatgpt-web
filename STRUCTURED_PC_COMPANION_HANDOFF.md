# Structured PC companion — development preview, 2026-10-11

The user explicitly requested implementing a structured mobile frontend: existing PC Chrome runs ChatGPT, its existing extension reads selected visible message content/state, and iOS renders natively and returns draft/Send actions. This is NOT a new browser kernel, remote screenshot viewer, revived userscript, or independent ChatGPT API client.

## Actual status

**Native iOS source is implemented and device compilation + simulator offline-reader UI passed. No new IPA has been signed/published, and no phone-to-PC HTTPS route is connected yet. Keep this feature in a draft PR.** The existing signed iOS version remains unchanged until these gates pass.

PC extension/backend support is installed in the same existing project, with the feature inactive unless a paired client subscribes. No real user test message was sent; final mobile sessions were zero.

## Canonical PC runtime

- mcpoffice: D:\workspace\py\chatgpt-orchestrator, extension directory `extension`.
- Default Chrome extension ID `hkpkilpjbeneliaiafdbkaomedgkkcmi`.
- Manifest **0.3.2**, executor **pc-extension-v35-structured-mobile**, existing resilience **1.1.1** unchanged, companion module **0.1.2**.
- Reuses existing local Orchestrator and `/executor` WebSocket. Restricted mobile API is a second loopback listener **127.0.0.1:3211 in the same Node process**.
- Never expose3210 admin APIs, `/executor`, or Chrome debugger. Future HTTPS gateway must reach ONLY3211.
- Full operational truth, tests, backup and troubleshooting are in local `MOBILE_STRUCTURE_HANDOFF.md` and `PC_DEPLOYMENT.json`; read them before deployment. Do not use the retired independent chrome-extension-bridge Profile.

## iOS files and behavior

- `App/PCCompanionView.swift`: native text reader/editor and restricted URLSession client. Pairing bearer in Keychain, no website cookies. Requires HTTPS origin and rejects redirects. Selects already-open PC conversation tabs. Stores a protected/excluded-from-backup recent snapshot for offline viewing and a local draft with owner/base-hash guards.
- `App/PCCompanionRootView.swift`: opt-in PC mode, default remains original webpage. PC mode has **no hidden WKWebView**, freeing the heavyweight webpage; switching warns about unsent phone-web drafts. Original webpage is a lazy fallback, not removed.
- `App/ContentView.swift`: retains explicit ChatGPTWebView closure so existing app checks are not disabled.
- `UITests/PCCompanionUITests.swift`: offline native fixture, read cached answer, type draft, assert offline Send/sync disabled, secure pairing field, and **app.webViews.count == 0**.
- `scripts/fix-pc-companion-invariants.mjs`: idempotent exact-match integration executed on GitHub CI, not on an MCP checkout. It applies native draft-owner and test fixture changes, and commits source only after gates pass.

Source remains on GitHub. No iOS checkout, source dump or IPA is stored on MCP hosts. PC test harness files are legitimately in the existing local Orchestrator workspace.

## Protocol / security

Native app calls only the restricted paired service, never ChatGPT HTTP endpoints. All `/v1/*` require the random bearer generated locally in the Orchestrator private pairing file; key is never committed, logged or included in URLs. Native stores it in Keychain. Service rejects browser Origin headers and has no permissive CORS/cookie authentication. Local setup page is `/mobile.html` on the original PC localhost management surface, with explicit secret reveal; do not expose that page publicly.

Routes: health, tabs, POST/GET/DELETE sessions, per-session commands and command receipt lookup. Sessions are90-second leases, up to4. A bounded20-second long poll delivers changed snapshots. No active session => no message extraction observers. The current transport sends a whole bounded recent snapshot on change, not a fine-grained per-block delta stream.

Snapshot: schema1; document/conversation IDs; title; status; draft/SHA256; composing/canSend flags; bounded messages with role/text/blocks/links/truncation. Only selected currently mounted recent messages are mirrored. Do not infer that virtualized full history was captured.

Local typing does not send a prompt. Explicit Sync Draft updates the real PC editor only after route/document/deadline, state, IME and draft-hash checks. Explicit Send syncs the draft then clicks the original Send exactly once. Both backend and extension persist command reservations before dispatch; unknown/timeout receipts remain unknown and are queried, never automatically replayed. Confirmed means a new matching user message was observed on the official PC page. PC-side draft edits, input composition, active generation, MCP approval, or running Orchestrator work block overwriting/sending. Draft owner/base hash persist across app restart and cross-conversation selection.

No login credentials, request interception, historical DOM pruning, iframe deletion, page scrolling or automatic PC navigation was introduced. Complex MCP/attachments, images, model selection and file upload remain PC/original-web tasks. Native first version renders selectable text; rich block/link fidelity is not yet fully rendered despite structured fields being available.

## Validation

- GitHub Actions **38101036154**: successful original script/retirement guards, existing compiled native policy, real iPhone device build, real iPhone simulator offline native reader UI. Validated feature source committed as **12eee7e6aac1fa763f0543921ff3cd616835f030**; later documentation may advance the branch.
- PC Node **65/65 tests PASS**, existing MV3 resilience **16/16 PASS**.
- PC new actual Chromium MV3 + authenticated Node service **11/11 PASS**: auth/origin; hidden role marker vs body; Markdown-only message and non-message tool exclusion; Chinese draft without send; PC edit conflict; single Send with duplicate suppression; reply streaming/completion; contenteditable real input event; IME protection; workflow busy; route invalidation. These use synthetic pages, not actual user message submission.
- Actual default Chrome read-only extraction initially exposed an implementation bug: official role markers are H4.sr-only, not body wrappers. Corrected by reading real DIL/explicit-role-associated MarkdownRoot only. Do not scrape every tool Markdown block.
- Corrected actual PC snapshot obtained four visible historical assistant answers (1327/1654/2131/2957chars), headings/lists/tables, no tool-process text mistaken for final answer. Snapshot about82.6KB; local extraction20ms in one read and256ms after extension reload. **These are not phone-network or cold-start benchmarks.** No real Send/editor mutation, and the read-only session was released.
- Same real extension safe reload receipt `probe-1791682989218-ly07b2`: executorv35 confirmed. Current PC handoff carries final live state-restoration audit; never assume a GitHub commit alone changed the user's actual extension.

## Remaining gates before release

1. Configure and verify a trusted HTTPS route to ONLY local3211 using existing network infrastructure; currently absent. Do not install unrelated plugins/services or expose Orchestrator admin APIs as a shortcut.
2. Real native iPhone → service → correct PC extension → official editor/Send → reply testing in a deliberately selected test conversation. Existing tests split native UI from synthetic browser transport; do not describe them as already proving this full path.
3. Verify network loss, backgrounding, leases, app restart, PC navigation/reload and unknown-send receipt behavior. Server/extension restart may currently require reconnect; cached content must remain visibly stale/offline.
4. Improve structure fidelity, older-history pagination and message deltas after the basic real-device path is accepted. PC remote actions and all baseline workflows must remain safe.

## Rollback

Local pre-change backup: D:\workspace\chatgpt-rollback\before-mobile-structured-20261011.zip (111857bytes). It contains previous PC extension/src and deployment/handoff. Restore only while original workflow and mobile sessions are idle, restart only the same Node backend, reload the same installed extension; do not restart Chrome or clear extension/site data. Preserve command journal if later re-enabling, so unknown Sends are not repeated.

This iOS branch is unmerged and original signed app unchanged. Do not bump/publish an IPA simply to claim delivery while external pairing is absent.
