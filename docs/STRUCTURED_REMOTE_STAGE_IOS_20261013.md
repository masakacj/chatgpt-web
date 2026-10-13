# ChatGPT Web iOS — PC Bridge isolated HTTPS test channel (2026-10-13)

The app is a **native structured remote desktop** for an explicitly selected PC Chrome ChatGPT tab. Do not add an independent history loader, a ChatGPT API client, a second reader tab, PC status markers or a video-stream UI.

### Separate test environment
- Independent PC Bridge extension/service version **0.3.10**, loopback **127.0.0.1:13213** on mcpoffice; original Orchestrator3210 and formal mobile3211 remain unchanged.
- Verified public test origin: **https://chatgpt-bridge-test.78175132.xyz**. Cloudflare named tunnel only forwards `/v1/` to this loopback service. Real TLS + 401 without key + 403 with browser Origin + 404 on local management endpoints + 200 with local stage pairing, 20-second long poll 200.
- Pairing page **only on the PC**: http://127.0.0.1:13213/local/pair. User explicitly reveals and copies the distinct stage pairing key, which must never be embedded in app, UI fixtures, logs, GitHub or DNS.
- On the new iPhone candidate, open **连接设置 → 使用新版 PC Bridge 测试通道**, enter the stage pairing key, choose **读取 PC 标签页** and bind the intended existing tab. The switch does not automatically send a message and clears the old production key field. Phone-local drafts are stored separately.
- Older existing 0.7.1 Build3 candidate can also connect by manually setting the HTTPS test URL and stage key in settings, but does not include the one-tap stage button.

### Version/release policy
A signed candidate is published on a distinct install page and is **not** automatically promoted to stable. Existing stable0.6.0 Build221 remains available. Source and native UI tests must pass on macOS for an exact App SHA before the signer workflow can produce another candidate IPA. The signer candidate workflow is allowlisted to this exact GitHub repository, branch and workflow path. Never pass a production pairing key to stage.

Physical iPhone A01–A18, remote Send exactly once, background/foreground and Wi-Fi/cellular changes remain user-device acceptance. An isolated PC fixture, online HTTPS read-only snapshot, iOS simulator and an IPA ZIP signature check do not establish these outcomes. Do not switch formal3211 or stable install-channel latest just to make the candidate appear production-ready.

PC authoritative operational handoff: `D:\workspace\py\chatgpt-pc-bridge\docs\REMOTE_DESKTOP_040_STAGE_AND_IPA_20261013.md`.
