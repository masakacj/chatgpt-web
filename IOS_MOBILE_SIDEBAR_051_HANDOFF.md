# iOS 0.5.1 / PC mobile sidebar and Send — 2026-10-11

User acceptance: v0.5.0 Build219 can open/read the paired PC conversation on the physical iPhone. New requests: mirror sidebar projects/chat lists for switching; repair Send where draft reaches PC but no message is submitted.

## Confirmed failure

The current PC command journal showed draft -> done/draft_synced, followed by send -> unknown/error send_unavailable. In released extractor0.1.2 this error occurs ONLY before calling click(), proving that attempt did not send. No original failed message was replayed.

The old selector only recognized data-testid=send-button and two exact labels. The real current page has composer controls without legacy test IDs, including a localized Stop control. This iteration broadens only actual composer Send semantics (localized Send prompt/message, known submit ID), excludes Stop/voice controls, and waits up to1.6s for UI readiness without issuing a request. Tests reproduce an aria-only Chinese Send with no legacy testid. A temporary real-home no-Send inspection could not reach a ready editor and was cleaned up; do NOT claim a new live message was sent/tested.

All guard failures before click now return structured not_sent. The authenticated service records these as failed, not indefinitely unknown. Existing unknown/send_unavailable legacy receipts are corrected to failed/not_sent while retaining ID/hash reservations. Anything after click or a lost response remains unknown and cannot be replayed. iOS failed receipts clear only pending UI state, keep the draft, and display an actionable translated error.

## PC deployed support

Canonical workspace mcpoffice `D:\workspace\py\chatgpt-orchestrator`; Chrome Default extension `hkpkilpjbeneliaiafdbkaomedgkkcmi` only. Manifest0.4.0, executor pc-extension-v38-mobile-sidebar-send, structured module0.2.0. Existing resilience1.1.1/reader/scroll/MCP paths remain unchanged.

New `extension/mobile-sidebar.js`: captures observed sidebar project ID/label/collapsed attributes and links; explicit project expand/more; navigation only by matching a link actually captured in that sidebar. No arbitrary caller URLs, archive/delete/rename, full-history API scrape, or all-project polling. Expanded project links and currently loaded recent chats are partial by design. Unknown project names may be grouped as other projects; not an authoritative account-wide directory.

New paired routes on existing restricted3211: GET /v1/library; POST /v1/library/actions with action project/open. Existing NPM gateway and auth unchanged. List refresh occurs on opening/refreshing the native sheet, not permanent DOM scanning. Native status/read-unread metadata comes from the current extension's already-observed state records.

Switching uses an already-open tab where possible; otherwise it clicks one matching original sidebar chat link. PC unsent draft or current approval blocks navigation. During SPA transition, an old turn key is not rendered as the new chat's messages. The phone also blocks cross-chat switching with a local draft or unresolved Send. No new message/session API or cookie copy.

## iOS implementation

`App/PCSidebarView.swift`: native project DisclosureGroups, search across loaded project/chat titles, PC-open tabs, recent chats, read/unread/running/error indicators, explicit expand/load-more and switching. Reader UI remains the v0.5.0 implementation; no hidden WKWebView added. Entry is the top-right 对话 button; 连接 remains for pairing.

Exact integration is in `scripts/prepare-mobile-sidebar-051.mjs`; isolated test fixture integration in `scripts/prepare-sidebar-fixtures.mjs`. CI commits actual prepared source only after checks. Source remains GitHub, never checked out onto MCP hosts.

Version0.5.1 is a targeted client update. Backend fixes can also report the definite failure to the existing0.5.0 receipt UI; pending original command is never auto-submitted.

## Validation

PC `npm test`:68/68 PASS, including legacy receipt correction without replay and authenticated sidebar route validation.
PC real Chromium MV3+Node fixture:15/15 PASS, including localized aria-only Send, unavailable button preserving draft, duplicate reservation, original editor/IME/MCP protections, project expansion, draft-blocked navigation, and an actual sidebar-link navigation invalidating the old subscription. These use synthetic pages; zero real user test Sends.
Original PC resilience MV316/16 PASS, keeping native read/unread/error/loading protections.
Public HTTPS GET /v1/library with existing local key:200, normal TLS trust,9 project groups/38 loaded chat links/1 open tab; relationships and unique IDs verified. Counts/metadata only recorded, no titles or drafts in public logs. No real navigation or project expansion used for this live check.

Native CI **38110169996 success**, prepared source **aa0904179a033bbd9189b141766d4eb14580c844**: iPhone Release compilation;42 PC policy+30 native state assertions;5 actual simulator UI tests passed (not-sent draft retained/no indefinite pending, project expand/search/switch, prior draft conflict, offline reader with0WebViews, unknown Send receipt preserving next draft). Native transport is an isolated URLProtocol fixture, not a claim that the physical iPhone's new Send has been confirmed.

## Deployment/rollback

Public paired endpoint stays https://chatgpt-pc.781751.xyz:58443. NPM192.168.233.127, existing WireGuard and AliDNS unchanged. No key embedded or exported. Original user report now establishes physical reading success; sending acceptance still needs the updated app/extension result.

PC before-change backup: D:\workspace\chatgpt-rollback\before-mobile-send-sidebar-20261011.zip (112662bytes). Backend restart validates only the loopback3211 listener: WG's10.77.0.4:3211 portproxy is a DIFFERENT legitimate PID and must not be killed. Restart still requires no pending commands; an explicit maintenance switch can allow read sessions to reconnect while preserving durable drafts/receipts. Chrome itself is never restarted.

Signed iOS release details are recorded after actual install-center confirmation. Install in place. Rollback to0.5.0 Build219 is a reference, verify signing validity first; never delete pairing, receipt journal, native drafts, website cache or PC history. Source rollback must retain PC userscript retirement guards.

Remaining scope: only loaded sidebar/history, no deletion/renaming/archiving UI, attachment/MCP complex controls remain on PC. No claim of full physical-phone Send acceptance before the user retries deliberately; known old failed command stays reserved and is not resent automatically.
