// ==UserScript==
// @name         ChatGPT Web Unified
// @namespace    https://github.com/masakacj/chatgpt-web
// @version      0.4.0
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

  const VERSION = '0.4.0';
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
    IS_NATIVE_IOS ? 180 : 100;
  const STATUS_INTERVAL_MS =
    IS_NATIVE_IOS ? 8000 : 5000;
  const PHASE_TWO_IDLE_TIMEOUT_MS =
    IS_NATIVE_IOS ? 1200 : 700;
  const STATE_EVAL_DEBOUNCE_MS =
    IS_NATIVE_IOS ? 220 : 120;
  const IOS_KEEP_RECENT_TURNS = 6;
  const TURN_CACHE_MAX_AGE_MS =
    IS_NATIVE_IOS ? 30000 : 15000;
  const DEFAULT_AGGRESSIVE_WINDOWING = false;
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
  const TURN_ELEMENT_QUERY = [
    '[data-testid^="conversation-turn-"]',
    'article[data-scroll-anchor]',
    '[data-message-author-role]',
  ].join(',');

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
    aggressiveWindowing:
      DEFAULT_AGGRESSIVE_WINDOWING,
  };

  const state = {
    settings: loadSettings(),
    destroyed: false,
    observer: null,
    conversationObserver: null,
    sidebarObserver: null,
    conversationRoot: null,
    sidebarRoot: null,
    refreshTimer: 0,
    stateEvalTimer: 0,
    phaseTwoTimer: 0,
    phaseTwoStarted: false,
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
    processedToolHeadings: new WeakSet(),
    toolCounts: { groups: 0, collapsed: 0 },
    conversationLinks: new Map(),
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
    metrics: {
      phaseTwoStartedAt: 0,
      observerCallbacks: 0,
      conversationMutations: 0,
      sidebarMutations: 0,
      turnRefreshes: 0,
      toolNodesProcessed: 0,
      routeChanges: 0,
      longTasks: 0,
      lastLongTaskAt: 0,
    },
    longTaskObserver: null,
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
        showControl:
          shouldRestoreControl
            ? true
            : stored.showControl !== false,
        aggressiveWindowing:
          stored.aggressiveWindowing === true,
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
    renderConversationStateForId(id);

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
    renderConversationStateForId(id);
    updateUI(currentTurnCount());
  }

  function registerConversationLinks(
    scope = document
  ) {
    for (
      const item of
        ChatGPTDOMAdapter
          .conversationItems(scope)
    ) {
      const id =
        ChatGPTDOMAdapter
          .conversationIdForItem(item);

      if (!id) continue;

      let links =
        state.conversationLinks.get(id);

      if (!links) {
        links = new Set();
        state.conversationLinks.set(
          id,
          links
        );
      }

      links.add(item);
    }
  }

  function renderConversationStateForId(id) {
    if (!id) return;

    const links =
      state.conversationLinks.get(id);

    if (!links) return;

    const status =
      state.conversationStates[id]?.status;

    for (const item of Array.from(links)) {
      if (
        !(item instanceof Element) ||
        !item.isConnected
      ) {
        links.delete(item);
        continue;
      }

      if (
        shouldRenderConversationState(
          id,
          status
        )
      ) {
        item.setAttribute(
          'data-cgpt-safari-chat-state',
          status
        );
      } else {
        item.removeAttribute(
          'data-cgpt-safari-chat-state'
        );
      }
    }

    if (!links.size) {
      state.conversationLinks.delete(id);
    }
  }

  function renderConversationStates(
    scope = null
  ) {
    if (scope) {
      registerConversationLinks(scope);
    } else if (
      state.conversationLinks.size === 0
    ) {
      registerConversationLinks(
        ChatGPTDOMAdapter.sidebarRoot() ||
        document
      );
    }

    for (
      const id of
        state.conversationLinks.keys()
    ) {
      renderConversationStateForId(id);
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

    if (!waiting && !running) {
      finalizeTrackedToolGroups();
    }

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

  const ChatGPTDOMAdapter =
    Object.freeze({
      conversationRoot() {
        return (
          document.querySelector('main') ||
          document.querySelector(
            '[role="main"]'
          )
        );
      },

      sidebarRoot() {
        return (
          document.querySelector('aside') ||
          document.querySelector(
            'nav[aria-label]'
          ) ||
          document.querySelector('nav')
        );
      },

      mountedTurns() {
        const root =
          this.conversationRoot() ||
          document;

        for (const selector of TURN_SELECTORS) {
          const localSelector =
            selector.startsWith('main ')
              ? selector.slice(5)
              : selector;

          const nodes =
            Array.from(
              root.querySelectorAll(
                localSelector
              )
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
      },

      turnFromNode(node) {
        if (!(node instanceof Element)) {
          return null;
        }

        const primarySelector = [
          '[data-testid^="conversation-turn-"]',
          'article[data-scroll-anchor]',
        ].join(',');

        if (node.matches(primarySelector)) {
          return node;
        }

        const primary =
          node.closest(primarySelector);

        if (primary) return primary;

        if (
          node.matches(
            '[data-message-author-role]'
          )
        ) {
          return node;
        }

        return node.closest(
          '[data-message-author-role]'
        );
      },

      activeTurn() {
        const turns = turnCandidates();
        return turns.length
          ? turns[turns.length - 1]
          : null;
      },

      conversationItems(scope) {
        const root =
          scope instanceof Element ||
          scope instanceof Document
            ? scope
            : document;

        const result = [];

        if (
          root instanceof Element &&
          root.matches(
            'a[href*="/c/"],' +
            '[data-conversation-id]'
          )
        ) {
          result.push(root);
        }

        result.push(
          ...root.querySelectorAll(
            'a[href*="/c/"],' +
            '[data-conversation-id]'
          )
        );

        return result;
      },

      conversationIdForItem(node) {
        if (!(node instanceof Element)) {
          return null;
        }

        const explicit =
          node.getAttribute(
            'data-conversation-id'
          );

        if (explicit) return explicit;

        const href =
          node instanceof HTMLAnchorElement
            ? node.href
            : node.getAttribute('href');

        return href
          ? conversationIdFromHref(href)
          : null;
      },

      streamingSignal() {
        const root =
          this.conversationRoot() ||
          document;

        return Boolean(
          root.querySelector([
            '[data-testid="stop-button"]',
            'button[data-testid*="stop"]',
            'button[aria-label*="Stop"]',
            'button[aria-label*="停止"]',
            'button[aria-label*="Cancel"]',
            'button[aria-label*="取消"]',
          ].join(','))
        );
      },
    });

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
      '[data-cgpt-safari-chat-state] { position: relative !important; }',
      '[data-cgpt-safari-chat-state]::after { content: ""; position: absolute; right: 30px; top: 50%; width: 7px; height: 7px; margin-top: -3.5px; border-radius: 50%; pointer-events: none; }',
      '[data-cgpt-safari-chat-state="running"]::after { background: #34c759; animation: cgpt-safari-pulse 1.15s ease-in-out infinite; }',
      '[data-cgpt-safari-chat-state="waiting_user"]::after { background: #ff9f0a; }',
      '[data-cgpt-safari-chat-state="settling"]::after { background: #8e8e93; animation: cgpt-safari-pulse .9s ease-in-out infinite; }',
      '[data-cgpt-safari-chat-state="completed_unread"]::after { background: #0a84ff; }',
      '@keyframes cgpt-safari-pulse { 0%,100% { opacity: .45; transform: scale(.82); } 50% { opacity: 1; transform: scale(1.12); } }',
      '@media print {',
      '  #' + HOST_ID + ' { display: none !important; }',
      '}',
    ].join('\n');

    (document.head || document.documentElement).appendChild(style);
  }

  function collectTurnCandidates() {
    return ChatGPTDOMAdapter
      .mountedTurns();
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
              state.settings.aggressiveWindowing &&
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

      if (
        state.settings.aggressiveWindowing
      ) {
        ensureWindowObserver();
        state.windowObserver?.observe(turn);
      }
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
    state.metrics.turnRefreshes += 1;

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

  function updateToolCounts() {
    let groups = 0;
    let collapsed = 0;

    for (
      const group of
        Array.from(state.toolGroups)
    ) {
      if (
        !(group instanceof HTMLElement) ||
        !group.isConnected
      ) {
        state.toolGroups.delete(group);
        continue;
      }

      groups += 1;

      if (
        group.hasAttribute(
          'data-cgpt-tool-collapsed'
        )
      ) {
        collapsed += 1;
      }
    }

    state.toolCounts = {
      groups,
      collapsed,
    };
  }

  function registerToolGroup(
    group,
    turn,
    liveTurn = null
  ) {
    if (!(group instanceof HTMLElement)) {
      return;
    }

    state.toolGroups.add(group);
    group.setAttribute(
      'data-cgpt-tool-group',
      '1'
    );

    const active =
      turn === liveTurn ||
      toolGroupNeedsAttention(group) ||
      group.matches(':focus-within');

    if (active) {
      group.removeAttribute(
        'data-cgpt-tool-collapsed'
      );
      group.removeAttribute(
        'data-cgpt-tool-summary'
      );
    } else {
      group.setAttribute(
        'data-cgpt-tool-collapsed',
        '1'
      );
      group.setAttribute(
        'data-cgpt-tool-summary',
        toolSummary(group)
      );
    }
  }

  function toolHeadingsInScope(scope) {
    if (!(scope instanceof Element)) {
      return [];
    }

    const selector =
      'button,[role="button"],' +
      'summary,[aria-expanded]';
    const result = [];

    if (
      scope.matches(selector) &&
      TOOL_GROUP_RE.test(
        nodeLabel(scope)
      )
    ) {
      result.push(scope);
    }

    for (
      const node of
        scope.querySelectorAll(selector)
    ) {
      if (
        TOOL_GROUP_RE.test(
          nodeLabel(node)
        )
      ) {
        result.push(node);
      }
    }

    return result;
  }

  function processToolMutationNode(node) {
    if (
      !state.settings.enabled ||
      !(node instanceof Element)
    ) {
      return;
    }

    state.metrics.toolNodesProcessed += 1;
    let changed = false;

    const turn =
      ChatGPTDOMAdapter.turnFromNode(node);

    if (!(turn instanceof HTMLElement)) {
      return;
    }

    const liveTurn =
      isStreaming()
        ? ChatGPTDOMAdapter.activeTurn()
        : null;

    for (
      const heading of
        toolHeadingsInScope(node)
    ) {
      if (
        state.processedToolHeadings
          .has(heading)
      ) {
        continue;
      }

      const group =
        findToolGroupContainer(
          heading,
          turn
        );

      if (!(group instanceof HTMLElement)) {
        continue;
      }

      state.processedToolHeadings
        .add(heading);

      registerToolGroup(
        group,
        turn,
        liveTurn
      );
      changed = true;
    }

    if (changed) {
      updateToolCounts();
    }
  }

  function finalizeTrackedToolGroups() {
    if (!state.settings.enabled) {
      return;
    }

    const activeTurn =
      ChatGPTDOMAdapter.activeTurn();

    if (!(activeTurn instanceof HTMLElement)) {
      return;
    }

    const liveTurn =
      isStreaming()
        ? activeTurn
        : null;
    let changed = false;

    for (
      const group of
        Array.from(state.toolGroups)
    ) {
      if (
        !(group instanceof HTMLElement) ||
        !group.isConnected
      ) {
        state.toolGroups.delete(group);
        changed = true;
        continue;
      }

      if (!activeTurn.contains(group)) {
        continue;
      }

      registerToolGroup(
        group,
        activeTurn,
        liveTurn
      );
      changed = true;
    }

    if (changed) {
      updateToolCounts();
    }
  }

  function restoreToolGroups() {
    for (
      const group of
        Array.from(state.toolGroups)
    ) {
      if (!(group instanceof HTMLElement)) {
        continue;
      }

      group.removeAttribute(
        'data-cgpt-tool-group'
      );
      group.removeAttribute(
        'data-cgpt-tool-collapsed'
      );
      group.removeAttribute(
        'data-cgpt-tool-summary'
      );
    }

    state.toolGroups.clear();
    state.toolCounts = {
      groups: 0,
      collapsed: 0,
    };
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

  function applyAggressiveWindowing(
    turns,
    liveTurn
  ) {
    ensureWindowObserver();

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

    for (const turn of turns) {
      if (
        !(turn instanceof HTMLElement) ||
        protectedTurns.includes(turn) ||
        turn === liveTurn ||
        state.nearTurns.has(turn)
      ) {
        continue;
      }

      const protectedSet =
        new Set(protectedTurns);

      if (
        canWindowTurn(
          turn,
          protectedSet,
          liveTurn
        )
      ) {
        windowTurn(turn);
      }
    }
  }

  function applyPerformanceHints() {
    const turns = turnCandidates();

    if (!state.settings.enabled) {
      restoreOptimizedTurns();
      restoreToolGroups();
      updateUI(turns.length);
      return;
    }

    const streaming = isStreaming();
    const liveTurn =
      streaming && turns.length
        ? turns[turns.length - 1]
        : null;

    if (
      state.settings.aggressiveWindowing
    ) {
      applyAggressiveWindowing(
        turns,
        liveTurn
      );
    } else if (
      state.optimizedTurns.size > 0
    ) {
      restoreOptimizedTurns();
    }

    updateToolCounts();
    updateUI(turns.length);
  }

  function isStreaming() {
    return ChatGPTDOMAdapter
      .streamingSignal();
  }

  function scheduleRefresh(
    delay = PERF_REFRESH_DELAY_MS
  ) {
    if (state.destroyed) return;
    clearTimeout(state.refreshTimer);
    state.refreshTimer = window.setTimeout(() => {
      if (state.destroyed) return;
      if (routeChanged()) {
        onRoute();
        return;
      }

      window.requestAnimationFrame(
        applyPerformanceHints
      );
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
    perfLabel.textContent = '低干扰增量优化';
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

[Showing lines 1-2000 of 3444. Use offset=2001 to continue.]