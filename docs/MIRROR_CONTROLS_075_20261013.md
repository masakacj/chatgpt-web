# Native Mirror 0.7.5 feature branch handoff — 2026-10-13

Branch: `feature/mirror-controls-075-20261013` (based on earlier 0.7.4 mirror UX candidate, **not main**).
Requested scope: phone uploads photos/files; PC-native current model / Thinking effort selection; cross-project recent activity sorted by verified PC-side CM evidence; animated header running/complete/error.

Implementation:
- `SharedTabScreen.swift`: native PhotosPicker, fileImporter, model option sheet, recent-active section (includes known project-linked conversations), small status/animation at title.
- `SharedTabModel.swift`: all capabilities require `/v1/health` advertisement, all remote actions use same bound PC tab and document, local drafts unchanged; 10MiB upload cap; error/uncertain result never auto-resends; only real option IDs may be clicked.
- `SharedTabFixtureProtocol.swift` + `SharedTabUITests.swift`: fixture menu options, bound upload result, verified activity ranking and tests.
- `project.yml` version 0.7.5 Build7; `.github/workflows/ios.yml` checks native simulator and unsigned Release device compile.

PC companion source is separately on mcpoffice `D:\workspace\py\chatgpt-pc-bridge`: `docs/MIRROR_CONTROLS_075_20261013.md`. Existing Bridge Chrome extension 0.3.19 updated, but public Node 0.3.10 still running as its guarded service restart detected a live phone session. New capabilities will remain hidden by the iOS app until Node safely restarts.

Evidence at handoff: PC Node120, shared Chromium19, extension coexistence5 PASS. iOS CI: https://github.com/masakacj/chatgpt-web/actions/runs/38420276920 (verify final state). NO signed 0.7.5 yet. Real PC ChatGPT model controls and iPhone files remain subject to physical testing, do not claim fully accepted. Don't overwrite 0.7.3 Build5 stable with a CI failure or unsigned build.
