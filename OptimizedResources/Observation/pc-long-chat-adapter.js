// WKWebView port of PC Chrome's bounded long-chat render scheduling.
// Lives in the isolated observation content world; all policy lives in native App settings.
(() => {
  'use strict';
  if (window !== window.top || location.origin !== 'https://chatgpt.com') return;
  const isHistoryEnabled = () => globalThis.__OPTIMIZED_PC_HISTORY_ENABLED__ === true;
  const KEEP = 12;
  const MIN = 24;
  // Give ChatGPT's sidebar priority over bounded historical layout work on cold start.
  // CM observations and interactive approvals remain immediate.
  const COLD_START_GRACE_MS = 5000;
  const coldStartClock = typeof performance !== 'undefined' && typeof performance.now === 'function'
    ? performance.now() : null;
  const TURN = '[data-turn-key],[data-testid^="conversation-turn-"]';
  const ATTR = 'data-optimized-pc-history';
  const STYLE = 'optimized-pc-history-style';
  const APPROVAL = '[data-testid*="approval" i],[data-testid*="permission" i],button[aria-label*="Approve" i],button[aria-label*="授权"],iframe';

  const NATIVE_VIRTUALIZER = '[data-virtualized-turn-content],[class*="virtualized-turn" i]';
  const state = {chat: null, count: 0, tail: null, checked: 0, generation: 0,
    optimized: 0, nativeVirtualized: false, disposed: false};

  // The official renderer wins even when modern and legacy markers coexist.
  function nativeRenderer(turns, root) {
    for (let i = 0; i < turns.length; i++) {
      if (turns[i]?.hasAttribute?.('data-turn-key')) return true;
    }
    return Boolean(root?.querySelector?.('[data-turn-key],' + NATIVE_VIRTUALIZER));
  }

  function resetHistory() {
    state.generation++;
    if (state.optimized) {
      for (const el of document.querySelectorAll('[' + ATTR + ']')) el.removeAttribute(ATTR);
    }
    document.getElementById(STYLE)?.remove();
    state.count = 0; state.tail = null;
    state.checked = 0; state.optimized = 0;
  }

  function reset() {
    resetHistory();
    state.chat = null;
    state.nativeVirtualized = false;
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
    if (!isHistoryEnabled() || document.getElementById(STYLE)) return;
    const el = document.createElement('style');
    el.id = STYLE;
    // Native WebKit implements this CSS; it does not delete React nodes or stop MCP requests.
    // CSS :has() unfreezes newly inserted approval/iframe content immediately,
    // even between the slower native observer scans (supported by iOS 17+).
    el.textContent = '[' + ATTR + '="1"]:not(:has(' + APPROVAL + ')){content-visibility:auto!important;contain-intrinsic-size:auto 650px;}';
    (document.head || document.documentElement).appendChild(el);
  }

  function refresh(id, turns, activity, root) {
    if (state.disposed) return;
    if (!id) { if (state.chat) reset(); return; }
    if (document.hidden || !turns) return;
    if (state.chat && id !== state.chat) reset();
    state.chat = id;

    if (!isHistoryEnabled()) {
      if (state.optimized || document.getElementById(STYLE)) resetHistory();
      return;
    }
    const count = turns.length, tail = count ? turns[count - 1] : null, now = Date.now();
    if (nativeRenderer(turns, root)) {
      // Cancel pending legacy work even if no idle batch has marked a turn yet.
      if (!state.nativeVirtualized || state.optimized) resetHistory();
      state.nativeVirtualized = true;
      state.count = count; state.tail = tail; state.checked = now;
      return;
    }
    if (state.nativeVirtualized) {
      resetHistory();
      state.nativeVirtualized = false;
    }
    if (activity?.running || activity?.waiting) {
      if (activity?.waiting) restoreApprovals();
      state.generation++;
      state.checked = 0;
      return;
    }
    if (coldStartClock !== null && performance.now() - coldStartClock < COLD_START_GRACE_MS) return;
    if (tail === state.tail && count === state.count && now - state.checked < 12000) return;
    restoreApprovals();
    if (count < MIN && state.count >= MIN) resetHistory();
    state.chat = id; state.count = count; state.tail = tail; state.checked = now;
    if (count < MIN) return;
    const mounted = Array.from(turns).filter(el => !el.parentElement?.closest?.(TURN));
    if (mounted.length < MIN) return;
    const generation = ++state.generation, end = mounted.length - KEEP;
    // The latest 12 turns, including streaming/interactive controls, remain native.
    for (let i = end; i < mounted.length; i++) unmark(mounted[i]);
    style();
    let index = 0;
    const schedule = () => {
      // iOS Safari often lacks requestIdleCallback. A forced 24ms/16-turn
      // timeout used to compete with React sidebar layout on the main thread.
      if (typeof requestIdleCallback === 'function') requestIdleCallback(step);
      else setTimeout(step, 160);
    };
    const step = deadline => {
      if (state.disposed || !isHistoryEnabled() || generation !== state.generation ||
          state.chat !== id || document.hidden) return;
      // A native marker can arrive between the refresh and an idle batch.
      if (root?.isConnected === false || nativeRenderer(turns, root)) {
        resetHistory();
        state.nativeVirtualized = Boolean(root?.isConnected !== false);
        return;
      }
      if (deadline?.timeRemaining && deadline.timeRemaining() < 4) {
        schedule();
        return;
      }
      let budget = 0;
      while (index < end && budget++ < 4) {
        if (deadline?.timeRemaining && deadline.timeRemaining() < 2) break;
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
      if (index < end) schedule();
    };
    schedule();
  }

  function destroy() {
    state.disposed = true;
    reset();
    document.getElementById(STYLE)?.remove();
    delete globalThis.__CHATGPT_WEB_PC_LONG_CHAT__;
  }

  globalThis.__CHATGPT_WEB_PC_LONG_CHAT__ = {
    refresh, reset, destroy, audit: () => ({
      enabled: isHistoryEnabled(),
      mounted: state.count,
      optimized: state.optimized,
      nativeVirtualized: state.nativeVirtualized,
      generation: state.generation
    })
  };
})();
