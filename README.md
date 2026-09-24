# ChatGPT Safari Lite

A Safari-first ChatGPT client enhancement. The browser is now the client: no WKWebView shell, no native JavaScript bridge, and no custom conversation renderer.

## Why this version

The previous iOS wrapper could diverge from real Safari in layout, keyboard, scrolling, login, file upload and WebKit lifecycle behavior. This version keeps the official `https://chatgpt.com/` page in Safari and adds only a small userscript.

The userscript deliberately avoids the risky optimizations from the old app:

- no DOM snapshots or `innerHTML` replacement;
- no hiding/fixed-height conversation turns;
- no image/video/iframe source removal;
- no custom tool-call collapsing;
- no native state bridge or native loading/status model.

For long chats it can add one conservative rendering hint to older turns: `content-visibility: auto`. The latest 16 turns stay untouched by default.

## iPhone / iPad installation

Safari itself does not install `.user.js` files directly. Use a Safari userscript extension that supports standard userscript metadata, enable it for `chatgpt.com`, then install:

`safari/chatgpt-safari.user.js`

Raw update URL:

`https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-safari.user.js`

The script includes `@updateURL` and `@downloadURL` metadata pointing to the same file.

## Controls

A small floating **S** button appears at the top-right of ChatGPT. It does not resize the page.

- **长对话轻量优化** — on/off. It activates only when the conversation reaches 32 turns.
- **重新加载 ChatGPT** — reloads the official page.
- **恢复官方页面显示** — disables all performance hints immediately.
- **隐藏悬浮按钮** — hides the control. It can be restored from the console with `ChatGPTSafari.showControl()`.

Useful console checks:

```js
ChatGPTSafari.getState()
ChatGPTSafari.setEnabled(false)
ChatGPTSafari.setKeepRecent(20)
```

Settings are stored only in Safari localStorage for `chatgpt.com`.

## Repository layout

```text
safari/chatgpt-safari.user.js   # the complete Safari userscript
scripts/validate-userscript.mjs # metadata/version safety checks
scripts/package-userscript.mjs  # release packaging
.github/workflows/safari.yml     # syntax check + release artifact
```

## Release

Pushes to `main` run syntax/metadata validation and upload a packaged artifact. A tag such as `v0.2.0` publishes the userscript and ZIP to GitHub Releases.

The earlier native iOS client remains available in Git history; it is no longer the active architecture.
