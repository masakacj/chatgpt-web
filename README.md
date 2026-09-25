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

## Release

Every push to `main` validates the canonical script and packages:

- `ChatGPT-Web-Unified.user.js`
- `ChatGPT-Web-Unified.zip`
- SHA-256 files

The release tag is derived from `package.json`, for example `v0.3.0`.

The earlier WKWebView iOS client and the old standalone desktop optimizer are legacy architectures and should not be maintained separately.
