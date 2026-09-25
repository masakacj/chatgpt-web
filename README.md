# ChatGPT Web Unified

One userscript for both desktop Tampermonkey and iOS Safari userscript extensions.

There is only one maintained runtime source:

`safari/chatgpt-safari.user.js`

The path is kept for backward compatibility with existing iOS installations, but the file is now the canonical cross-platform script. Desktop and iOS use the exact same file, version, performance logic and conversation-state logic.

## Canonical install URL

`https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-safari.user.js`

Install that same URL on:

- Desktop: Tampermonkey / Violentmonkey / compatible userscript manager.
- iPhone / iPad: a Safari userscript extension that supports standard userscript metadata.

The script includes `@updateURL` and `@downloadURL` pointing to the same canonical file, so both platforms follow the same update stream.

## Shared performance behavior

The optimization layer is deliberately browser-safe and identical on desktop and iOS:

- always-on `content-visibility: auto` for eligible conversation turns;
- the currently streaming turn is excluded;
- focused / interactive turns are excluded;
- no `innerHTML` replacement or DOM snapshots;
- no fixed-height message freezing;
- no image/video/iframe source unloading;
- no separate native bridge.

This means performance changes are made once and roll out to both platforms.

## Always-on balanced optimization

Optimization starts from the first conversation turn on both desktop and iOS.

- every eligible conversation turn uses `content-visibility: auto`;
- the currently streaming turn stays fully live;
- focused / interactive content stays fully live;
- MCP / DevSpace / tool-call process blocks remain fully visible while running or waiting for approval;
- once the current response finishes, completed tool-process blocks collapse to a one-line summary and their children stop participating in layout/paint;
- disabling optimization restores the official tool-process DOM display immediately.

This is intentionally a middle ground: completed tool output is not deleted from memory, so ChatGPT/React state is not damaged, but the expensive process UI no longer contributes to normal rendering work. Final assistant answers are never compacted by the tool-process rule.

## Shared conversation-state model

Both platforms use the same state machine:

`running → waiting_user → settling → completed_unread → completed_read`

Rules:

- completion settling window: 2.8 seconds;
- completed-unread becomes read after 1.2 seconds of actual visible dwell;
- state persists in `localStorage`;
- cross-tab synchronization uses `BroadcastChannel`;
- the browser `storage` event is the fallback;
- sidebar status dots and the floating control read from this same state store.

The custom status layer does not replace ChatGPT message DOM and is independent of the official unread indicator.

## Controls

The floating control is part of the same script on both platforms.

- **常驻轻量优化** — enable or disable performance hints.
- **重新加载 ChatGPT** — reload the official page.
- **恢复官方页面显示** — remove performance hints immediately.
- **隐藏悬浮按钮** — hide the control.

Console API:

```js
ChatGPTWeb.getState()
ChatGPTWeb.setEnabled(false)
ChatGPTWeb.showControl()
```

For compatibility with existing iOS installs, `ChatGPTSafari` remains an alias of `ChatGPTWeb`.

## iOS hot update

The iOS IPA is only a thin WebKit shell. It does not maintain a second copy of the optimization logic.

Startup order:

1. load the newest valid cached Unified userscript;
2. fall back to the userscript bundled in the IPA;
3. check the canonical GitHub Raw script and `package.json`;
4. validate that metadata/runtime/package versions match;
5. cache and inject the newer script into the current page immediately.

If the network check fails, the cached/bundled script continues to work.

The floating **S** menu shows the active script version, IPA shell version, and update state such as `检查更新中`, `已是最新`, `已热更`, or `离线 · 使用本地版`.

Future userscript-only releases do not require rebuilding or reinstalling the IPA. A new IPA is needed only when the native WebKit shell itself changes.

## Release

Every push to `main` validates the canonical script and packages:

- `ChatGPT-Web-Unified.user.js`
- `ChatGPT-Web-Unified.zip`
- SHA-256 files

The release tag is derived from `package.json`, for example `v0.3.2`.

The earlier WKWebView iOS client and the old standalone desktop optimizer are legacy architectures and should not be maintained separately.
