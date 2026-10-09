// ==UserScript==
// @name         ChatGPT Desktop Lite - Conversation Status
// @namespace    https://github.com/masakacj/chatgpt-web
// @version      0.2.0
// @description  Respect native long-chat loading; track running/completed chat state conservatively.
// @match        https://chatgpt.com/*
// @run-at       document-idle
// @noframes
// @grant        none
// @updateURL    https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-desktop-lite.user.js
// @downloadURL  https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-desktop-lite.user.js
// ==/UserScript==
(() => {
  'use strict';
  // Minimal desktop layer: never rewrites messages, tools, network or scroll.
  const VERSION = '0.2.0';
  const KEY = 'cgpt-lite-states-v1';
  const CHANNEL = 'cgpt-lite-sync-v1';
  const ATTR = 'data-cgpt-lite-state';
  const STALE_MS = 90000;
  const SETTLE_MS = 3200;
  const POLL_ACTIVE_MS = 1300;
  const STOP = [
    'button[data-testid="stop-button"]',
    'button[aria-label*="Stop generating" i]',
    'button[aria-label*="Stop responding" i]',
    'button[aria-label*="停止生成"]',
    'button[aria-label*="停止回答"]',
    'button[aria-label*="停止响应"]'
  ].join(',');
  const SEND = [
    'button[data-testid="send-button"]',
    'button[aria-label="Send prompt"]',
    'button[aria-label="Send message"]',
    'button[aria-label="发送消息"]',
    'button[aria-label="发送"]'
  ].join(',');
  const now = () => Date.now();
  const chatId = (href = location.href) => {
    try {
      const u = new URL(href, location.origin);
      return u.origin === location.origin
        ? u.pathname.match(/(?:^|\/)c\/([A-Za-z0-9_-]{12,80})(?:\/|$)/)?.[1] || null
        : null;
    } catch (_) { return null; }
  };
  const state = new Map();
  const sidebarLinks = new Map();
  let currentId = null;
  let run = null;
  let runTick = 0;
  let heartbeat = 0;
  let pendingNewChatAt = 0;
  let sidebarObserver = null;
  let sidebarRoot = null;
  let sidebarTimer = 0;
  const expiryTimers = new Map();
  let routeTimers = [];
  let channel = null;
  let destroyed = false;

  function load() {
    try {
      const items = JSON.parse(localStorage.getItem(KEY) || '{}');
      for (const [id, rec] of Object.entries(items)) {
        if (!/^[A-Za-z0-9_-]{12,80}$/.test(id) ||
            !rec || now() - rec.at > 3 * 86400000) continue;
        state.set(id, rec);
      }
    } catch (_) {}
  }
  function persist() {
    try {
      const recent = [...state].sort((a,b) => b[1].at - a[1].at).slice(0,120);
      localStorage.setItem(KEY, JSON.stringify(Object.fromEntries(recent)));
    } catch (_) {}
  }
  function effectiveStatus(rec) {
    if (!rec) return null;
    if (rec.status === 'running' && now() - (rec.heartbeat || rec.at) > STALE_MS) {
      return 'uncertain';
    }
    return rec.status;
  }
  function paint(id) {
    const links = sidebarLinks.get(id);
    if (!links) return;
    const status = effectiveStatus(state.get(id));
    for (const anchor of [...links]) {
      if (!anchor.isConnected) { links.delete(anchor); continue; }
      if (status && status !== 'unknown') anchor.setAttribute(ATTR, status);
      else anchor.removeAttribute(ATTR);
    }
    if (!links.size) sidebarLinks.delete(id);
  }
  function merge(id, rec, broadcast = false) {
    if (!id || !rec || typeof rec.at !== 'number') return;
    const old = state.get(id);
    if (old && old.at > rec.at) return;
    state.set(id, rec);
    const previousTimer = expiryTimers.get(id);
    if (previousTimer) clearTimeout(previousTimer);
    expiryTimers.delete(id);
    if (rec.status === 'running') {
      const remaining = Math.max(0, STALE_MS - (now() - (rec.heartbeat || rec.at))) + 25;
      expiryTimers.set(id, setTimeout(() => {
        expiryTimers.delete(id);
        paint(id);
      }, remaining));
    }
    paint(id);
    persist();
    if (broadcast) {
      try { channel?.postMessage({ id, rec }); } catch (_) {}
    }
  }
  function mark(id, status) {
    if (!id) return;
    const old = state.get(id);
    if (old?.status === status && status !== 'running') return;
    if (old?.status === status && status === 'running' &&
        now() - (old.heartbeat || old.at) < 18000) return;
    const at = now();
    merge(id, {
      status, at,
      heartbeat: status === 'running' ? at : undefined,
    }, true);
  }
  function visible(node) {
    if (!node || node.closest('[hidden],[aria-hidden="true"]')) return false;
    const style = getComputedStyle(node);
    return style.display !== 'none' && style.visibility !== 'hidden' &&
      node.getClientRects().length > 0;
  }
  function generating() {
    const main = document.querySelector('main');
    return Boolean(main && [...main.querySelectorAll(STOP)].some(visible));
  }
  function waitingForUser() {
    const main = document.querySelector('main');
    if (!main) return false;
    // Do not scan historical turns: only a small number of explicit approval controls.
    const actionable = main.querySelectorAll(
      '[data-testid*="approval" i] button,' +
      '[data-testid*="permission" i] button,' +
      'button[aria-label*="Approve" i],' +
      'button[aria-label*="批准"],' +
      'button[aria-label*="授权"]'
    );
    for (const button of actionable) {
      if (!visible(button)) continue;
      const rect = button.getBoundingClientRect();
      if (rect.bottom >= 0 && rect.top <= window.innerHeight) return true;
    }
    return false;
  }
  function hasAssistantContent() {
    const main = document.querySelector('main');
    return Boolean(main?.querySelector(
      '[data-message-author-role="assistant"],' +
      '[data-testid^="conversation-turn-"] [data-message-author-role="assistant"]'
    ));
  }
  function clearActive() {
    clearInterval(runTick); runTick = 0;
    clearInterval(heartbeat); heartbeat = 0;
    run = null;
  }
  function watchActive() {
    if (!runTick) runTick = setInterval(checkActive, POLL_ACTIVE_MS);
    if (!heartbeat) heartbeat = setInterval(() => {
      if (run && run.id === currentId && state.get(run.id)?.status === 'running') {
        mark(run.id, 'running');
      }
    }, 20000);
  }
  function begin(id = currentId) {
    if (!id) { pendingNewChatAt = now(); return; }
    if (run?.id === id && state.get(id)?.status === 'running') return;
    clearActive();
    run = { id, since: now(), stopSeen: generating(), clearSince: 0, canceled: false };
    mark(id, 'running');
    watchActive();
  }
  function checkActive() {
    if (!run || run.id !== currentId) { clearActive(); return; }
    const id = run.id;
    if (generating()) {
      run.stopSeen = true;
      run.clearSince = 0;
      mark(id, 'running');
      return;
    }
    if (waitingForUser()) {
      mark(id, 'waiting');
      clearActive();
      return;
    }
    if (!run.clearSince) run.clearSince = now();
    const noStopFor = now() - run.clearSince;
    if (run.canceled && noStopFor > 1000) {
      mark(id, 'stopped');
      clearActive();
    } else if (run.stopSeen && noStopFor >= SETTLE_MS) {
      mark(id, hasAssistantContent() ? 'completed' : 'uncertain');
      clearActive();
    } else if (!run.stopSeen && now() - run.since > 30000) {
      // Long MCP operations can have no visible stop control. Do not guess.
      mark(id, 'uncertain');
      clearActive();
    }
  }
  function visit() {
    const next = chatId();
    if (next === currentId && !pendingNewChatAt) return;
    clearActive();
    currentId = next;
    if (next && pendingNewChatAt && now() - pendingNewChatAt < 20000) {
      pendingNewChatAt = 0;
      begin(next);
    }
    if (!next) return;
    let checks = 0;
    const check = () => {
      if (destroyed || currentId !== next) return;
      if (generating()) { begin(next); return; }
      if (waitingForUser()) { mark(next, 'waiting'); return; }
      if (++checks === 4 && !state.get(next) && hasAssistantContent()) {
        mark(next, 'completed');
      }
    };
    for (const delay of [150, 700, 1800, 4000]) {
      routeTimers.push(setTimeout(check, delay));
    }
  }
  function attachSidebar() {
    const candidates = document.querySelectorAll('nav,aside');
    const root = [...candidates].find(node =>
      node.querySelector('a[href*="/c/"],[data-conversation-id]')
    ) || [...candidates].find(node => node.querySelector('a[href*="/g/g-p-"]')) ||
      candidates[0];
    if (!root || root === sidebarRoot) return;
    sidebarObserver?.disconnect();
    sidebarRoot = root;
    sidebarLinks.clear();
    const reconcile = () => {
      if (destroyed || !sidebarRoot?.isConnected) return;
      sidebarLinks.clear();
      for (const link of sidebarRoot.querySelectorAll(
        'a[href*="/c/"],[data-conversation-id]'
      )) {
        const id = link.getAttribute('data-conversation-id') ||
          chatId(link.getAttribute('href') || '');
        if (!id) continue;
        let group = sidebarLinks.get(id);
        if (!group) { group = new Set(); sidebarLinks.set(id, group); }
        group.add(link);
        paint(id);
      }
    };
    sidebarObserver = new MutationObserver(mutations => {
      if (!mutations.some(m => {
        if (m.type === 'attributes') return true;
        return [...m.addedNodes, ...m.removedNodes].some(n =>
          n.nodeType === 1 && (
            n.matches?.('a[href*="/c/"],[data-conversation-id]') ||
            n.querySelector?.('a[href*="/c/"],[data-conversation-id]')
          )
        );
      })) return;
      clearTimeout(sidebarTimer);
      sidebarTimer = setTimeout(reconcile, 120);
    });
    sidebarObserver.observe(root, {
      childList: true, subtree: true,
      attributes: true, attributeFilter: ['href','data-conversation-id']
    });
    reconcile();
  }
  function onSubmit(event) {
    const form = event.target;
    if (form instanceof HTMLFormElement &&
        form.querySelector('textarea[name="prompt"],[contenteditable="true"]')) {
      begin();
    }
  }
  function onClick(event) {
    const button = event.target.closest?.('button');
    if (button?.matches(SEND) && !button.disabled) begin();
    else if (run && button?.matches(STOP)) run.canceled = true;
    const link = event.target.closest?.('a[href*="/c/"]');
    if (link) setTimeout(onRoute, 0);
  }
  function onRoute() {
    for (const timer of routeTimers) clearTimeout(timer);
    routeTimers = [];
    visit();
    attachSidebar();
  }
  function onVisibility() {
    if (!document.hidden && run) checkActive();
  }
  function onStorage(event) {
    if (event.key !== KEY || !event.newValue) return;
    try {
      for (const [id, rec] of Object.entries(JSON.parse(event.newValue))) {
        if ((state.get(id)?.at || 0) < rec.at) {
          state.set(id, rec); paint(id);
        }
      }
    } catch (_) {}
  }
  function installStyle() {
    if (document.getElementById('cgpt-lite-style')) return;
    const style = document.createElement('style');
    style.id = 'cgpt-lite-style';
    style.textContent = [
      'nav a[' + ATTR + '],aside a[' + ATTR + ']{position:relative;}',
      'nav a[' + ATTR + ']::after,aside a[' + ATTR + ']::after{',
      'content:"";font:10px/1.4 system-ui,-apple-system,sans-serif;',
      'color:var(--cgpt-lite-color,#888);margin-left:6px;',
      'padding:1px 5px;border-radius:4px;white-space:nowrap;',
      'background:color-mix(in srgb,currentColor 8%,transparent);',
      'pointer-events:none;vertical-align:middle;display:inline-block;}',
      'a[' + ATTR + '="running"]{--cgpt-lite-color:#16a34a;}',
      'a[' + ATTR + '="running"]::after{content:"进行中";}',
      'a[' + ATTR + '="completed"]{--cgpt-lite-color:#6b7280;}',
      'a[' + ATTR + '="completed"]::after{content:"已完成";}',
      'a[' + ATTR + '="waiting"]{--cgpt-lite-color:#d97706;}',
      'a[' + ATTR + '="waiting"]::after{content:"等待操作";}',
      'a[' + ATTR + '="uncertain"]{--cgpt-lite-color:#9ca3af;}',
      'a[' + ATTR + '="uncertain"]::after{content:"待确认";}',
      'a[' + ATTR + '="stopped"]{--cgpt-lite-color:#9ca3af;}',
      'a[' + ATTR + '="stopped"]::after{content:"已停止";}'
    ].join('\n');
    (document.head || document.documentElement).appendChild(style);
  }
  function destroy() {
    destroyed = true;
    clearActive();
    sidebarObserver?.disconnect();
    clearTimeout(sidebarTimer);
    expiryTimers.forEach(clearTimeout);
    expiryTimers.clear();
    routeTimers.forEach(clearTimeout);
    document.removeEventListener('submit', onSubmit, true);
    document.removeEventListener('click', onClick, true);
    window.removeEventListener('popstate', onRoute);
    window.removeEventListener('hashchange', onRoute);
    window.navigation?.removeEventListener('navigatesuccess', onRoute);
    window.removeEventListener('storage', onStorage);
    document.removeEventListener('visibilitychange', onVisibility);
    try { channel?.close(); } catch (_) {}
    document.querySelectorAll('[' + ATTR + ']').forEach(a => a.removeAttribute(ATTR));
    document.getElementById('cgpt-lite-style')?.remove();
    document.documentElement.removeAttribute('data-cgpt-lite-version');
  }
  if (!location.hostname.endsWith('chatgpt.com')) return;
  if (document.documentElement.dataset.cgptLiteVersion === VERSION) return;
  window.__CGPT_LITE_INSTANCE__?.destroy?.();
  load();
  installStyle();
  document.documentElement.dataset.cgptLiteVersion = VERSION;
  document.addEventListener('submit', onSubmit, true);
  document.addEventListener('click', onClick, true);
  window.addEventListener('popstate', onRoute);
  window.addEventListener('hashchange', onRoute);
  window.navigation?.addEventListener('navigatesuccess', onRoute);
  window.addEventListener('storage', onStorage);
  document.addEventListener('visibilitychange', onVisibility);
  try {
    channel = new BroadcastChannel(CHANNEL);
    channel.addEventListener('message', event => {
      if (event.data?.id && event.data?.rec) merge(event.data.id, event.data.rec);
    });
  } catch (_) {}
  attachSidebar();
  visit();
  // Sidebar may mount after hydration. These are finite retries, not a poller.
  setTimeout(attachSidebar, 500);
  setTimeout(attachSidebar, 1800);
  // Lightweight diagnostic surface; no custom panel or official UI replacement.
  window.__CGPT_LITE_INSTANCE__ = {
    destroy,
    diagnostics: () => ({
      version: VERSION, currentId, active: Boolean(run),
      tracked: state.size, sidebarItems: sidebarLinks.size,
      current: state.get(currentId) || null,
    })
  };
})();
