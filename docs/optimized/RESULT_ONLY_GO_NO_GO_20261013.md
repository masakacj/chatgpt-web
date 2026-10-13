# Web Optimized Result Only — Go / No-Go evidence

Date: 2026-10-13
Owner: ChatGPT Web iOS project
Scope: independently signed `ChatGPTWebOptimized` (WKWebView, no PC Bridge) vs existing native-PC mirror.
Status: **NO-GO for strict independent WKWebView Result Only; iOS Simulator benchmark PASSED 2026-10-13**. This does *not* claim a real-ChatGPT iPhone A/B resident-memory benchmark.

## Required outcome

The user wants: own iPhone logs into ChatGPT directly, can use project history, MCP/tool approval, uploads and final rich answers; thinking/tool intermediate content is **not created, retained or animated in the phone's web process**; heavy long conversations do not repeatedly terminate WebContent. A visual hiding-only mode does not meet this definition.

## Existing real-device baseline (CF D1, 0.1.2+3)

- `web_terminated`: 3 ingested rows, **2 unique debug IDs** (one 19:37 observation duplicated by upload retry).
- `memory_warning`: **2 distinct events**.
- Both unique terminated events were on the `project` route and immediately followed by `auto_recovery` and `nav_start home`.
- One memory warning preceded the earlier termination by roughly 12 seconds.
- These establish device memory pressure and process termination during actual use, but not a causal proof of Jetsam. No iOS system crash/footprint profile was captured.

## Platform boundary

- WKWebView loads official ChatGPT's page scripts and maintains React-owned UI/data state. Hiding reasoning/tool DOM or using `content-visibility` does not tell the website to avoid constructing its internal records.
- DOM pruning after React mounts can reduce active nodes but cannot free data still referenced by React; can trigger reconciler/UI errors when page rerenders.
- `WKContentWorld` isolates JavaScript variables but not the DOM. Its isolated-world adapter is insufficient to replace ChatGPT's internal renderer.
- Apple's `WKURLSchemeHandler` expressly does not register for URL schemes WebKit already handles, including `https`. Selective stripping of private ChatGPT stream bodies is not available through this public WKWebView API.
- A reliable zero-intermediate *local* implementation would require an owned application renderer and an independently maintained, supported ChatGPT data/action API, or an invasive unsupported page/request hook. This is not the specified standalone official-web design.

Apple references:
- https://developer.apple.com/documentation/webkit/wkcontentworld
- https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/seturlschemehandler(_:forurlscheme:)

## Isolated A/B experiment (never signs or publishes IPA)

Branch: `experiment/optimized-result-only-go-no-go-20261013`
Workflow: `.github/workflows/optimized-result-only-feasibility.yml`
Test: `OptimizedTests/ResultOnlyWebKitFeasibilityTests.swift`
Actions run: https://github.com/masakacj/chatgpt-web/actions/runs/38399873801

On an actual iOS Simulator WKWebView, an **explicitly synthetic React-like workload** generates 400 turns x 6 intermediate records plus final answers and an approval button.

Modes:
1. `full`: all intermediate DOM and app state retained.
2. `css_hidden`: all intermediate DOM and app state generated; CSS hides the intermediate DOM.
3. `offscreen`: content-visibility / intrinsic-size optimization of layout, without removing records.
4. `dom_pruned`: delete intermediate DOM after mount but keep app state.
5. `owned_final_only`: controlled fixture never constructs intermediate DOM or model records.

Assertions check intermediate DOM, stored model records and visible UI controls. `retainedPayloadBytes` in the fixture is *logical payload capacity*, **not measured RSS or JavaScript heap residency**. Layout timing is illustrative and device-dependent. This experiment alone does not establish exact WebContent memory savings, crash rates, or authentic ChatGPT React compatibility.

## iOS Simulator measured evidence

- GitHub Actions run `38399873801` completed **success**, one iOS Simulator WebKit XCTest passed, zero failures.
- The five modes produced the following counts from the same fixture:

| Mode | DOM elements | Intermediate DOM nodes | Hidden intermediate nodes | Retained intermediate model records | Final answer nodes | Approval buttons |
|---|---:|---:|---:|---:|---:|---:|
| full | 3,609 | 2,400 | 0 | 2,400 | 400 | 1 |
| css_hidden | 3,609 | 2,400 | 2,400 | 2,400 | 400 | 1 |
| offscreen | 3,609 | 2,400 | 0 | 2,400 | 400 | 1 |
| dom_pruned | 1,209 | 0 | 0 | 2,400 | 400 | 1 |
| owned_final_only | 1,209 | 0 | 0 | 0 | 400 | 1 |

- The experiment intentionally embeds only synthetic fixture content and never logs in to ChatGPT. The 10,560,000-byte `retainedPayloadBytes` field is a **logical UTF-16 payload-size estimate**, *not measured physical resident memory* and potentially overestimates actual allocations due to JavaScript string sharing.
- A single layout flush yielded approximately 4.0ms (full), 0.0ms (css), 3.0ms (offscreen), 0.0ms (pruned), 0.0ms (owned). Single-run timings are not stable benchmarks and do not establish production performance.
- All modes preserved the fixture's 400 final messages and one approval button. This does **not** establish compatibility with real ChatGPT approvals or rich results.

## Decision rules

For the **strict Result Only requirement**: NO-GO unless a reliable, supported mechanism is found that prevents the live official app from creating and retaining intermediate model data. The existing public WKWebView APIs and display-only scripts do not meet this gate.

A weaker `visual-only` mode may improve readability and painting, but it must be labeled accordingly. Do not relabel it as memory-safe Result Only or use a synthetic fixture's timings to claim production improvement.

**Final decision: NO-GO for true standalone Result Only using the current official-web WKWebView architecture.** This is a product/architecture gate, not a proof that all small WKWebView display optimizations are worthless or that all observed terminations were caused specifically by MCP content.\n\nDiscontinued-route disposition:
- **Discontinue further standalone Web Optimized Result Only investment.**
- Preserve existing signed IPA/releases and user app data; do not auto-uninstall, erase credentials or overwrite the mirror line.
- Focus long/MCP-heavy conversations on the already-built structured PC Bridge mirror (which *never loads* ChatGPT React on the iPhone).
- Keep the official ChatGPT app as the independent option if the PC is unavailable.
- Do not promote Web Optimized candidate or trigger its signing workflow solely to run this experiment.
