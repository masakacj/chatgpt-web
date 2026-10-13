# ChatGPT Web Optimized Acceptance Plan

Date: 2026-10-13
Status: planned; no acceptance evidence exists yet

## Gates

### F0 — Mirror baseline frozen

Required evidence:

- signed 0.7.2 Build4 IPA hash/size/signing/profile/entitlements;
- install-center manifest and rollback index;
- current SharedTab policy and UI result bundle;
- mirror Release device compile;
- confirmed source identities `8440857...` and `fac5b787...`.

### F1 — Target isolation

Required evidence:

- both app schemes compile;
- side-by-side installation with distinct icons and bundle IDs;
- target-boundary check passes;
- mirror tests unchanged;
- deleting either app leaves the other app and its data intact.

### F2 — CM contract parity

Run the same versioned JSON corpus through PC Node and Swift.

Required topics:

- validation/privacy;
- state transitions and read state;
- submit/new-turn/late-answer handling;
- duplicate/order/document/sequence/generation conflicts;
- terminal regression;
- cancellation error versus stop;
- migration and stale active state;
- URL and recovery-policy classification.

Pass condition: identical decision and projected state for every case, with fixture and upstream hashes recorded.

### F3 — WK shell

Synthetic and real-device checks:

- independent first login and logout;
- ordinary and project conversation navigation;
- persistent login after relaunch/device restart;
- strict trusted-origin message acceptance;
- popup/external link behavior;
- file upload and download;
- keyboard/safe area;
- app foreground/background;
- observer has no fetch/XHR/localStorage/CSS/DOM mutation path;
- mirror namespaces remain absent.

### F4 — State, recovery, diagnostics and lifecycle

Synthetic WK fixtures:

- complete before answer body and late answer mount;
- running/waiting/approval;
- submit followed by old answer;
- SPA stale turn;
- duplicate, out-of-order and wrong-generation event;
- cancelled failure versus ordinary stop;
- official load-error with Retry present/missing;
- draft/running/waiting/answer blockers;
- WebContent process termination;
- app pause/resume;
- storage corruption and restart.

Mandatory safety assertions:

- zero automatic Retry;
- zero automatic full reload;
- zero request replay;
- zero fetch/XHR wrapping;
- one explicit confirmation causes at most one verified native Retry click;
- process rebuild requires separate confirmation;
- no CM styles, badges, status attributes or hidden native markers;
- no content/credential data in state or diagnostics.

### F5 — Physical iPhone candidate gate

Record device model and iOS version for every result.

Functional matrix:

1. mirror and optimized apps installed side by side;
2. optimized login does not affect mirror data or connection;
3. deleting/clearing optimized does not affect mirror;
4. login, MFA/CAPTCHA, logout and relaunch;
5. normal/project/long conversations;
6. input, scroll, code, table, link and attachment behavior;
7. popup, upload and download;
8. microphone/camera prompt policy;
9. foreground/background/device restart;
10. memory pressure and forced WebContent termination fixture;
11. visible loading-error confirmation flow;
12. offline, 401/403, 429, 404/410, TLS and unknown failure produce no automatic action;
13. 30-minute idle observer behavior;
14. active generation observer behavior;
15. diagnostic export redaction.

Performance A/B:

- cold launch;
- first interactive state;
- long-conversation open/switch;
- input latency;
- scrolling hitch/FPS;
- CPU/energy;
- resident memory and growth over five conversation switches;
- observer-to-native latency;
- reducer latency;
- WebContent termination count.

Provisional internal goals, finalized after baseline capture:

- reducer p95 below 5 ms;
- observer-to-native p95 below 250 ms;
- no sustained memory growth over five conversation switches;
- no WebContent termination during the accepted long-conversation run;
- no final-answer loss or draft loss.

Release evidence:

- exact source SHA;
- CI run and result bundles;
- unsigned archive hash;
- candidate ID;
- signed IPA SHA-256/size;
- bundle/version/build;
- signing identity and decoded profile;
- `codesign --verify --deep --strict`;
- physical install and complete test matrix;
- candidate/stable metadata separation;
- rollback artifact and rehearsal.

Stable promotion is forbidden until all physical-device gates pass.

### F6 — Mirror cleanup gate

Blocked until F5 passes.

Required mirror regression after cleanup:

- SharedTab policy and all current SharedTab UI cases;
- formal Bridge 0.3.10 compatibility;
- existing pairing/Keychain/client ID;
- per-conversation drafts;
- pending/unknown send and interaction receipts;
- library/search/new/project actions;
- foreground/background/offline snapshot;
- accessibility identifiers;
- upgrade from 0.7.2 and rollback to preserved 0.7.2 IPA.

The cleanup candidate may not promote if it modifies mirror data or requires the new Web app.

## CI layout

- `mirror-policy-and-ui`
- `optimized-cm-contract`
- `optimized-unit`
- `optimized-wk-synthetic`
- `mirror-release-compile`
- `optimized-release-compile`
- `target-boundary-check`
- `cm-corpus-hash-check`

Each product has separate result bundles and artifacts named with product, version, build and source SHA. CI verifies source and unsigned builds only; signing and stable promotion remain separate explicit actions.

## Evidence language

Always report separately:

- source implemented;
- unit/simulator passed;
- Release device target compiled;
- candidate signed;
- IPA downloadable;
- installed on physical phone;
- physical functional/performance acceptance passed;
- stable promoted.

Earlier states never imply later states.
