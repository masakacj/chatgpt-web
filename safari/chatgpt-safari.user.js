// ==UserScript==
// @name         ChatGPT Web Unified
// @namespace    https://github.com/masakacj/chatgpt-web
// @version      0.3.1
// @description  One ChatGPT userscript for desktop Tampermonkey and iOS Safari: shared performance optimization and conversation state management.
// @author       masakacj
// @match        https://chatgpt.com/*
// @run-at       document-start
// @grant        none
// @updateURL    https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-safari.user.js
// @downloadURL  https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-safari.user.js
// ==/UserScript==

(() => {
  'use strict';

  const VERSION = '0.3.1';
  const GLOBAL_KEY = 'ChatGPTWeb';
  const LEGACY_GLOBAL_KEY = 'ChatGPTSafari';
  const STYLE_ID = 'cgpt-safari-lite-style';
  const HOST_ID = 'cgpt-safari-lite-host';
  const SETTINGS_KEY = 'cgpt-safari-lite-settings-v1';
  const CONTROL_MIGRATION_KEY = 'cgpt-unified-control-visible-v031';
  const CONVERSATION_STATE_KEY = 'cgpt-safari-conversation-state-v1';
  const STATE_CHANNEL = 'cgpt-safari-conversation-state';
  const SETTLE_MS = 2800;
  const READ_DWELL_MS = 1200;
  const STATE_TTL_MS = 14 * 24 * 60 * 60 * 1000;

  try {
    window[GLOBAL_KEY]?.destroy?.();
    window[LEGACY_GLOBAL_KEY]?.destroy?.();
  } catch (_) {}

  const defaults = {
    enabled: true,
    showControl: true,
  };

  const state = {
    settings: loadSettings(),
    destroyed: false,
    observer: null,
    refreshTimer: 0,
    statusTimer: 0,
    optimizedTurns: new Set(),
    lastRoute: location.pathname + location.search,
    activeConversationId: null,
    activeRouteSince: Date.now(),
    settlingSince: 0,
    conversationStates: loadConversationStates(),
    nativeStatus: { ...(window.__CHATGPT_NATIVE__ || {}) },
    channel: null,
    ui: null,
  };

  function clamp(value, min, max) {
    const n = Number(value);
    return Math.min(max, Math.max(min, Number.isFinite(n) ? n : min));
  }

  function loadSettings() {
    try {
      const stored = JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}');
      const shouldRestoreControl = localStorage.getItem(CONTROL_MIGRATION_KEY) !== '1';
      if (shouldRestoreControl) {
        localStorage.setItem(CONTROL_MIGRATION_KEY, '1');
      }
      return {
        enabled: stored.enabled !== false,
        showControl: shouldRestoreControl ? true : stored.showControl !== false,
      };
    } catch (_) {
      return { ...defaults };
    }
  }

  function saveSettings() {
    try {
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(state.settings));
    } catch (_) {}
  }

  function loadConversationStates() {
    try {
      const raw = JSON.parse(localStorage.getItem(CONVERSATION_STATE_KEY) || '{}');
      const now = Date.now();
      const result = {};

      for (const [id, record] of Object.entries(raw)) {
        if (!record || typeof record !== 'object') continue;
        if (now - Number(record.updatedAt || 0) > STATE_TTL_MS) continue;
        result[id] = record;
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  function persistConversationStates() {
    try {
      const entries = Object.entries(state.conversationStates)
        .sort((a, b) => Number(b[1]?.updatedAt || 0) - Number(a[1]?.updatedAt || 0))
        .slice(0, 300);
      state.conversationStates = Object.fromEntries(entries);
      localStorage.setItem(CONVERSATION_STATE_KEY, JSON.stringify(state.conversationStates));
    } catch (_) {}
  }

  function conversationIdFromPath(pathname) {
    const parts = String(pathname || '').split('/').filter(Boolean);
    for (let i = parts.length - 2; i >= 0; i -= 1) {
      if (parts[i] === 'c' && parts[i + 1]) return parts[i + 1];
    }
    return null;
  }

  function conversationIdFromHref(href) {
    try {
      const url = new URL(href, location.origin);
      return conversationIdFromPath(url.pathname);
    } catch (_) {
      return null;
    }
  }

  function currentConversationId() {
    return conversationIdFromPath(location.pathname);
  }

  function statusLabel(status) {
    switch (status) {
      case 'running': return '运行中';
      case 'waiting_user': return '等待操作';
      case 'settling': return '收尾确认';
      case 'completed_unread': return '已完成 · 未读';
      case 'completed_read': return '已完成';
      default: return '就绪';
    }
  }

  function setConversationState(id, status, extra = {}) {
    if (!id) return;

    const previous = state.conversationStates[id] || {};
    const now = Date.now();
    const next = {
      ...previous,
      ...extra,
      status,
      updatedAt: now,
    };

    if (status === 'completed_unread' && !next.completedAt) {
      next.completedAt = now;
    }
    if (status === 'completed_read') {
      next.readAt = now;
    }

    const unchanged =
      previous.status === next.status &&
      Number(previous.settlingSince || 0) === Number(next.settlingSince || 0) &&
      Number(previous.completedAt || 0) === Number(next.completedAt || 0);

    if (unchanged) return;

    state.conversationStates[id] = next;
    persistConversationStates();
    renderConversationStates();

    try {
      state.channel?.postMessage({ type: 'conversation-state', id, record: next });
    } catch (_) {}
  }

  function mergeConversationState(id, record) {
    if (!id || !record || typeof record !== 'object') return;
    const current = state.conversationStates[id];
    if (current && Number(current.updatedAt || 0) >= Number(record.updatedAt || 0)) return;

    state.conversationStates[id] = record;
    persistConversationStates();
    renderConversationStates();
    updateUI(turnCandidates().length);
  }

  function renderConversationStates() {
    const anchors = document.querySelectorAll('a[href*="/c/"]');

    for (const anchor of anchors) {
      if (!(anchor instanceof HTMLAnchorElement)) continue;
      const id = conversationIdFromHref(anchor.href);
      const status = id ? state.conversationStates[id]?.status : null;

      if (status && status !== 'completed_read') {
        anchor.setAttribute('data-cgpt-safari-chat-state', status);
      } else {
        anchor.removeAttribute('data-cgpt-safari-chat-state');
      }
    }
  }

  function lastConversationTurn() {
    const turns = turnCandidates();
    return turns.length ? turns[turns.length - 1] : null;
  }

  function hasWaitingUserSignal() {
    const turn = lastConversationTurn();
    if (!(turn instanceof HTMLElement)) return false;

    const buttons = Array.from(turn.querySelectorAll('button,[role="button"]'));
    return buttons.some((button) => {
      const text = [
        button.textContent || '',
        button.getAttribute?.('aria-label') || '',
        button.getAttribute?.('title') || '',
      ].join(' ').replace(/\s+/g, ' ').trim();

      if (!text) return false;
      if (/(stop|cancel|停止|取消)/i.test(text)) return false;
      return /(allow|approve|confirm|yes,?\s*(?:run|proceed)|run\s+(?:it|command)|continue|允许|批准|确认|继续|运行此|授权)/i.test(text);
    });
  }

  function hasToolOrStreamingSignal() {
    if (isStreaming()) return true;

    const turn = lastConversationTurn();
    if (!(turn instanceof HTMLElement)) return false;

    return Boolean(turn.querySelector(
      '[aria-busy="true"],[role="progressbar"],[data-state="loading"],[data-loading="true"]'
    ));
  }

  function evaluateConversationState() {
    if (state.destroyed) return;

    const now = Date.now();
    const id = currentConversationId();

    if (id !== state.activeConversationId) {
      state.activeConversationId = id;
      state.activeRouteSince = now;
      state.settlingSince = 0;
    }

    if (!id) {
      renderConversationStates();
      updateUI(turnCandidates().length);
      return;
    }

    const waiting = hasWaitingUserSignal();
    const running = hasToolOrStreamingSignal();

    if (waiting) {
      state.settlingSince = 0;
      setConversationState(id, 'waiting_user', {
        settlingSince: 0,
        completedAt: 0,
      });
      updateUI(turnCandidates().length);
      return;
    }

    if (running) {
      state.settlingSince = 0;
      setConversationState(id, 'running', {
        settlingSince: 0,
        completedAt: 0,
      });
      updateUI(turnCandidates().length);
      return;
    }

    const record = state.conversationStates[id];

    if (!record) {
      setConversationState(id, 'completed_read', {
        settlingSince: 0,
        completedAt: now,
      });
      updateUI(turnCandidates().length);
      return;
    }

    if (record.status === 'running' || record.status === 'waiting_user') {
      state.settlingSince = now;
      setConversationState(id, 'settling', {
        settlingSince: now,
        completedAt: 0,
      });
      updateUI(turnCandidates().length);
      return;
    }

    if (record.status === 'settling') {
      const since = Number(record.settlingSince || state.settlingSince || now);
      if (now - since >= SETTLE_MS) {
        setConversationState(id, 'completed_unread', {
          settlingSince: 0,
          completedAt: now,
        });
      }
      updateUI(turnCandidates().length);
      return;
    }

    if (record.status === 'completed_unread' && !document.hidden) {
      const completedAt = Number(record.completedAt || now);
      const readableSince = Math.max(completedAt, state.activeRouteSince);
      if (now - readableSince >= READ_DWELL_MS) {
        setConversationState(id, 'completed_read', {
          settlingSince: 0,
          completedAt,
        });
      }
    }

    updateUI(turnCandidates().length);
  }

  function setupConversationStateSync() {
    try {
      state.channel = new BroadcastChannel(STATE_CHANNEL);
      state.channel.addEventListener('message', (event) => {
        const data = event.data;
        if (data?.type === 'conversation-state') {
          mergeConversationState(data.id, data.record);
        }
      });
    } catch (_) {
      state.channel = null;
    }

    window.addEventListener('storage', onStorageSync);
  }

  function onStorageSync(event) {
    if (event.key !== CONVERSATION_STATE_KEY) return;
    const incoming = loadConversationStates();
    for (const [id, record] of Object.entries(incoming)) {
      mergeConversationState(id, record);
    }
  }

  function installStyle() {
    if (document.getElementById(STYLE_ID)) return;

    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = [
      '[data-cgpt-safari-opt="1"] {',
      '  content-visibility: auto !important;',
      '  contain-intrinsic-size: auto 720px !important;',
      '}',
      'a[data-cgpt-safari-chat-state] { position: relative !important; }',
      'a[data-cgpt-safari-chat-state]::after { content: ""; position: absolute; right: 30px; top: 50%; width: 7px; height: 7px; margin-top: -3.5px; border-radius: 50%; pointer-events: none; }',
      'a[data-cgpt-safari-chat-state="running"]::after { background: #34c759; animation: cgpt-safari-pulse 1.15s ease-in-out infinite; }',
      'a[data-cgpt-safari-chat-state="waiting_user"]::after { background: #ff9f0a; }',
      'a[data-cgpt-safari-chat-state="settling"]::after { background: #8e8e93; animation: cgpt-safari-pulse .9s ease-in-out infinite; }',
      'a[data-cgpt-safari-chat-state="completed_unread"]::after { background: #0a84ff; }',
      '@keyframes cgpt-safari-pulse { 0%,100% { opacity: .45; transform: scale(.82); } 50% { opacity: 1; transform: scale(1.12); } }',
      '@media print {',
      '  #' + HOST_ID + ' { display: none !important; }',
      '}',
    ].join('\n');

    (document.head || document.documentElement).appendChild(style);
  }

  function turnCandidates() {
    const selectors = [
      'article[data-testid^="conversation-turn-"]',
      '[data-testid^="conversation-turn-"]',
      'main article[data-scroll-anchor]',
      'main [data-message-author-role]',
    ];

    for (const selector of selectors) {
      const nodes = Array.from(document.querySelectorAll(selector));
      if (!nodes.length) continue;

      return nodes.filter((node, index) => {
        if (!(node instanceof HTMLElement)) return false;
        return !nodes.some((other, otherIndex) => {
          return otherIndex !== index && other instanceof HTMLElement && other.contains(node);
        });
      });
    }

    return [];
  }

  function restoreOptimizedTurns() {
    for (const turn of Array.from(state.optimizedTurns)) {
      if (turn instanceof HTMLElement) {
        turn.removeAttribute('data-cgpt-safari-opt');
      }
    }
    state.optimizedTurns.clear();
  }

  function applyPerformanceHints() {
    const turns = turnCandidates();

    if (!state.settings.enabled) {
      restoreOptimizedTurns();
      updateUI(turns.length);
      return;
    }

    const streaming = isStreaming();
    const liveTurn = streaming ? turns[turns.length - 1] : null;
    const nextOptimized = new Set();

    for (const turn of turns) {
      if (!(turn instanceof HTMLElement)) continue;

      const interactive = turn.matches(':focus-within');
      const shouldOptimize = !interactive && turn !== liveTurn;

      if (shouldOptimize) {
        turn.setAttribute('data-cgpt-safari-opt', '1');
        nextOptimized.add(turn);
      } else {
        turn.removeAttribute('data-cgpt-safari-opt');
      }
    }

    for (const oldTurn of Array.from(state.optimizedTurns)) {
      if (!nextOptimized.has(oldTurn) && oldTurn instanceof HTMLElement) {
        oldTurn.removeAttribute('data-cgpt-safari-opt');
      }
    }

    state.optimizedTurns = nextOptimized;
    updateUI(turns.length);
  }

  function isStreaming() {
    return Boolean(document.querySelector([
      '[data-testid="stop-button"]',
      'button[data-testid*="stop"]',
      'button[aria-label*="Stop"]',
      'button[aria-label*="停止"]',
      'button[aria-label*="Cancel"]',
      'button[aria-label*="取消"]',
    ].join(',')));
  }

  function scheduleRefresh(delay = 120) {
    if (state.destroyed) return;
    clearTimeout(state.refreshTimer);
    state.refreshTimer = window.setTimeout(() => {
      if (state.destroyed) return;
      const route = location.pathname + location.search;
      if (route !== state.lastRoute) {
        state.lastRoute = route;
        restoreOptimizedTurns();
      }
      window.requestAnimationFrame(applyPerformanceHints);
    }, delay);
  }

  function createControl() {
    if (!state.settings.showControl || state.destroyed) return;
    if (!document.body || document.getElementById(HOST_ID)) return;

    const host = document.createElement('div');
    host.id = HOST_ID;
    host.style.position = 'fixed';
    host.style.top = 'max(8px, env(safe-area-inset-top))';
    host.style.right = '10px';
    host.style.zIndex = '2147483646';
    host.style.pointerEvents = 'auto';

    const shadow = host.attachShadow({ mode: 'open' });
    const wrap = document.createElement('div');

    const style = document.createElement('style');
    style.textContent = [
      ':host { all: initial; }',
      '* { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }',
      '.wrap { position: relative; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }',
      '.fab { width: 36px; height: 36px; border: 0; border-radius: 18px; background: rgba(32,32,32,.78); color: white; box-shadow: 0 3px 14px rgba(0,0,0,.22); display: grid; place-items: center; font-size: 15px; font-weight: 700; backdrop-filter: blur(18px); -webkit-backdrop-filter: blur(18px); }',
      '.fab[data-chat-state]::after { content: ""; width: 7px; height: 7px; border-radius: 50%; position: absolute; right: 1px; top: 1px; box-shadow: 0 0 0 2px rgba(255,255,255,.82); }',
      '.fab[data-chat-state="running"]::after { background: #34c759; animation: pulse 1.15s ease-in-out infinite; }',
      '.fab[data-chat-state="waiting_user"]::after { background: #ff9f0a; }',
      '.fab[data-chat-state="settling"]::after { background: #8e8e93; animation: pulse .9s ease-in-out infinite; }',
      '.fab[data-chat-state="completed_unread"]::after { background: #0a84ff; }',
      '@keyframes pulse { 0%,100% { opacity: .45; transform: scale(.82); } 50% { opacity: 1; transform: scale(1.12); } }',
      '.panel { position: absolute; top: 43px; right: 0; width: 238px; padding: 10px; border-radius: 14px; background: rgba(28,28,30,.94); color: white; box-shadow: 0 12px 34px rgba(0,0,0,.28); backdrop-filter: blur(24px); -webkit-backdrop-filter: blur(24px); display: none; }',
      '.panel.open { display: block; }',
      '.title { font-size: 13px; font-weight: 700; margin: 2px 2px 9px; }',
      '.status { font-size: 11px; opacity: .72; margin: 0 2px 10px; line-height: 1.35; }',
      '.row { width: 100%; min-height: 38px; display: flex; align-items: center; justify-content: space-between; gap: 10px; border-top: 1px solid rgba(255,255,255,.11); }',
      '.row:first-of-type { border-top: 0; }',
      '.label { font-size: 13px; }',
      'button.action { width: 100%; border: 0; background: transparent; color: white; text-align: left; padding: 10px 2px; font-size: 13px; }',
      '.switch { appearance: none; -webkit-appearance: none; width: 42px; height: 24px; border-radius: 12px; background: rgba(255,255,255,.20); position: relative; transition: .15s ease; margin: 0; }',
      '.switch::after { content: ""; position: absolute; width: 20px; height: 20px; border-radius: 50%; background: white; top: 2px; left: 2px; transition: .15s ease; }',
      '.switch:checked { background: #34c759; }',
      '.switch:checked::after { transform: translateX(18px); }',
      '.foot { font-size: 10px; opacity: .5; margin: 8px 2px 1px; }',
    ].join('\n');

    const button = document.createElement('button');
    button.className = 'fab';
    button.type = 'button';
    button.textContent = 'S';
    button.setAttribute('aria-label', 'ChatGPT Safari 控制');

    const panel = document.createElement('div');
    panel.className = 'panel';

    const title = document.createElement('div');
    title.className = 'title';
    title.textContent = 'ChatGPT Web Unified';

    const status = document.createElement('div');
    status.className = 'status';

    const perfRow = document.createElement('label');
    perfRow.className = 'row';
    const perfLabel = document.createElement('span');
    perfLabel.className = 'label';
    perfLabel.textContent = '常驻轻量优化';
    const perfSwitch = document.createElement('input');
    perfSwitch.className = 'switch';
    perfSwitch.type = 'checkbox';
    perfSwitch.checked = state.settings.enabled;
    perfRow.append(perfLabel, perfSwitch);

    const reloadRow = document.createElement('div');
    reloadRow.className = 'row';
    const reload = document.createElement('button');
    reload.type = 'button';
    reload.className = 'action';
    reload.textContent = '重新加载 ChatGPT';
    reloadRow.appendChild(reload);

    const restoreRow = document.createElement('div');
    restoreRow.className = 'row';
    const restore = document.createElement('button');
    restore.type = 'button';
    restore.className = 'action';
    restore.textContent = '恢复官方页面显示';
    restoreRow.appendChild(restore);

    const hideRow = document.createElement('div');
    hideRow.className = 'row';
    const hide = document.createElement('button');
    hide.type = 'button';
    hide.className = 'action';
    hide.textContent = '隐藏悬浮按钮';
    hideRow.appendChild(hide);

    const foot = document.createElement('div');
    foot.className = 'foot';
    foot.textContent = versionLine();

    panel.append(title, status, perfRow, reloadRow, restoreRow, hideRow, foot);
    wrap.append(button, panel);
    shadow.append(style, wrap);
    document.body.appendChild(host);

    button.addEventListener('click', () => {
      panel.classList.toggle('open');
    });

    perfSwitch.addEventListener('change', () => {
      state.settings.enabled = perfSwitch.checked;
      saveSettings();
      scheduleRefresh(0);
    });

    reload.addEventListener('click', () => location.reload());

    restore.addEventListener('click', () => {
      state.settings.enabled = false;
      perfSwitch.checked = false;
      saveSettings();
      restoreOptimizedTurns();
      updateUI(turnCandidates().length);
      panel.classList.remove('open');
    });

    hide.addEventListener('click', () => {
      state.settings.showControl = false;
      saveSettings();
      host.remove();
      state.ui = null;
    });

    state.ui = { host, button, panel, status, perfSwitch, foot };
    updateUI(turnCandidates().length);
  }

  function updateStatusLabel() {
    const status = String(state.nativeStatus?.updateStatus || '');
    switch (status) {
      case 'checking': return '检查更新中';
      case 'latest': return '已是最新';
      case 'updated': return '已热更';
      case 'cached': return '缓存版';
      case 'bundled': return '内置版';
      case 'offline': return '离线 · 使用本地版';
      case 'error': return '更新检查失败';
      default: return state.nativeStatus?.hotUpdate ? '热更已启用' : '自动更新';
    }
  }

  function versionLine() {
    const appVersion = state.nativeStatus?.appVersion;
    if (appVersion) {
      return '脚本 v' + VERSION + ' · IPA ' + appVersion + ' · ' + updateStatusLabel();
    }
    return '脚本 v' + VERSION + ' · PC / iOS 同一脚本';
  }

  function setNativeStatus(next) {
    if (!next || typeof next !== 'object') return;
    state.nativeStatus = { ...state.nativeStatus, ...next };
    window.__CHATGPT_NATIVE__ = { ...(window.__CHATGPT_NATIVE__ || {}), ...next };
    if (state.ui?.foot) state.ui.foot.textContent = versionLine();
    updateUI(turnCandidates().length);
  }

  function updateUI(turnCount) {
    const ui = state.ui;
    if (!ui) return;

    const id = currentConversationId();
    const chatStatus = id ? state.conversationStates[id]?.status : null;
    const mode = state.settings.enabled ? '常驻优化' : '官方原生';

    if (chatStatus && chatStatus !== 'completed_read') {
      ui.button.dataset.chatState = chatStatus;
    } else {
      delete ui.button.dataset.chatState;
    }

    ui.status.textContent =
      mode + ' · ' +
      turnCount + ' 轮 · 已优化 ' +
      state.optimizedTurns.size + ' 轮 · ' +
      statusLabel(chatStatus);

    if (ui.foot) ui.foot.textContent = versionLine();
  }

  function setupObservers() {
    state.observer = new MutationObserver(() => {
      scheduleRefresh(180);
      evaluateConversationState();
      renderConversationStates();
    });
    state.observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
    });

    window.addEventListener('popstate', onRoute, { passive: true });
    window.addEventListener('hashchange', onRoute, { passive: true });
    document.addEventListener('visibilitychange', onVisibility, { passive: true });

    state.statusTimer = window.setInterval(() => {
      if (!state.destroyed) {
        evaluateConversationState();
        renderConversationStates();
      }
    }, 600);
  }

  function onRoute() {
    state.activeConversationId = null;
    state.activeRouteSince = Date.now();
    state.settlingSince = 0;
    scheduleRefresh(0);
    evaluateConversationState();
    renderConversationStates();
  }

  function onVisibility() {
    if (!document.hidden) {
      scheduleRefresh(0);
      evaluateConversationState();
      renderConversationStates();
    }
  }

  function showControl() {
    state.settings.showControl = true;
    saveSettings();
    createControl();
  }

  function setEnabled(value) {
    state.settings.enabled = Boolean(value);
    saveSettings();
    if (state.ui) state.ui.perfSwitch.checked = state.settings.enabled;
    scheduleRefresh(0);
  }

  function getState() {
    const turns = turnCandidates();
    return {
      version: VERSION,
      enabled: state.settings.enabled,
      turns: turns.length,
      optimizedTurns: state.optimizedTurns.size,
      streaming: isStreaming(),
      conversationId: currentConversationId(),
      conversationStatus: currentConversationId()
        ? state.conversationStates[currentConversationId()]?.status || null
        : null,
      conversationStates: { ...state.conversationStates },
      nativeStatus: { ...state.nativeStatus },
      route: location.pathname + location.search,
    };
  }

  function destroy() {
    if (state.destroyed) return;
    state.destroyed = true;

    clearTimeout(state.refreshTimer);
    clearInterval(state.statusTimer);
    state.observer?.disconnect();

    window.removeEventListener('popstate', onRoute);
    window.removeEventListener('hashchange', onRoute);
    document.removeEventListener('visibilitychange', onVisibility);
    window.removeEventListener('storage', onStorageSync);
    try { state.channel?.close?.(); } catch (_) {}

    restoreOptimizedTurns();
    for (const anchor of document.querySelectorAll('[data-cgpt-safari-chat-state]')) {
      anchor.removeAttribute('data-cgpt-safari-chat-state');
    }
    document.getElementById(STYLE_ID)?.remove();
    document.getElementById(HOST_ID)?.remove();
    state.ui = null;

    try {
      delete window[GLOBAL_KEY];
      delete window[LEGACY_GLOBAL_KEY];
    } catch (_) {
      window[GLOBAL_KEY] = undefined;
      window[LEGACY_GLOBAL_KEY] = undefined;
    }
  }

  const api = {
    version: VERSION,
    getState,
    setEnabled,
    setNativeStatus,
    showControl,
    refresh: () => scheduleRefresh(0),
    destroy,
  };

  window[GLOBAL_KEY] = api;
  window[LEGACY_GLOBAL_KEY] = api;

  installStyle();
  setupConversationStateSync();
  setupObservers();

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      createControl();
      scheduleRefresh(0);
      evaluateConversationState();
      renderConversationStates();
    }, { once: true });
  } else {
    createControl();
    scheduleRefresh(0);
    evaluateConversationState();
    renderConversationStates();
  }
})();
