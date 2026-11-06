// WKWebView port of PC Chrome's bounded long-chat render scheduling.
// Lives in the isolated observation content world; all policy lives in native App settings.
(() => {
  'use strict';
  if (window !== window.top || location.origin !== 'https://chatgpt.com') return;
  const isHistoryEnabled = () => globalThis.__OPTIMIZED_PC_HISTORY_ENABLED__ === true;
  const isMcpEnabled = () => globalThis.__OPTIMIZED_MCP_OUTPUT_RELIEF_ENABLED__ === true;
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

  const MCP_ATTR = 'data-optimized-mcp-output';
  const MCP_STYLE = 'optimized-mcp-output-style';
  const MCP_OUTPUT_SELECTOR = [
    '[data-testid*="tool-result" i]',
    '[data-testid*="tool-output" i]',
    '[data-testid*="tool-response" i]',
    '[data-testid*="mcp-result" i]',
    '[data-testid*="mcp-output" i]',
    '[data-testid*="tool_result" i]',
    '[data-testid*="tool_output" i]',
    '[data-testid*="mcp_result" i]',
    '[data-testid*="mcp_output" i]'
  ].join(',');
  const INTERACTIVE = 'button,a[href],textarea,select,iframe,[role="dialog"],[data-testid*="approval" i],[data-testid*="permission" i],[data-testid*="mcp-app" i]';
  const STATUS_HEADER = 'summary,header,[class*="header" i],[data-testid*="header" i],[data-testid*="status" i],[role="status"],[data-testid*="progress" i]';
  const PRESERVE = INTERACTIVE + ',' + STATUS_HEADER + ',[data-testid*="error" i],[role="alert"]';

  const state = {chat: null, count: 0, tail: null, checked: 0, generation: 0,
    optimized: 0, mcpRelieved: 0, disposed: false};
  const markedMcpNodes = new Set();
  const candidateMcpNodes = new Set();
  const scannedTurns = new Set();
  let lastTailTurn = null;
  let lastTailCount = -1;

  function hasMcpInteractive(node) {
    if (!node) return false;
    if (typeof node.matches === 'function') {
      if (node.matches(PRESERVE)) return true;
      if (node.matches(TURN) || (typeof node.hasAttribute === 'function' ? node.hasAttribute('data-turn-key') : Boolean(node.attrs?.has?.('data-turn-key')))) return true;
      if (node.matches('[data-testid*="reasoning" i],[data-testid*="thought" i]')) return true;
    }
    if (typeof node.closest === 'function') {
      if (node.closest('[data-conversation-role="user"],[data-message-author-role="user"]')) return true;
      if (node.closest(PRESERVE)) return true;
      if (node.closest('[data-testid*="reasoning" i],[data-testid*="thought" i],[class*="group/activity-header"]')) return true;
      if (node.closest('[data-testid*="conversation-error" i],[data-testid*="error-boundary" i]')) return true;
    }
    let cur = node;
    while (cur) {
      const role = typeof cur.getAttribute === 'function' ?
        (cur.getAttribute('data-conversation-role') || cur.getAttribute('data-message-author-role')) :
        (cur.attrs?.get?.('data-conversation-role') || cur.attrs?.get?.('data-message-author-role'));
      if (role === 'user') return true;
      cur = cur.parentElement || cur.parent;
    }
    if (typeof node.querySelector === 'function') {
      if (node.querySelector(PRESERVE)) return true;
    }
    return false;
  }

  function isLargeOutput(node) {
    if (!node) return false;
    const textLen = (node.textContent || '').length;
    if (textLen >= 1024) return true;
    const count = typeof node.getElementsByTagName === 'function' ?
      node.getElementsByTagName('*').length :
      (typeof node.querySelectorAll === 'function' ? node.querySelectorAll('*').length : 0);
    return count > 100;
  }

  function mcpStyle() {
    if (document.getElementById(MCP_STYLE)) return;
    const el = document.createElement('style');
    el.id = MCP_STYLE;
    el.textContent = '[' + MCP_ATTR + '="1"]:not(:is(' + PRESERVE + ')):not(:has(' + PRESERVE + ')){display:none!important;}';
    (document.head || document.documentElement).appendChild(el);
  }

  function clearMcpRelief() {
    for (const el of markedMcpNodes) {
      try { el.removeAttribute?.(MCP_ATTR); } catch (_) {}
    }
    if (typeof document.querySelectorAll === 'function') {
      try {
        for (const el of document.querySelectorAll('[' + MCP_ATTR + ']'))
          el.removeAttribute(MCP_ATTR);
      } catch (_) {}
    }
    markedMcpNodes.clear();
    candidateMcpNodes.clear();
    scannedTurns.clear();
    lastTailTurn = null;
    lastTailCount = -1;
    document.getElementById(MCP_STYLE)?.remove();
    state.mcpRelieved = 0;
  }

  function getTurnDescendantCount(turn) {
    if (!turn) return 0;
    if (typeof turn.getElementsByTagName === 'function') {
      try { return turn.getElementsByTagName('*').length; } catch (_) {}
    }
    let count = 0;
    const stack = [turn];
    while (stack.length) {
      const node = stack.pop();
      const ch = node.children;
      if (ch) {
        const len = ch.length;
        count += len;
        for (let i = 0; i < len; i++) {
          stack.push(ch[i]);
        }
      }
    }
    return count;
  }

  function discoverMcpCandidates(turns, activity) {
    if (!turns || !turns.length) return;
    const len = turns.length;
    const tailIndex = len - 1;
    const tailTurn = turns[tailIndex];
    const isRunning = Boolean(activity?.running || activity?.waiting);

    for (let i = 0; i < len; i++) {
      const turn = turns[i];
      if (!turn || typeof turn.querySelectorAll !== 'function') continue;
      const isTail = (i === tailIndex);
      const isSettled = scannedTurns.has(turn);

      if (isSettled && !isTail) continue;
      if (isTail && isRunning && turn === lastTailTurn && getTurnDescendantCount(turn) === lastTailCount) continue;
      if (isSettled && isTail && !isRunning) continue;

      try {
        const items = turn.querySelectorAll(MCP_OUTPUT_SELECTOR);
        if (items && items.length) {
          for (let j = 0; j < items.length; j++) {
            const item = items[j];
            if (!item) continue;
            candidateMcpNodes.add(item);
            if (!markedMcpNodes.has(item) && !hasMcpInteractive(item) && isLargeOutput(item)) {
              if (typeof item.setAttribute === 'function') {
                item.setAttribute(MCP_ATTR, '1');
                markedMcpNodes.add(item);
              }
            }
          }
        }
      } catch (_) {}

      if (!isTail || !isRunning) {
        scannedTurns.add(turn);
      } else {
        lastTailTurn = turn;
        lastTailCount = getTurnDescendantCount(turn);
      }
    }
  }

  function applyMcpRelief(turns, activity) {
    if (!isMcpEnabled()) {
      // OFF is the default: avoid a full ChatGPT DOM walk on every status update.
      if (markedMcpNodes.size || candidateMcpNodes.size || scannedTurns.size ||
          document.getElementById(MCP_STYLE)) clearMcpRelief();
      return;
    }
    for (const node of markedMcpNodes) {
      if (hasMcpInteractive(node)) {
        try { node.removeAttribute?.(MCP_ATTR); } catch (_) {}
        markedMcpNodes.delete(node);
      }
    }
    for (const node of candidateMcpNodes) {
      if (!node || node.isConnected === false) continue;
      if (markedMcpNodes.has(node)) continue;
      if (hasMcpInteractive(node) || !isLargeOutput(node)) continue;
      if (typeof node.setAttribute === 'function') {
        node.setAttribute(MCP_ATTR, '1');
        markedMcpNodes.add(node);
      }
    }
    discoverMcpCandidates(turns, activity);
    if (markedMcpNodes.size > 0) mcpStyle();
    state.mcpRelieved = markedMcpNodes.size;
  }

  function resetHistory() {
    state.generation++;
    for (const el of document.querySelectorAll('[' + ATTR + ']'))
      el.removeAttribute(ATTR);
    state.count = 0; state.tail = null;
    state.checked = 0; state.optimized = 0;
  }

  function reset() {
    resetHistory();
    clearMcpRelief();
    state.chat = null;
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

  function refresh(id, turns, activity) {
    if (state.disposed) return;
    if (!id) { if (state.chat) reset(); return; }
    if (document.hidden || !turns) return;
    if (state.chat && id !== state.chat) reset();
    state.chat = id;

    // 1. MCP tool output relief: selective display relief during running/idle, independent of 24/12 layout
    applyMcpRelief(turns, activity);

    // 2. PC Chrome long-chat history optimization: gated on running/waiting and 24-turn minimum
    if (!isHistoryEnabled()) return;
    if (activity?.running || activity?.waiting) {
      // CSS :has() restores newly mounted approvals during streaming.
      // Inspect marked history only when an explicit approval is awaited.
      if (activity?.waiting) restoreApprovals();
      state.generation++;
      state.checked = 0;
      return;
    }
    // MCP output relief above remains active; delay only expensive history relayout.
    if (coldStartClock !== null && performance.now() - coldStartClock < COLD_START_GRACE_MS) return;
    const count = turns.length, tail = count ? turns[count - 1] : null, now = Date.now();
    if (id === state.chat && tail === state.tail && count === state.count &&
        now - state.checked < 12000) return;
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
    document.getElementById(MCP_STYLE)?.remove();
    delete globalThis.__CHATGPT_WEB_PC_LONG_CHAT__;
  }

  globalThis.__CHATGPT_WEB_PC_LONG_CHAT__ = {
    refresh, reset, destroy, audit: () => ({
      enabled: isHistoryEnabled(),
      mcpEnabled: isMcpEnabled(),
      mounted: state.count,
      optimized: state.optimized,
      mcpRelieved: markedMcpNodes.size,
      generation: state.generation
    })
  };
})();
