// WKWebView port of PC Chrome's bounded long-chat render scheduling.
// Lives in the isolated observation content world; all policy lives in native App settings.
(() => {
  'use strict';
  if (window !== window.top || location.origin !== 'https://chatgpt.com') return;
  const enabled = globalThis.__OPTIMIZED_PC_HISTORY_ENABLED__ === true;
  const KEEP = 12;
  const MIN = 24;
  const TURN = '[data-turn-key],[data-testid^="conversation-turn-"]';
  const ATTR = 'data-optimized-pc-history';
  const STYLE = 'optimized-pc-history-style';
  const APPROVAL = '[data-testid*="approval" i],[data-testid*="permission" i],button[aria-label*="Approve" i],button[aria-label*="授权"],iframe';
  const state = {chat: null, count: 0, tail: null, checked: 0, generation: 0,
    optimized: 0, disposed: false};
  function reset() {
    state.generation++;
    for (const el of document.querySelectorAll('[' + ATTR + ']'))
      el.removeAttribute(ATTR);
    state.chat = null; state.count = 0; state.tail = null;
    state.checked = 0; state.optimized = 0;
  }
  function unmark(node) {
    if (!node) return;
    const has = typeof node.hasAttribute === 'function' ? node.hasAttribute(ATTR) :
      (typeof node.getAttribute === 'function' ? node.getAttribute(ATTR) !== null : Boolean(node.attrs?.has?.(ATTR)));
    if (has !== false) node.removeAttribute?.(ATTR);
  }
  function hasApproval(node) {
    if (!node) return false;
    if (typeof node.matches === 'function' && node.matches('iframe')) return true;
    return Boolean(node.querySelector?.(APPROVAL));
  }
  function restoreApprovals() {
    // Already optimized blocks only; avoid scanning every turn on every CM refresh.
    for (const node of document.querySelectorAll('[' + ATTR + ']')) {
      if (hasApproval(node)) unmark(node);
    }
  }
  function style() {
    if (!enabled || document.getElementById(STYLE)) return;
    const el = document.createElement('style');
    el.id = STYLE;
    // Native WebKit implements this CSS; it does not delete React nodes or stop MCP requests.
    // CSS :has() unfreezes newly inserted approval/iframe content immediately,
    // even between the slower native observer scans (supported by iOS 17+).
    el.textContent = '[' + ATTR + '="1"]:not(:has(' + APPROVAL + ')){content-visibility:auto!important;contain-intrinsic-size:auto 650px;}';
    (document.head || document.documentElement).appendChild(el);
  }
  function refresh(id, turns, activity) {
    if (state.disposed) return;
    if (!id) { if (state.chat) reset(); return; }
    if (!enabled || document.hidden || !turns) return;
    if (state.chat && id !== state.chat) reset();
    if (activity?.running || activity?.waiting) {
      restoreApprovals();
      state.generation++;
      state.checked = 0;
      return;
    }
    const count = turns.length, tail = count ? turns[count - 1] : null, now = Date.now();
    if (id === state.chat && tail === state.tail && count === state.count &&
        now - state.checked < 12000) return;
    restoreApprovals();
    if (count < MIN && state.count >= MIN) reset();
    state.chat = id; state.count = count; state.tail = tail; state.checked = now;
    if (count < MIN) return;
    const mounted = Array.from(turns).filter(el => !el.parentElement?.closest?.(TURN));
    if (mounted.length < MIN) return;
    const generation = ++state.generation, end = mounted.length - KEEP;
    // The latest 12 turns, including streaming/interactive controls, remain native.
    for (let i = end; i < mounted.length; i++) unmark(mounted[i]);
    style();
    let index = 0;
    const step = () => {
      if (state.disposed || generation !== state.generation ||
          state.chat !== id || document.hidden) return;
      let budget = 0;
      while (index < end && budget++ < 16) {
        const turn = mounted[index++];
        if (!turn?.isConnected || typeof turn.setAttribute !== 'function') continue;
        // Never alter blocks carrying an explicit outstanding user approval or iframe.
        if (hasApproval(turn)) {
          unmark(turn);
          continue;
        }
        const currentAttr = typeof turn.getAttribute === 'function' ? turn.getAttribute(ATTR) : turn.attrs?.get?.(ATTR);
        if (currentAttr === '1') continue;
        turn.setAttribute(ATTR, '1');
        state.optimized++;
      }
      if (index < end) {
        if (typeof requestIdleCallback === 'function') requestIdleCallback(step, {timeout: 220});
        else setTimeout(step, 24);
      }
    };
    if (typeof requestIdleCallback === 'function') requestIdleCallback(step, {timeout: 220});
    else setTimeout(step, 24);
  }
  function destroy() {
    state.disposed = true;
    reset();
    document.getElementById(STYLE)?.remove();
    delete globalThis.__CHATGPT_WEB_PC_LONG_CHAT__;
  }
  globalThis.__CHATGPT_WEB_PC_LONG_CHAT__ = {
    refresh, reset, destroy, audit: () => ({
      enabled, mounted: state.count, optimized: state.optimized,
      generation: state.generation
    })
  };
})();
