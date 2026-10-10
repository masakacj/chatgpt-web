# Deployment rules — PC and iOS must not be confused

Read PC_EXTENSION_HANDOFF.md before any PC ChatGPT work.

- PC is **Chrome extension only**, explicitly confirmed by the user. Never request Tampermonkey installation/update or reactivate Desktop Lite/Unified userscripts.
- The live PC source is on mcpoffice: D:\workspace\py\chatgpt-orchestrator\extension, extension ID hkpkilpjbeneliaiafdbkaomedgkkcmi in the Administrator Chrome Default profile. Reuse its existing workspace and workflows.
- D:\workspace\chrome-extension-bridge is an old independent test-profile project for this purpose. Its ChatGPT optimization deployment entries are retired; do not treat it as the user's Chrome. Preserve unrelated business/browser profiles and scripts.
- This repository still contains iOS WKWebView resources. PC defects do not authorize changing or releasing iOS. The user has not supplied a post-fix iPhone acceptance result.
- Old scripts and historical reports are evidence, not current deployment instructions. The Desktop Lite download file is a non-executable retirement notice, guarded by a test.
- Do not delete messages, remove historical MCP DOM, intercept/block iframe loads, clear login/site data, or add idle transcript polling. Do not revive old destructive debug experiments.
- Deployment is complete only after the **same actual extension ID** is reloaded and its real page runtime is observed. A GitHub commit or source file edit is not runtime proof.
- Back up the active extension before changes. Keep exact rollback, test results, unresolved cases and current version in the local PC handoff.
