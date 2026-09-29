// ==UserScript==
// @name         ChatGPT Web Unified
// @namespace    https://github.com/masakacj/chatgpt-web
// @version      0.3.35
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

  const VERSION = '0.3.35';
  const GLOBAL_KEY = 'ChatGPTWeb';

  const HOST = location.hostname.toLowerCase();
  const IS_CHATGPT =
    HOST === 'chatgpt.com' ||
    HOST.endsWith('.chatgpt.com');

  if (!IS_CHATGPT) {
    return;
  }

  const IS_NATIVE_IOS = Boolean(
    window.__CHATGPT_NATIVE__?.hotUpdate
  );
  const PERF_REFRESH_DELAY_MS =
    IS_NATIVE_IOS ? 420 : 120;
  const STATUS_INTERVAL_MS =
    IS_NATIVE_IOS ? 1500 : 600;
  const IOS_KEEP_RECENT_TURNS = 6;
  const IOS_TOOL_SWEEP_MS = 6500;
  const TURN_CACHE_MAX_AGE_MS =
    IS_NATIVE_IOS ? 5000 : 3000;
  const WINDOW_ROOT_MARGIN =
    IS_NATIVE_IOS
      ? '220% 0px 260% 0px'
      : '180% 0px 220% 0px';
  const WINDOW_MIN_HEIGHT = 56;
  const TURN_SELECTORS = [
    'article[data-testid^="conversation-turn-"]',
    '[data-testid^="conversation-turn-"]',
    'main article[data-scroll-anchor]',
    'main [data-message-author-role]',
  ];
  const TURN_SELECTOR_QUERY =
    TURN_SELECTORS.join(',');

  const LEGACY_GLOBAL_KEY = 'ChatGPTSafari';
  const STYLE_ID = 'cgpt-safari-lite-style';
  const HOST_ID = 'cgpt-safari-lite-host';
  const SETTINGS_KEY = 'cgpt-safari-lite-settings-v1';
  const CONTROL_MIGRATION_KEY = 'cgpt-unified-control-visible-v031';
  const CONTROL_POSITION_KEY =
    'cgpt-unified-control-position-v1';
  const NATIVE_ANCHOR_MIN_VERSION =
    '0.3.31';
  const CONVERSATION_STATE_KEY = 'cgpt-safari-conversation-state-v1';
  const STATE_CHANNEL = 'cgpt-safari-conversation-state';
  const SETTLE_MS = 2800;
  const READ_DWELL_MS = 1200;
  const STATE_TTL_MS = 14 * 24 * 60 * 60 * 1000;

  const TOOL_GROUP_RE = /(?:已调用工具|工具调用列表|调用工具|Called tools?|Tool calls?|Tools called)/i;
  const TOOL_ACTION_RE = /(?:Ran command|Run command|Called tool|Searched|Read file|Wrote file|Edited file|Opened workspace|Fetched|Executed|运行命令|执行命令|调用工具|搜索|读取文件|写入文件|编辑文件|打开工作区|已运行|已调用)/i;
  const TOOL_ATTENTION_RE = /(?:running|in progress|pending|waiting|failed|error|approval|required|confirm|permission|正在|执行中|等待|失败|错误|需要确认|确认操作|授权|权限)/i;

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
    updateWatchdogTimer: 0,
    optimizedTurns: new Set(),
    turnCache: [],
    turnSet: new Set(),
    turnCacheDirty: true,
    lastTurnScanAt: 0,
    nearTurns: new Set(),
    turnRecords: new WeakMap(),
    windowObserver: null,
    toolGroups: new Set(),
    toolRecords: new WeakMap(),
    toolCounts: { groups: 0, collapsed: 0 },
    lastToolSweepAt: 0,
    lastRoute: location.pathname + location.search,
    activeConversationId: null,
    activeRouteSince: Date.now(),
    settlingSince: 0,
    conversationStates: loadConversationStates(),
    nativeStatus: { ...(window.__CHATGPT_NATIVE__ || {}) },
    channel: null,
    ui: null,
    controlResizeHandler: null,
    controlRecoveryTimer: 0,
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

  function isActiveCycleStatus(status) {
    return (
      status === 'running' ||
      status === 'waiting_user' ||
      status === 'settling'
    );
  }

  function sameConversationCycle(left, right) {
    const leftStartedAt = Number(left?.runStartedAt || 0);
    const rightStartedAt = Number(right?.runStartedAt || 0);
    return (
      leftStartedAt > 0 &&
      rightStartedAt > 0 &&
      leftStartedAt === rightStartedAt
    );
  }

  function completionStatusForCurrentView(id) {
    return (
      !document.hidden &&
      id === currentConversationId()
    )
      ? 'completed_read'
      : 'completed_unread';
  }

  function shouldRenderConversationState(id, status) {
    if (!status || status === 'completed_read') return false;

    if (
      status === 'completed_unread' &&
      !document.hidden &&
      id === currentConversationId()
    ) {
      return false;
    }

    return true;
  }

  function setConversationState(id, status, extra = {}) {
    if (!id) return;

    const previous = state.conversationStates[id] || {};
    const now = Date.now();
    const enteringActiveCycle =
      (
        status === 'running' ||
        status === 'waiting_user'
      ) &&
      !isActiveCycleStatus(previous.status);

    const next = {
      ...previous,
      ...extra,
      status,
      updatedAt: now,
    };

    if (enteringActiveCycle) {
      next.runStartedAt = now;
    }

    if (status === 'completed_unread' && !next.completedAt) {
      next.completedAt = now;
    }

    if (status === 'completed_read') {
      next.readAt = now;
    } else if (
      isActiveCycleStatus(status) ||
      status === 'completed_unread'
    ) {
      next.readAt = 0;
    }

    const unchanged =
      previous.status === next.status &&
      Number(previous.settlingSince || 0) === Number(next.settlingSince || 0) &&
      Number(previous.completedAt || 0) === Number(next.completedAt || 0) &&
      Number(previous.readAt || 0) === Number(next.readAt || 0) &&
      Number(previous.runStartedAt || 0) === Number(next.runStartedAt || 0);

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

    if (
      current?.status === 'completed_read' &&
      record.status === 'completed_unread'
    ) {
      if (sameConversationCycle(current, record)) {
        return;
      }

      const currentReadAt = Number(current.readAt || 0);
      const incomingCompletedAt = Number(record.completedAt || 0);
      const incomingRunStartedAt = Number(record.runStartedAt || 0);

      if (
        incomingRunStartedAt === 0 &&
        currentReadAt > 0 &&
        incomingCompletedAt > 0 &&
        currentReadAt >= incomingCompletedAt
      ) {
        return;
      }
    }

    if (
      current &&
      Number(current.updatedAt || 0) >=
        Number(record.updatedAt || 0)
    ) {
      return;
    }

    state.conversationStates[id] = record;
    persistConversationStates();
    renderConversationStates();
    updateUI(currentTurnCount());
  }

  function renderConversationStates() {
    const anchors = document.querySelectorAll('a[href*="/c/"]');

    for (const anchor of anchors) {
      if (!(anchor instanceof HTMLAnchorElement)) continue;
      const id = conversationIdFromHref(anchor.href);
      const status = id ? state.conversationStates[id]?.status : null;

      if (shouldRenderConversationState(id, status)) {
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
      updateUI(currentTurnCount());
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
      updateUI(currentTurnCount());
      return;
    }

    if (running) {
      state.settlingSince = 0;
      setConversationState(id, 'running', {
        settlingSince: 0,
        completedAt: 0,
      });
      updateUI(currentTurnCount());
      return;
    }

    const record = state.conversationStates[id];

    if (!record) {
      setConversationState(id, 'completed_read', {
        settlingSince: 0,
        completedAt: now,
      });
      updateUI(currentTurnCount());
      return;
    }

    if (record.status === 'running' || record.status === 'waiting_user') {
      state.settlingSince = now;
      setConversationState(id, 'settling', {
        settlingSince: now,
        completedAt: 0,
      });
      updateUI(currentTurnCount());
      return;
    }

    if (record.status === 'settling') {
      const since = Number(record.settlingSince || state.settlingSince || now);
      if (now - since >= SETTLE_MS) {
        const nextStatus = completionStatusForCurrentView(id);
        setConversationState(id, nextStatus, {
          settlingSince: 0,
          completedAt: now,
        });
      }
      updateUI(currentTurnCount());
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

    updateUI(currentTurnCount());
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
      '[data-cgpt-windowed="1"] {',
      '  height: var(--cgpt-window-height) !important;',
      '  min-height: var(--cgpt-window-height) !important;',
      '  max-height: var(--cgpt-window-height) !important;',
      '  overflow: hidden !important;',
      '  contain: strict !important;',
      '  content-visibility: visible !important;',
      '}',
      '[data-cgpt-windowed="1"] > * {',
      '  display: none !important;',
      '}',
      '[data-cgpt-tool-group="1"] {',
      '  content-visibility: auto !important;',
      '  contain: layout style paint !important;',
      '  contain-intrinsic-size: auto 42px !important;',
      '}',
      '[data-cgpt-tool-collapsed="1"] {',
      '  display: block !important;',
      '  min-height: 38px !important;',
      '  max-height: 42px !important;',
      '  overflow: hidden !important;',
      '  contain: strict !important;',
      '}',
      '[data-cgpt-tool-collapsed="1"] > * {',
      '  display: none !important;',
      '}',
      '[data-cgpt-tool-collapsed="1"]::before {',
      '  content: attr(data-cgpt-tool-summary);',
      '  display: block;',
      '  box-sizing: border-box;',
      '  min-height: 38px;',
      '  padding: 9px 11px;',
      '  border: 1px solid color-mix(in srgb, currentColor 12%, transparent);',
      '  border-radius: 10px;',
      '  opacity: .64;',
      '  font: 12px/1.35 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;',
      '  white-space: nowrap;',
      '  overflow: hidden;',
      '  text-overflow: ellipsis;',
      '}',
      '[data-cgpt-tool-collapsed="1"] *,',
      '[data-cgpt-tool-collapsed="1"]::before {',
      '  animation: none !important;',
      '  transition: none !important;',
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

  function collectTurnCandidates() {
    for (const selector of TURN_SELECTORS) {
      const nodes =
        Array.from(
          document.querySelectorAll(selector)
        ).filter(
          (node) =>
            node instanceof HTMLElement &&
            node.isConnected
        );

      if (nodes.length) {
        return nodes;
      }
    }

    return [];
  }

  function turnIdentity(turn) {
    if (!(turn instanceof HTMLElement)) return '';

    return [
      turn.getAttribute('data-testid') || '',
      turn.getAttribute('data-scroll-anchor') || '',
      turn.getAttribute('data-message-author-role') || '',
    ].join('|');
  }

  function ensureWindowObserver() {
    if (
      state.windowObserver ||
      typeof IntersectionObserver !== 'function'
    ) {
      return;
    }

    state.windowObserver =
      new IntersectionObserver(
        (entries) => {
          if (state.destroyed) return;

          const turns = turnCandidates();
          const protectedTurns =
            new Set(
              turns.slice(
                -IOS_KEEP_RECENT_TURNS
              )
            );
          const liveTurn =
            isStreaming() &&
            turns.length
              ? turns[turns.length - 1]
              : null;

          for (const entry of entries) {
            const turn = entry.target;
            if (!(turn instanceof HTMLElement)) {
              continue;
            }

            if (entry.isIntersecting) {
              state.nearTurns.add(turn);
              restoreWindowedTurn(turn);
              continue;
            }

            state.nearTurns.delete(turn);

            if (
              state.settings.enabled &&
              canWindowTurn(
                turn,
                protectedTurns,
                liveTurn
              )
            ) {
              windowTurn(turn);
            } else {
              restoreWindowedTurn(turn);
            }
          }
        },
        {
          root: null,
          rootMargin: WINDOW_ROOT_MARGIN,
          threshold: 0,
        }
      );
  }

  function registerTurn(turn) {
    if (!(turn instanceof HTMLElement)) return;

    const identity = turnIdentity(turn);
    const previous = state.turnRecords.get(turn);

    if (
      previous?.identity &&
      previous.identity !== identity
    ) {
      restoreWindowedTurn(turn);
    }

    state.turnRecords.set(turn, {
      ...(previous || {}),
      identity,
    });

    if (!state.turnSet.has(turn)) {
      state.turnSet.add(turn);
      ensureWindowObserver();
      state.windowObserver?.observe(turn);
    }
  }

  function turnCandidates(force = false) {
    const now = performance.now();

    if (
      !force &&
      !state.turnCacheDirty &&
      now - state.lastTurnScanAt <
        TURN_CACHE_MAX_AGE_MS
    ) {
      return state.turnCache;
    }

    const turns = collectTurnCandidates();
    const nextSet = new Set(turns);

    for (const oldTurn of Array.from(state.turnSet)) {
      if (
        oldTurn.isConnected &&
        nextSet.has(oldTurn)
      ) {
        continue;
      }

      state.windowObserver?.unobserve(oldTurn);
      state.nearTurns.delete(oldTurn);
      restoreWindowedTurn(oldTurn);
      state.turnSet.delete(oldTurn);
    }

    for (const turn of turns) {
      registerTurn(turn);
    }

    state.turnCache = turns;
    state.turnCacheDirty = false;
    state.lastTurnScanAt = now;

    return turns;
  }

  function currentTurnCount() {
    return turnCandidates().length;
  }

  function selectionTouches(turn) {
    const selection = window.getSelection?.();
    if (!selection || selection.rangeCount < 1) {
      return false;
    }

    const anchor = selection.anchorNode;
    const focus = selection.focusNode;

    return Boolean(
      (anchor && turn.contains(anchor)) ||
      (focus && turn.contains(focus))
    );
  }

  function turnHasActiveMedia(turn) {
    return Array.from(
      turn.querySelectorAll('audio,video')
    ).some(
      (media) =>
        media instanceof HTMLMediaElement &&
        !media.paused
    );
  }

  function canWindowTurn(
    turn,
    protectedTurns,
    liveTurn
  ) {
    if (!(turn instanceof HTMLElement)) {
      return false;
    }

    if (
      turn === liveTurn ||
      protectedTurns.has(turn) ||
      turn.matches(':focus-within') ||
      selectionTouches(turn) ||
      turnHasActiveMedia(turn)
    ) {
      return false;
    }

    if (
      turn.querySelector(
        '[aria-busy="true"],' +
        '[role="progressbar"],' +
        '[data-state="loading"],' +
        '[data-loading="true"]'
      )
    ) {
      return false;
    }

    return true;
  }

  function windowTurn(turn) {
    if (
      !(turn instanceof HTMLElement) ||
      turn.hasAttribute('data-cgpt-windowed')
    ) {
      return;
    }

    const rect = turn.getBoundingClientRect();
    const height = Math.ceil(rect.height);

    if (
      !Number.isFinite(height) ||
      height < WINDOW_MIN_HEIGHT ||
      turn.childElementCount === 0
    ) {
      return;
    }

    const record =
      state.turnRecords.get(turn) || {};

    record.height = height;
    record.identity = turnIdentity(turn);
    state.turnRecords.set(turn, record);

    turn.style.setProperty(
      '--cgpt-window-height',
      height + 'px'
    );
    turn.setAttribute(
      'data-cgpt-windowed',
      '1'
    );
    state.optimizedTurns.add(turn);
  }

  function restoreWindowedTurn(turn) {
    if (!(turn instanceof HTMLElement)) {
      return;
    }

    turn.removeAttribute(
      'data-cgpt-windowed'
    );
    turn.style.removeProperty(
      '--cgpt-window-height'
    );
    state.optimizedTurns.delete(turn);
  }

  function invalidateTurnCache() {
    state.turnCacheDirty = true;
    state.lastTurnScanAt = 0;
  }

  function nodeLabel(node) {
    return [
      String(node?.textContent || '').replace(/\s+/g, ' ').trim(),
      node?.getAttribute?.('aria-label') || '',
      node?.getAttribute?.('title') || '',
    ].join(' ').replace(/\s+/g, ' ').trim();
  }

  function toolActionNodes(scope) {
    return Array.from(
      scope.querySelectorAll('button,[role="button"],summary,[aria-expanded]')
    ).filter((node) => {
      const text = nodeLabel(node);
      return TOOL_ACTION_RE.test(text) && !TOOL_GROUP_RE.test(text);
    });
  }

  function findToolGroupContainer(heading, turn) {
    let node = heading.parentElement;

    for (
      let depth = 0;
      node && node !== turn && depth < 7;
      depth += 1, node = node.parentElement
    ) {
      const role = node.getAttribute?.('role');
      if (
        node.tagName === 'BUTTON' ||
        node.tagName === 'SUMMARY' ||
        role === 'button'
      ) {
        continue;
      }

      if (
        node.children.length >= 2 ||
        toolActionNodes(node).length > 0
      ) {
        return node;
      }
    }

    return null;
  }

  function findToolGroups(turn) {
    const headings = Array.from(
      turn.querySelectorAll(
        'button,[role="button"],summary,[aria-expanded]'
      )
    ).filter((node) => TOOL_GROUP_RE.test(nodeLabel(node)));

    const groups = [];

    for (const heading of headings) {
      const group = findToolGroupContainer(heading, turn);
      if (!(group instanceof HTMLElement)) continue;
      if (
        groups.some(
          (existing) =>
            existing === group ||
            existing.contains(group)
        )
      ) {
        continue;
      }

      for (let index = groups.length - 1; index >= 0; index -= 1) {
        if (group.contains(groups[index])) {
          groups.splice(index, 1);
        }
      }

      groups.push(group);
    }

    return groups;
  }

  function toolGroupNeedsAttention(group) {
    const nodes = Array.from(
      group.querySelectorAll(
        'button,[role="button"],summary,[aria-live],[aria-label],[aria-busy="true"],[role="progressbar"]'
      )
    );

    return nodes.some((node) => {
      if (
        node.matches?.(
          '[aria-busy="true"],[role="progressbar"],[data-state="loading"],[data-loading="true"]'
        )
      ) {
        return true;
      }
      return TOOL_ATTENTION_RE.test(nodeLabel(node));
    });
  }

  function toolSummary(group) {
    let record = state.toolRecords.get(group);
    if (!record) {
      record = {};
      state.toolRecords.set(group, record);
    }

    if (record.summary) return record.summary;

    const count = Math.max(1, toolActionNodes(group).length);
    const chinese =
      (document.documentElement.lang || '')
        .toLowerCase()
        .startsWith('zh');

    record.summary = chinese
      ? '🛠 工具过程 · ' + count + ' 项 · 已折叠'
      : '🛠 Tool process · ' + count + ' item' +
        (count === 1 ? '' : 's') + ' · collapsed';

    return record.summary;
  }

  function optimizeToolGroups(turns, liveTurn) {
    let groups = 0;
    let collapsed = 0;
    const seen = new Set();

    for (const turn of turns) {
      if (!(turn instanceof HTMLElement)) continue;

      for (const group of findToolGroups(turn)) {
        if (seen.has(group)) continue;
        seen.add(group);
        state.toolGroups.add(group);
        groups += 1;

        const active =
          turn === liveTurn ||
          toolGroupNeedsAttention(group) ||
          group.matches(':focus-within');

        group.setAttribute('data-cgpt-tool-group', '1');

        if (active) {
          group.removeAttribute('data-cgpt-tool-collapsed');
          group.removeAttribute('data-cgpt-tool-summary');
        } else {
          group.setAttribute('data-cgpt-tool-collapsed', '1');
          group.setAttribute(
            'data-cgpt-tool-summary',
            toolSummary(group)
          );
          collapsed += 1;
        }
      }
    }

    for (const group of Array.from(state.toolGroups)) {
      if (!group.isConnected) {
        state.toolGroups.delete(group);
        continue;
      }

      if (!seen.has(group)) {
        group.removeAttribute('data-cgpt-tool-group');
        group.removeAttribute('data-cgpt-tool-collapsed');
        group.removeAttribute('data-cgpt-tool-summary');
        state.toolGroups.delete(group);
      }
    }

    state.toolCounts = { groups, collapsed };
  }

  function restoreToolGroups() {
    for (const group of Array.from(state.toolGroups)) {
      if (!(group instanceof HTMLElement)) continue;
      group.removeAttribute('data-cgpt-tool-group');
      group.removeAttribute('data-cgpt-tool-collapsed');
      group.removeAttribute('data-cgpt-tool-summary');
    }

    state.toolGroups.clear();
    state.toolCounts = { groups: 0, collapsed: 0 };
  }

  function restoreOptimizedTurns() {
    for (
      const turn of
        Array.from(state.optimizedTurns)
    ) {
      restoreWindowedTurn(turn);
    }
    state.optimizedTurns.clear();
  }

  function applyPerformanceHints() {
    const turns = turnCandidates();

    if (!state.settings.enabled) {
      restoreOptimizedTurns();
      restoreToolGroups();
      updateUI(turns.length);
      return;
    }

    ensureWindowObserver();

    const streaming = isStreaming();
    const liveTurn =
      streaming && turns.length
        ? turns[turns.length - 1]
        : null;

    const protectedTurns =
      turns.slice(
        -IOS_KEEP_RECENT_TURNS
      );

    for (const turn of protectedTurns) {
      restoreWindowedTurn(turn);
    }

    if (liveTurn) {
      restoreWindowedTurn(liveTurn);
    }

    const activeTurnSet =
      new Set([
        ...state.nearTurns,
        ...protectedTurns,
      ]);

    if (liveTurn) {
      activeTurnSet.add(liveTurn);
    }

    const activeTurns =
      Array.from(activeTurnSet)
        .filter(
          (turn) =>
            turn instanceof HTMLElement &&
            turn.isConnected &&
            !turn.hasAttribute(
              'data-cgpt-windowed'
            )
        );

    const now = performance.now();
    if (
      now - state.lastToolSweepAt >=
        IOS_TOOL_SWEEP_MS
    ) {
      optimizeToolGroups(
        activeTurns,
        liveTurn
      );
      state.lastToolSweepAt = now;
    }

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

  function scheduleRefresh(
    delay = PERF_REFRESH_DELAY_MS
  ) {
    if (state.destroyed) return;
    clearTimeout(state.refreshTimer);
    state.refreshTimer = window.setTimeout(() => {
      if (state.destroyed) return;
      const route = location.pathname + location.search;
      if (route !== state.lastRoute) {
        state.lastRoute = route;
        restoreOptimizedTurns();
        restoreToolGroups();
        state.nearTurns.clear();
        invalidateTurnCache();
      }
      window.requestAnimationFrame(applyPerformanceHints);
    }, delay);
  }

  function requestNativeUpdateCheck() {
    try {
      const handler =
        window.webkit?.messageHandlers?.chatGPTNative;

      if (!handler?.postMessage) return false;

      setNativeStatus({
        ...(window.__CHATGPT_NATIVE__ || {}),
        updateStatus: 'checking',
        ...(window.__CHATGPT_NATIVE__?.gestureVersion
          ? { gestureUpdateStatus: 'checking' }
          : {}),
      });

      clearTimeout(state.updateWatchdogTimer);
      state.updateWatchdogTimer = window.setTimeout(() => {
        if (
          state.nativeStatus?.updateStatus === 'checking'
        ) {
          setNativeStatus({
            ...(window.__CHATGPT_NATIVE__ || {}),
            updateStatus: 'timeout',
            ...(window.__CHATGPT_NATIVE__?.gestureVersion
              ? { gestureUpdateStatus: 'timeout' }
              : {}),
          });
        }
      }, 10000);

      handler.postMessage({ type: 'check-update' });
      return true;
    } catch (_) {
      return false;
    }
  }

  function versionParts(value) {
    return String(value || '')
      .split('.')
      .map((part) =>
        Number.parseInt(part, 10) || 0
      );
  }

  function versionAtLeast(value, minimum) {
    const left = versionParts(value);
    const right = versionParts(minimum);
    const length =
      Math.max(left.length, right.length);

    for (
      let index = 0;
      index < length;
      index += 1
    ) {
      const a = left[index] || 0;
      const b = right[index] || 0;
      if (a > b) return true;
      if (a < b) return false;
    }

    return true;
  }

  function nativeAnchorSupported() {
    return Boolean(
      IS_NATIVE_IOS &&
      versionAtLeast(
        state.nativeStatus?.appVersion,
        NATIVE_ANCHOR_MIN_VERSION
      )
    );
  }

  function loadControlPosition() {
    try {
      const raw = JSON.parse(
        localStorage.getItem(
          CONTROL_POSITION_KEY
        ) || 'null'
      );

      if (
        raw &&
        Number.isFinite(Number(raw.x)) &&
        Number.isFinite(Number(raw.y))
      ) {
        return {
          x: clamp(Number(raw.x), 0, 1),
          y: clamp(Number(raw.y), 0, 1),
        };
      }
    } catch (_) {}

    return null;
  }

  function saveControlPosition(host) {
    if (!(host instanceof HTMLElement)) return;

    const rect = host.getBoundingClientRect();
    const width =
      Math.max(
        1,
        window.innerWidth - rect.width
      );
    const height =
      Math.max(
        1,
        window.innerHeight - rect.height
      );

    try {
      localStorage.setItem(
        CONTROL_POSITION_KEY,
        JSON.stringify({
          x: clamp(rect.left / width, 0, 1),
          y: clamp(rect.top / height, 0, 1),
        })
      );
    } catch (_) {}
  }

  function positionControlHost(host, left, top) {
    if (!(host instanceof HTMLElement)) return;

    const rect = host.getBoundingClientRect();
    const width = rect.width || 36;
    const height = rect.height || 36;
    const padding = 8;

    const x = clamp(
      Number(left),
      padding,
      Math.max(
        padding,
        window.innerWidth -
          width -
          padding
      )
    );
    const y = clamp(
      Number(top),
      padding,
      Math.max(
        padding,
        window.innerHeight -
          height -
          padding
      )
    );

    host.style.left = x + 'px';
    host.style.top = y + 'px';
    host.style.right = 'auto';

    host.dataset.panelSide =
      x + width / 2 < window.innerWidth / 2
        ? 'left'
        : 'right';
    host.dataset.panelVertical =
      y + height / 2 > window.innerHeight / 2
        ? 'up'
        : 'down';
  }

  function restoreControlPosition(host) {
    const stored = loadControlPosition();
    if (!stored) return;

    const rect = host.getBoundingClientRect();
    const width =
      Math.max(
        1,
        window.innerWidth -
          (rect.width || 36)
      );
    const height =
      Math.max(
        1,
        window.innerHeight -
          (rect.height || 36)
      );

    positionControlHost(
      host,
      stored.x * width,
      stored.y * height
    );
  }

  function requestNativeAction(type, payload = {}) {
    try {
      const handler =
        window.webkit?.messageHandlers?.chatGPTNative;

      if (!handler?.postMessage) return false;

      handler.postMessage({
        type,
        ...payload,
      });

      return true;
    } catch (_) {
      return false;
    }
  }

  function cleanupDetachedControl() {
    if (
      state.ui?.host &&
      state.ui.host.isConnected
    ) {
      return;
    }

    if (state.controlResizeHandler) {
      window.removeEventListener(
        'resize',
        state.controlResizeHandler
      );
      state.controlResizeHandler = null;
    }

    state.ui = null;
  }

  function ensureControlMounted() {
    if (state.destroyed) {
      return false;
    }

    const existing =
      document.getElementById(HOST_ID);

    if (existing?.isConnected) {
      return true;
    }

    cleanupDetachedControl();

    if (!document.body) {
      return false;
    }

    createControl();

    return Boolean(
      document.getElementById(HOST_ID)
        ?.isConnected
    );
  }

  function scheduleControlRecovery(
    delay = 80
  ) {
    if (
      state.destroyed ||
      !IS_NATIVE_IOS
    ) {
      return;
    }

    clearTimeout(
      state.controlRecoveryTimer
    );

    state.controlRecoveryTimer =
      window.setTimeout(() => {
        state.controlRecoveryTimer = 0;

        if (ensureControlMounted()) {
          return;
        }

        scheduleControlRecovery(220);
      }, delay);
  }

  function createControl() {
    if (
      (!state.settings.showControl && !IS_NATIVE_IOS) ||
      state.destroyed
    ) return;

    cleanupDetachedControl();

    if (
      !document.body ||
      document.getElementById(HOST_ID)
    ) {
      return;
    }

    const usingNativeAnchor =
      nativeAnchorSupported();

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
      '.fab { width: 36px; height: 36px; border: 0; border-radius: 18px; background: rgba(32,32,32,.78); color: white; box-shadow: 0 3px 14px rgba(0,0,0,.22); display: grid; place-items: center; font-size: 14px; font-weight: 700; backdrop-filter: blur(18px); -webkit-backdrop-filter: blur(18px); touch-action: none; user-select: none; -webkit-user-select: none; }',
      '.fab[data-chat-state]::after { content: ""; width: 7px; height: 7px; border-radius: 50%; position: absolute; right: 1px; top: 1px; box-shadow: 0 0 0 2px rgba(255,255,255,.82); }',
      '.fab[data-chat-state="running"]::after { background: #34c759; animation: pulse 1.15s ease-in-out infinite; }',
      '.fab[data-chat-state="waiting_user"]::after { background: #ff9f0a; }',
      '.fab[data-chat-state="settling"]::after { background: #8e8e93; animation: pulse .9s ease-in-out infinite; }',
      '.fab[data-chat-state="completed_unread"]::after { background: #0a84ff; }',
      '@keyframes pulse { 0%,100% { opacity: .45; transform: scale(.82); } 50% { opacity: 1; transform: scale(1.12); } }',
      '.panel { position: absolute; top: 42px; right: 0; width: 226px; padding: 8px; border-radius: 13px; background: rgba(28,28,30,.94); color: white; box-shadow: 0 12px 34px rgba(0,0,0,.28); backdrop-filter: blur(24px); -webkit-backdrop-filter: blur(24px); display: none; }',
      ':host([data-panel-side="left"]) .panel { left: 0; right: auto; }',
      ':host([data-panel-side="right"]) .panel { left: auto; right: 0; }',
      ':host([data-panel-vertical="up"]) .panel { top: auto; bottom: 42px; }',
      ':host([data-panel-vertical="down"]) .panel { top: 42px; bottom: auto; }',
      '.panel.open { display: block; }',
      '.title { font-size: 12px; font-weight: 700; margin: 1px 2px 6px; }',
      '.status { font-size: 10px; opacity: .70; margin: 0 2px 7px; line-height: 1.3; }',
      '.info { margin: 0 0 6px; padding: 6px 8px; border-radius: 9px; background: rgba(255,255,255,.07); }',
      '.info-row { min-height: 19px; display: flex; align-items: center; justify-content: space-between; gap: 10px; font-size: 10.5px; }',
      '.info-key { opacity: .58; }',
      '.info-value { opacity: .92; text-align: right; font-variant-numeric: tabular-nums; }',
      '.row { width: 100%; min-height: 33px; display: flex; align-items: center; justify-content: space-between; gap: 9px; border-top: 1px solid rgba(255,255,255,.11); }',
      '.row:first-of-type { border-top: 0; }',
      '.label { font-size: 12px; }',
      'button.action { width: 100%; border: 0; background: transparent; color: white; text-align: left; padding: 7px 2px; font-size: 12px; }',
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
    button.setAttribute(
      'aria-label',
      'ChatGPT Web 控制'
    );

    const panel = document.createElement('div');
    panel.className = 'panel';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute(
      'aria-label',
      'ChatGPT Web 菜单'
    );
    panel.setAttribute(
      'aria-hidden',
      'true'
    );

    if (usingNativeAnchor) {
      button.style.display = 'none';
      host.style.left = '0px';
      host.style.top = '0px';
      host.style.right = '0px';
      host.style.bottom = '0px';
      host.style.width = 'auto';
      host.style.height = 'auto';
      host.style.pointerEvents = 'none';
      wrap.style.pointerEvents = 'none';
      panel.style.pointerEvents = 'auto';
    }

    const title = document.createElement('div');
    title.className = 'title';
    title.textContent = 'ChatGPT Web Unified';

    const status = document.createElement('div');
    status.className = 'status';

    const info = document.createElement('div');
    info.className = 'info';

    const scriptInfo =
      makeInfoRow('当前脚本');
    const latestInfo =
      makeInfoRow('最新脚本');
    const appInfo =
      makeInfoRow('容器');
    const updateInfo =
      makeInfoRow('更新状态');
    const toolInfo = makeInfoRow('工具过程');
    const gestureInfo = state.nativeStatus?.gestureVersion
      ? makeInfoRow('iOS 手势')
      : null;

    info.append(
      scriptInfo.row,
      latestInfo.row,
      appInfo.row,
      updateInfo.row,
      toolInfo.row
    );
    if (gestureInfo) {
      info.append(gestureInfo.row);
    }

    const perfRow = document.createElement('label');
    perfRow.className = 'row';
    const perfLabel = document.createElement('span');
    perfLabel.className = 'label';
    perfLabel.textContent = '常驻平衡优化';
    const perfSwitch = document.createElement('input');
    perfSwitch.className = 'switch';
    perfSwitch.type = 'checkbox';
    perfSwitch.checked = state.settings.enabled;
    perfRow.append(perfLabel, perfSwitch);

    const updateRow = document.createElement('div');
    updateRow.className = 'row';
    const update = document.createElement('button');
    update.type = 'button';
    update.className = 'action';
    update.textContent = '检查更新';
    updateRow.appendChild(update);

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

    const cacheRow =
      document.createElement('div');
    cacheRow.className = 'row';
    const clearCache =
      document.createElement('button');
    clearCache.type = 'button';
    clearCache.className = 'action';
    clearCache.textContent =
      '清除网页缓存（保留登录）';
    cacheRow.appendChild(clearCache);

    const hideRow =
      document.createElement('div');
    hideRow.className = 'row';
    const hide =
      document.createElement('button');
    hide.type = 'button';
    hide.className = 'action';
    hide.textContent = '隐藏悬浮按钮';
    hideRow.appendChild(hide);

    const foot = document.createElement('div');
    foot.className = 'foot';
    foot.textContent = versionLine();

    panel.append(
      title,
      status,
      info,
      perfRow,
      updateRow,
      reloadRow,
      restoreRow
    );

    if (IS_NATIVE_IOS) {
      panel.append(cacheRow);
    } else {
      panel.append(hideRow);
    }

    panel.append(foot);

    if (usingNativeAnchor) {
      shadow.append(style, panel);
    } else {
      wrap.append(button, panel);
      shadow.append(style, wrap);

      window.requestAnimationFrame(() => {
        restoreControlPosition(host);

        const rect =
          host.getBoundingClientRect();

        host.dataset.panelSide =
          rect.left + rect.width / 2 <
          window.innerWidth / 2
            ? 'left'
            : 'right';

        host.dataset.panelVertical =
          rect.top + rect.height / 2 >
          window.innerHeight / 2
            ? 'up'
            : 'down';
      });

      const onControlResize = () => {
        const rect =
          host.getBoundingClientRect();

        positionControlHost(
          host,
          rect.left,
          rect.top
        );
      };

      state.controlResizeHandler =
        onControlResize;

      window.addEventListener(
        'resize',
        onControlResize,
        { passive: true }
      );
    }

    document.body.appendChild(host);

    const drag = {
      active: false,
      moved: false,
      pointerId: null,
      startX: 0,
      startY: 0,
      startLeft: 0,
      startTop: 0,
      suppressClickUntil: 0,
    };

    button.addEventListener(
      'pointerdown',
      (event) => {
        if (
          event.button !== undefined &&
          event.button !== 0
        ) {
          return;
        }

        const rect =
          host.getBoundingClientRect();

        drag.active = true;
        drag.moved = false;
        drag.pointerId = event.pointerId;
        drag.startX = event.clientX;
        drag.startY = event.clientY;
        drag.startLeft = rect.left;
        drag.startTop = rect.top;

        try {
          button.setPointerCapture?.(
            event.pointerId
          );
        } catch (_) {}
      }
    );

    button.addEventListener(
      'pointermove',
      (event) => {
        if (
          !drag.active ||
          event.pointerId !==
            drag.pointerId
        ) {
          return;
        }

        const dx =
          event.clientX - drag.startX;
        const dy =
          event.clientY - drag.startY;

        if (
          !drag.moved &&
          Math.hypot(dx, dy) < 6
        ) {
          return;
        }

        drag.moved = true;
        panel.classList.remove('open');

        positionControlHost(
          host,
          drag.startLeft + dx,
          drag.startTop + dy
        );

        event.preventDefault();
        event.stopPropagation();
      }
    );

    function finishControlDrag(event) {
      if (
        !drag.active ||
        (
          event?.pointerId !== undefined &&
          event.pointerId !==
            drag.pointerId
        )
      ) {
        return;
      }

      if (drag.moved) {
        saveControlPosition(host);
        drag.suppressClickUntil =
          performance.now() + 350;
      }

      try {
        button.releasePointerCapture?.(
          drag.pointerId
        );
      } catch (_) {}

      drag.active = false;
      drag.pointerId = null;
    }

    button.addEventListener(
      'pointerup',
      finishControlDrag
    );
    button.addEventListener(
      'pointercancel',
      finishControlDrag
    );

    button.addEventListener('click', () => {
      if (
        performance.now() <
        drag.suppressClickUntil
      ) {
        return;
      }

      const opening = !panel.classList.contains('open');
      panel.classList.toggle('open');

      if (opening) {
        state.nativeStatus = {
          ...state.nativeStatus,
          ...(window.__CHATGPT_NATIVE__ || {}),
        };
        requestNativeUpdateCheck();
        scheduleRefresh(0);
        evaluateConversationState();
        renderConversationStates();
        updateUI(currentTurnCount());
      }
    });

    perfSwitch.addEventListener('change', () => {
      state.settings.enabled = perfSwitch.checked;
      saveSettings();
      scheduleRefresh(0);
    });

    update.addEventListener('click', () => {
      requestNativeUpdateCheck();
      updateUI(currentTurnCount());
    });

    reload.addEventListener(
      'click',
      () => location.reload()
    );

    clearCache.addEventListener(
      'click',
      () => {
        clearCache.disabled = true;
        clearCache.style.opacity = '.55';
        clearCache.textContent =
          '清理中…';

        if (
          !requestNativeAction(
            'clear-cache'
          )
        ) {
          clearCache.disabled = false;
          clearCache.style.opacity = '1';
          clearCache.textContent =
            '清除失败 · 重试';
        }
      }
    );

    restore.addEventListener('click', () => {
      state.settings.enabled = false;
      perfSwitch.checked = false;
      saveSettings();
      restoreOptimizedTurns();
      updateUI(currentTurnCount());
      panel.classList.remove('open');
      panel.setAttribute(
        'aria-hidden',
        'true'
      );
    });

    hide.addEventListener('click', () => {
      if (IS_NATIVE_IOS) return;

      state.settings.showControl = false;
      saveSettings();

      if (state.controlResizeHandler) {
        window.removeEventListener(
          'resize',
          state.controlResizeHandler
        );
        state.controlResizeHandler = null;
      }

      host.remove();
      state.ui = null;
    });

    state.ui = {
      host,
      button,
      panel,
      status,
      perfSwitch,
      update,
      clearCache,
      foot,
      scriptInfo: scriptInfo.value,
      latestInfo: latestInfo.value,
      appInfo: appInfo.value,
      updateInfo: updateInfo.value,
      toolInfo: toolInfo.value,
      gestureInfo: gestureInfo?.value || null,
    };
    updateUI(currentTurnCount());
  }

  function positionNativePanel(
    anchor
  ) {
    const panel = state.ui?.panel;

    if (
      !(panel instanceof HTMLElement) ||
      !anchor
    ) {
      return;
    }

    const padding = 8;
    const gap = 8;
    const viewportWidth =
      Math.max(window.innerWidth, 1);
    const viewportHeight =
      Math.max(window.innerHeight, 1);

    panel.style.position = 'fixed';
    panel.style.right = 'auto';
    panel.style.bottom = 'auto';
    panel.style.visibility = 'hidden';

    const rect =
      panel.getBoundingClientRect();

    const anchorLeft =
      Number(anchor.left) || 0;
    const anchorTop =
      Number(anchor.top) || 0;
    const anchorRight =
      Number(anchor.right) ||
      anchorLeft +
        (Number(anchor.width) || 44);
    const anchorBottom =
      Number(anchor.bottom) ||
      anchorTop +
        (Number(anchor.height) || 44);

    const preferRight =
      anchorLeft +
        (anchorRight - anchorLeft) / 2 <
      viewportWidth / 2;

    let left =
      preferRight
        ? anchorRight + gap
        : anchorLeft -
          rect.width -
          gap;

    left = clamp(
      left,
      padding,
      Math.max(
        padding,
        viewportWidth -
          rect.width -
          padding
      )
    );

    let top = anchorTop;

    if (
      top + rect.height >
      viewportHeight - padding
    ) {
      top =
        anchorBottom -
        rect.height;
    }

    top = clamp(
      top,
      padding,
      Math.max(
        padding,
        viewportHeight -
          rect.height -
          padding
      )
    );

    panel.style.left = left + 'px';
    panel.style.top = top + 'px';
    panel.style.visibility = 'visible';
  }

  function toggleNativePanel(anchor) {
    if (!nativeAnchorSupported()) {
      return false;
    }

    ensureControlMounted();

    const panel = state.ui?.panel;

    if (!(panel instanceof HTMLElement)) {
      return false;
    }

    const opening =
      !panel.classList.contains('open');

    if (!opening) {
      panel.classList.remove('open');
      panel.setAttribute(
        'aria-hidden',
        'true'
      );
      return true;
    }

    panel.classList.add('open');
    panel.setAttribute(
      'aria-hidden',
      'false'
    );

    state.nativeStatus = {
      ...state.nativeStatus,
      ...(window.__CHATGPT_NATIVE__ || {}),
    };

    updateUI(currentTurnCount());
    requestNativeUpdateCheck();
    scheduleRefresh(0);
    evaluateConversationState();
    renderConversationStates();

    window.requestAnimationFrame(() => {
      positionNativePanel(anchor);
    });

    return true;
  }

  function closeNativePanel() {
    const panel = state.ui?.panel;
    panel?.classList.remove('open');
    panel?.setAttribute(
      'aria-hidden',
      'true'
    );
    return true;
  }

  function makeInfoRow(label) {
    const row = document.createElement('div');
    row.className = 'info-row';

    const key = document.createElement('span');
    key.className = 'info-key';
    key.textContent = label;

    const value = document.createElement('span');
    value.className = 'info-value';

    row.append(key, value);
    return { row, value };
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
      case 'timeout': return '检查超时 · 使用当前版本';
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

  function nativeActionResult(result) {
    if (
      !result ||
      typeof result !== 'object'
    ) {
      return;
    }

    if (
      result.type === 'clear-cache' &&
      state.ui?.clearCache
    ) {
      const button =
        state.ui.clearCache;

      button.disabled = false;
      button.style.opacity = '1';
      button.textContent =
        result.ok
          ? '缓存已清除'
          : '清除失败 · 重试';

      window.setTimeout(() => {
        if (
          !state.destroyed &&
          button.isConnected
        ) {
          button.textContent =
            '清除网页缓存（保留登录）';
        }
      }, 1800);
    }
  }

  function setNativeStatus(next) {
    if (!next || typeof next !== 'object') return;
    state.nativeStatus = { ...state.nativeStatus, ...next };
    window.__CHATGPT_NATIVE__ = { ...(window.__CHATGPT_NATIVE__ || {}), ...next };
    if (state.ui?.foot) {
      state.ui.foot.textContent =
        versionLine();
    }

    if (
      IS_NATIVE_IOS &&
      !document.getElementById(HOST_ID)
    ) {
      scheduleControlRecovery(0);
    }

    updateUI(currentTurnCount());
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
      statusLabel(chatStatus) +
      (state.toolCounts.collapsed > 0
        ? ' · 工具折叠 ' + state.toolCounts.collapsed
        : '');

    if (ui.scriptInfo) {
      ui.scriptInfo.textContent =
        'v' + VERSION;
    }

    if (ui.latestInfo) {
      const checking =
        String(
          state.nativeStatus?.updateStatus ||
          ''
        ) === 'checking';

      const latest =
        state.nativeStatus
          ?.latestScriptVersion ||
        state.nativeStatus
          ?.scriptVersion ||
        VERSION;

      ui.latestInfo.textContent =
        checking
          ? '检查中…'
          : 'v' + latest;
    }

    if (ui.appInfo) {
      ui.appInfo.textContent = state.nativeStatus?.appVersion
        ? 'v' + state.nativeStatus.appVersion
        : '浏览器';
    }
    if (ui.updateInfo) {
      ui.updateInfo.textContent = updateStatusLabel();
    }

    if (ui.update) {
      const updateStatus = String(
        state.nativeStatus?.updateStatus || ''
      );

      const failed = [
        'offline',
        'timeout',
        'error',
      ].includes(updateStatus);

      const checking = updateStatus === 'checking';

      ui.update.disabled = checking;
      ui.update.style.opacity = checking ? '.5' : '1';
      ui.update.textContent =
        checking ? '检查更新中…' :
        failed ? '重试更新' :
        ['latest', 'updated'].includes(updateStatus)
          ? '再次检查更新'
          : '检查更新';
    }
    if (ui.toolInfo) {
      ui.toolInfo.textContent =
        state.toolCounts.groups > 0
          ? state.toolCounts.collapsed + ' / ' +
            state.toolCounts.groups + ' 已折叠'
          : '无';
    }
    if (ui.gestureInfo) {
      const version = state.nativeStatus?.gestureVersion || '未知';
      const status = String(
        state.nativeStatus?.gestureUpdateStatus || ''
      );
      const label =
        status === 'checking' ? '检查中' :
        status === 'updated' ? '已热更' :
        status === 'latest' ? '已是最新' :
        status === 'offline' ? '离线' :
        status === 'timeout' ? '检查超时' :
        status === 'cached' ? '缓存版' :
        status === 'bundled' ? '内置版' :
        '已启用';
      ui.gestureInfo.textContent =
        'v' + version + ' · ' + label;
    }
    if (ui.foot) ui.foot.textContent = versionLine();
  }

  function setupObservers() {
    state.observer = new MutationObserver(
      (mutations) => {
        if (
          IS_NATIVE_IOS &&
          !document.getElementById(HOST_ID)
        ) {
          scheduleControlRecovery(40);
        }

        let relevant = !IS_NATIVE_IOS;
        let turnStructureChanged = false;

        for (const mutation of mutations) {
          for (const node of mutation.addedNodes) {
            if (!(node instanceof Element)) {
              continue;
            }

            if (
              node.matches?.(
                TURN_SELECTOR_QUERY
              ) ||
              node.querySelector?.(
                TURN_SELECTOR_QUERY
              )
            ) {
              turnStructureChanged = true;
              relevant = true;
              break;
            }
          }

          if (turnStructureChanged) {
            break;
          }

          if (IS_NATIVE_IOS) {
            const target =
              mutation.target instanceof Element
                ? mutation.target
                : mutation.target?.parentElement;

            if (
              target?.closest?.(
                'main,aside,nav,' +
                TURN_SELECTOR_QUERY
              )
            ) {
              relevant = true;
            }
          }
        }

        if (!relevant) return;

        if (turnStructureChanged) {
          invalidateTurnCache();
        }

        scheduleRefresh(
          turnStructureChanged
            ? 120
            : (IS_NATIVE_IOS ? 520 : 220)
        );

        if (!IS_NATIVE_IOS) {
          evaluateConversationState();
          renderConversationStates();
        }
      }
    );

    state.observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
    });

    window.addEventListener('popstate', onRoute, { passive: true });
    window.addEventListener('hashchange', onRoute, { passive: true });
    document.addEventListener('visibilitychange', onVisibility, { passive: true });

    state.statusTimer = window.setInterval(() => {
      if (!state.destroyed) {
        if (
          IS_NATIVE_IOS &&
          !document.getElementById(HOST_ID)
        ) {
          scheduleControlRecovery(0);
        }

        evaluateConversationState();
        renderConversationStates();
      }
    }, STATUS_INTERVAL_MS);
  }

  function onRoute() {
    state.activeConversationId = null;
    state.activeRouteSince = Date.now();
    state.settlingSince = 0;
    restoreOptimizedTurns();
    restoreToolGroups();
    state.nearTurns.clear();
    invalidateTurnCache();
    scheduleRefresh(0);
    evaluateConversationState();
    renderConversationStates();
  }

  function onVisibility() {
    if (!document.hidden) {
      if (
        IS_NATIVE_IOS &&
        !document.getElementById(HOST_ID)
      ) {
        scheduleControlRecovery(0);
      }

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
      windowing: {
        cachedTurns: state.turnCache.length,
        nearTurns: state.nearTurns.size,
        windowedTurns:
          state.optimizedTurns.size,
        observer:
          Boolean(state.windowObserver),
      },
      toolGroups: { ...state.toolCounts },
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
    clearTimeout(state.updateWatchdogTimer);
    clearTimeout(state.controlRecoveryTimer);
    clearInterval(state.statusTimer);
    state.observer?.disconnect();
    state.windowObserver?.disconnect();
    state.windowObserver = null;

    if (state.controlResizeHandler) {
      window.removeEventListener(
        'resize',
        state.controlResizeHandler
      );
      state.controlResizeHandler = null;
    }

    window.removeEventListener('popstate', onRoute);
    window.removeEventListener('hashchange', onRoute);
    document.removeEventListener('visibilitychange', onVisibility);
    window.removeEventListener('storage', onStorageSync);
    try { state.channel?.close?.(); } catch (_) {}

    restoreOptimizedTurns();
    restoreToolGroups();
    state.nearTurns.clear();
    state.turnSet.clear();
    state.turnCache = [];
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
    nativeActionResult,
    toggleNativePanel,
    closeNativePanel,
    requestNativeUpdateCheck,
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
