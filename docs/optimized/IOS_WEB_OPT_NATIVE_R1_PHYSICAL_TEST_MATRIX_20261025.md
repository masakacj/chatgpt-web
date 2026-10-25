# iOS Web Optimized Native R1 — physical iPhone acceptance matrix

Contract: `IOS-WEB-OPT-NATIVE-R1-20261025` · Date: 2026-10-25 · Status: **NOT TESTED** until a named physical iPhone and **new** signed candidate supply receipts. Existing `0.1.2 (3)` at source SHA 7f54b2a is a baseline-only control, not the optimized R1 candidate.

## Evidence header (mandatory)
- Installed IPA ID and SHA256: `PENDING`
- GitHub signed CI run/head SHA: `PENDING`
- Bundle ID: `com.masakacj.chatgptweb.optimized`
- Candidate version/build: `PENDING > 0.1.2 (3)`
- Physical device model / iOS version / available storage: `PENDING`
- Device install/test date-time and tester initials: `PENDING`
- Original mirror stable pointer hash before/after: `PENDING`
- Main/Project long-chat sample IDs may be kept local, **NOT exported** to shared telemetry.

## Test cases
| ID | Action on actual signed R1 installed iPhone | PASS criteria / evidence |
| --- | --- | --- |
| D01 | Fresh install beside signed Mirror; log into ChatGPT Optimized using its own profile | Independent bundle and website data, no Mirror data modified; screenshot |
| D02 | Start home and ordinary/project conversation, switch chats five times | Latest useful reply visible, correct chat; no phantom Send/approval |
| D03 | Open both historical fixed long-chat samples | For each: 5 cold and 5 warm switches; time-to-last-visible reply P50/P95 logged |
| D04 | Send one manual test turn with keyboard; use actual result/control UI | Draft not re-sent, latest reply and controls work |
| D05 | Stream/MCP-heavy real usage ≥30 minutes | Tool approval, images, attachment, UI/scroll responsive; test notes |
| D06 | Open diagnostics and tap **SIMULATED WebContent termination** | Native safe UI immediately available, no auto reload, journal type simulated, no false real-crash telemetry |
| D07 | Native safe UI: stay safe, export report, tap diagnostics | Controls remain active with WebContent absent; export contains no conversation/text/login/URL data |
| D08 | User confirms one rebuild; navigate safely to home | Exactly one fresh WebView, no automatic Send/Retry/approval, login persistence |
| D09 | Inspect persisted circuit condition using verified test fixture (no private kill API) | If genuine repeated termination is unavailable, **NOT VERIFIED**, not synthetic PASS |
| D10 | Background/foreground, force quit/relaunch, safe state journal | Remains usable; no false claim OOM; user-authorized recovery only |
| D11 | Attach image/file and verify download/popup permissions | Baseline behaviors work; no loss of media or interaction |
| D12 | Resource Gate disabled/off vs enabled only with verified benign allowlisted rule | Disabled equals official behavior; enabled must show actual rule/version, no broken stream/chat/MCP |
| D13 | With Mac Instruments/Web Inspector if available, measure memory/jank | Compare P50/P95 time-to-useful-reply, scroll jank, process exits, thermal/battery; note missing metrics explicitly |
| D14 | Verify signed bundle SHA/install URL and Mirror stable unchanged | All matching metadata and rollback baseline retained |

## Required distinctions
- **Simulated termination ≠ real WebContent termination ≠ app jetsam.** Never claim one as another.
- **Host QA / Simulator / signed IPA ≠ physical E2E.** Each is an independently recorded gate.
- Native Supervisor cannot survive a kill of its containing entire iOS App. Persist minimal journal across restart; detect unknown prior session only, never infer exact OOM cause.
- A NativeResourceGate with zero proven harmless rules may be a valid fail-open implementation but is **not** demonstrated performance improvement.
- Web Extension compatibility on iOS 18.4+ is an independent future A/B gate; not a prerequisite for the N1 safe-mode candidate.

## Status model
`BASELINE_INSTALLED` / `NEW_CANDIDATE_READY` / `PHYSICAL_TEST_RUNNING` / `PHYSICAL_DEVICE_PENDING` / `BLOCKED` / `PHYSICAL_E2E_ACCEPTED`.
Only set `PHYSICAL_E2E_ACCEPTED` when D01-D08,D10-D14 pass on real phone and D09 either tested+passed or clearly conditional/unverified in report with explicit device-coverage limitation. Must never promote stable without a separate user instruction.
