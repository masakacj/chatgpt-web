// ==UserScript==
// @name         ChatGPT Web Unified
// @namespace    https://github.com/masakacj/chatgpt-web
// @version      0.4.9
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

  const VERSION = '0.4.9';
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
  const EXTREME_NATIVE_MODE =
    IS_NATIVE_IOS;
  const NATIVE_PASSIVE_RECENT_TURNS = 4;
  const INITIAL_BOTTOM_SCROLL_DELAYS = [
    0,
    700,
  ];
  const PERF_REFRESH_DELAY_MS =
    IS_NATIVE_IOS ? 180 : 100;
  const STATUS_INTERVAL_MS =
    IS_NATIVE_IOS ? 12000 : 7000;
  const PHASE_TWO_IDLE_TIMEOUT_MS =
    IS_NATIVE_IOS ? 4000 : 1200;
  const ROUTE_SETTLE_DELAY_MS =
    IS_NATIVE_IOS ? 1400 : 500;
  const STATE_EVAL_DEBOUNCE_MS =
    IS_NATIVE_IOS ? 220 : 120;
  const IOS_KEEP_RECENT_TURNS = 6;
  const TURN_CACHE_MAX_AGE_MS =
    IS_NATIVE_IOS ? 300000 : 120000;
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
  const SAFE_LOAD_MIGRATION_KEY = 'cgpt-safe-load-v041';
  const CONTROL_POSITION_KEY =
    'cgpt-unified-control-position-v1';
  const NATIVE_ANCHOR_MIN_VERSION =
    '0.3.31';
  const CONVERSATION_STATE_KEY = 'cgpt-safari-conversation-state-v1';
  const STATE_CHANNEL = 'cgpt-safari-conversation-state';
  const SETTLE_MS = 2800;
  const READ_DWELL_MS = 1200;
  const STATE_TTL_MS = 14 * 24 * 60 * 60 * 1000;

  const TELEMETRY_ENDPOINT =
    'https://chatgpt-web-telemetry.masakacj.workers.dev/v1/telemetry';
  const TELEMETRY_CONFIG_URL =
    'https://chatgpt-web-telemetry.masakacj.workers.dev/v1/config';
  const TELEMETRY_INSTALL_KEY =
    'cgpt-telemetry-install-v1';
  const TELEMETRY_QUEUE_MAX = 60;
  const TELEMETRY_DEFAULTS =
    Object.freeze({
      sampleMs: 15000,
      loopProbeMs: 1000,
      flushMs: 30000,
      maxBatch: 20,
      debugDurationMs: 180000,
    });

  const TOOL_GROUP_RE = /(?:已调用工具|工具调用列表|调用工具|Called tools?|Tool calls?|Tools called|MCP|connector|连接器)/i;
  const TOOL_ACTION_RE = /(?:Ran command|Run command|Called tool|Searched|Read file|Wrote file|Edited file|Opened workspace|Fetched|Executed|运行命令|执行命令|调用工具|搜索|读取文件|写入文件|编辑文件|打开工作区|已运行|已调用)/i;
  const PROCESS_GROUP_RE = /(?:Thought for|Thinking|Reasoning|思考过程|思考了|正在思考|分析中)/i;
  const TOOL_ATTENTION_RE = /(?:running|in progress|pending|waiting|failed|error|approval|required|confirm|permission|正在|执行中|等待|失败|错误|需要确认|确认操作|授权|权限)/i;
  const TOOL_USER_ACTION_RE = /(?:allow|approve|confirm|yes,?\s*(?:run|proceed)|run\s+(?:it|command)|continue|permission|authorization|允许|批准|确认|继续|运行此|授权|权限)/i;

  try {
    window[GLOBAL_KEY]?.destroy?.();
    window[LEGACY_GLOBAL_KEY]?.destroy?.();
  } catch (_) {}

  const defaults = {
    enabled: true,
    showControl: true,
    aggressiveWindowing:
      DEFAULT_AGGRESSIVE_WINDOWING,
    telemetryEnabled: false,
  };

  const state = {
    settings: loadSettings(),
    destroyed: false,
    observer: null,
    conversationObserver: null,
    sidebarObserver: null,
    sidebarReconcileTimer: 0,
    bottomScrollTimers: new Set(),
    lastBottomConversationId: '',
    conversationRoot: null,
    sidebarRoot: null,
    refreshTimer: 0,
    stateEvalTimer: 0,
    phaseTwoTimer: 0,
    routeRebindTimer: 0,
    routeSettlingUntil: 0,
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
    telemetry: createTelemetryState(),
  };

  function clamp(value, min, max) {
    const n = Number(value);
    return Math.min(max, Math.max(min, Number.isFinite(n) ? n : min));
  }

  function randomTelemetryId(
    prefix,
    bytes = 8
  ) {
    try {
      const data =
        new Uint8Array(bytes);
      crypto.getRandomValues(data);

      return (
        prefix +
        Array.from(data)
          .map((value) =>
            value
              .toString(16)
              .padStart(2, '0')
          )
          .join('')
      );
    } catch (_) {
      return (
        prefix +
        Math.random()
          .toString(36)
          .slice(2, 18)
      );
    }
  }

  function loadOrCreateTelemetryInstallId() {
    try {
      const existing =
        localStorage.getItem(
          TELEMETRY_INSTALL_KEY
        );

      if (
        existing &&
        /^[A-Za-z0-9_-]{8,64}$/
          .test(existing)
      ) {
        return existing;
      }

      const next =
        randomTelemetryId(
          'i_',
          10
        );

      localStorage.setItem(
        TELEMETRY_INSTALL_KEY,
        next
      );

      return next;
    } catch (_) {
      return randomTelemetryId(
        'i_',
        10
      );
    }
  }

  function emptyLagBucket() {
    return {
      count: 0,
      sum: 0,
      max: 0,
      gt50: 0,
      gt100: 0,
      gt250: 0,
    };
  }

  function emptyCostBucket() {
    return {
      conversationObserverMs: 0,
      sidebarObserverMs: 0,
      turnScanMs: 0,
      toolProcessMs: 0,
    };
  }

  function createTelemetryState() {
    return {
      installId:
        loadOrCreateTelemetryInstallId(),
      sessionId:
        randomTelemetryId(
          's_',
          10
        ),
      config: {
        ...TELEMETRY_DEFAULTS,
      },
      configStatus: 'idle',
      status: 'off',
      transport: 'none',
      queue: [],
      uploadInFlight: false,
      activeBatch: null,
      uploadTimer: 0,
      sampleTimer: 0,
      flushTimer: 0,
      loopTimer: 0,
      debugTimer: 0,
      rafId: 0,
      debugId: '',
      debugUntil: 0,
      lastUploadAt: 0,
      lastError: '',
      lastCounters: null,
      loop: emptyLagBucket(),
      raf: emptyLagBucket(),
      costs: emptyCostBucket(),
    };
  }

  function telemetryRouteKind() {
    if (currentConversationId()) {
      return 'conversation';
    }

    if (
      location.pathname === '/' ||
      location.pathname === ''
    ) {
      return 'home';
    }

    return 'other';
  }

  function telemetryCounters() {
    return {
      observerCallbacks:
        state.metrics.observerCallbacks,
      conversationMutations:
        state.metrics
          .conversationMutations,
      sidebarMutations:
        state.metrics.sidebarMutations,
      turnRefreshes:
        state.metrics.turnRefreshes,
      toolNodesProcessed:
        state.metrics
          .toolNodesProcessed,
    };
  }

  function telemetryCounterDelta(
    current,
    previous,
    key
  ) {
    return Math.max(
      0,
      Number(current?.[key] || 0) -
      Number(previous?.[key] || 0)
    );
  }

  function recordTelemetryCost(
    key,
    duration
  ) {
    if (
      !state.settings.telemetryEnabled ||
      !Number.isFinite(duration) ||
      duration < 0
    ) {
      return;
    }

    if (
      Object.hasOwn(
        state.telemetry.costs,
        key
      )
    ) {
      state.telemetry.costs[key] +=
        duration;
    }
  }

  async function loadTelemetryConfig() {
    const telemetry = state.telemetry;

    if (
      telemetry.configStatus ===
        'loading' ||
      telemetry.configStatus ===
        'ready'
    ) {
      return telemetry.config;
    }

    telemetry.configStatus = 'loading';
    updateTelemetryUI();

    try {
      const response = await fetch(
        TELEMETRY_CONFIG_URL,
        {
          cache: 'no-store',
          credentials: 'omit',
        }
      );

      if (!response.ok) {
        throw new Error(
          'config_http_' +
          response.status
        );
      }

      const body = await response.json();
      const remote =
        body?.telemetry || {};

      telemetry.config = {
        sampleMs: clamp(
          remote.sampleMs,
          5000,
          60000
        ) ||
          TELEMETRY_DEFAULTS.sampleMs,
        loopProbeMs: clamp(
          remote.loopProbeMs,
          500,
          5000
        ) ||
          TELEMETRY_DEFAULTS.loopProbeMs,
        flushMs: clamp(
          remote.flushMs,
          5000,
          120000
        ) ||
          TELEMETRY_DEFAULTS.flushMs,
        maxBatch: clamp(
          remote.maxBatch,
          1,
          20
        ) ||
          TELEMETRY_DEFAULTS.maxBatch,
        debugDurationMs: clamp(
          remote.debugDurationMs,
          30000,
          600000
        ) ||
          TELEMETRY_DEFAULTS
            .debugDurationMs,
      };

      telemetry.configStatus = 'ready';
    } catch (_) {
      telemetry.config = {
        ...TELEMETRY_DEFAULTS,
      };
      telemetry.configStatus = 'fallback';
    }

    restartTelemetryTimers();
    updateTelemetryUI();

    return telemetry.config;
  }

  function updateLagBucket(
    bucket,
    lag
  ) {
    if (
      !bucket ||
      !Number.isFinite(lag) ||
      lag < 0
    ) {
      return;
    }

    bucket.count += 1;
    bucket.sum += lag;
    bucket.max = Math.max(
      bucket.max,
      lag
    );

    if (lag > 50) bucket.gt50 += 1;
    if (lag > 100) bucket.gt100 += 1;
    if (lag > 250) bucket.gt250 += 1;
  }

  function startLoopProbe() {
    const telemetry = state.telemetry;

    clearTimeout(
      telemetry.loopTimer
    );

    let expected =
      performance.now() +
      telemetry.config.loopProbeMs;

    const tick = () => {
      if (
        state.destroyed ||
        !state.settings.telemetryEnabled
      ) {
        telemetry.loopTimer = 0;
        return;
      }

      const now = performance.now();

      if (!document.hidden) {
        updateLagBucket(
          telemetry.loop,
          Math.max(
            0,
            now - expected
          )
        );
      }

      expected =
        now +
        telemetry.config.loopProbeMs;

      telemetry.loopTimer =
        window.setTimeout(
          tick,
          telemetry.config.loopProbeMs
        );
    };

    telemetry.loopTimer =
      window.setTimeout(
        tick,
        telemetry.config.loopProbeMs
      );
  }

  function stopDebugRafProbe() {
    if (state.telemetry.rafId) {
      cancelAnimationFrame(
        state.telemetry.rafId
      );
      state.telemetry.rafId = 0;
    }
  }

  function startDebugRafProbe() {
    stopDebugRafProbe();

    let previous = 0;

    const frame = (timestamp) => {
      const telemetry = state.telemetry;

      if (
        state.destroyed ||
        !telemetry.debugId
      ) {
        telemetry.rafId = 0;
        return;
      }

      if (
        previous > 0 &&
        !document.hidden
      ) {
        updateLagBucket(
          telemetry.raf,
          Math.max(
            0,
            timestamp - previous
          )
        );
      }

      previous = timestamp;
      telemetry.rafId =
        requestAnimationFrame(frame);
    };

    state.telemetry.rafId =
      requestAnimationFrame(frame);
  }

  function telemetrySample(
    reason = 'interval'
  ) {
    const telemetry = state.telemetry;
    const current =
      telemetryCounters();
    const previous =
      telemetry.lastCounters ||
      current;

    telemetry.lastCounters = current;

    const loop =
      telemetry.loop;
    const raf =
      telemetry.raf;
    const costs =
      telemetry.costs;

    const sample = {
      mode:
        telemetry.debugId
          ? 'debug'
          : 'metrics',
      debugId:
        telemetry.debugId || '',
      routeKind:
        telemetryRouteKind(),
      reason:
        String(reason).slice(0, 24),
      aggressive:
        state.settings
          .aggressiveWindowing,
      streaming:
        isStreaming(),
      phaseTwo:
        state.phaseTwoStarted,
      uptimeMs:
        Math.round(
          performance.now()
        ),
      mountedTurns:
        state.turnCache.length,
      observerCallbacks:
        telemetryCounterDelta(
          current,
          previous,
          'observerCallbacks'
        ),
      conversationMutations:
        telemetryCounterDelta(
          current,
          previous,
          'conversationMutations'
        ),
      sidebarMutations:
        telemetryCounterDelta(
          current,
          previous,
          'sidebarMutations'
        ),
      turnRefreshes:
        telemetryCounterDelta(
          current,
          previous,
          'turnRefreshes'
        ),
      toolNodesProcessed:
        telemetryCounterDelta(
          current,
          previous,
          'toolNodesProcessed'
        ),
      toolGroups:
        state.toolCounts.groups,
      toolCollapsed:
        state.toolCounts.collapsed,
      loopCount:
        loop.count,
      loopAvgMs:
        loop.count
          ? loop.sum / loop.count
          : 0,
      loopMaxMs:
        loop.max,
      loopGt50:
        loop.gt50,
      loopGt100:
        loop.gt100,
      loopGt250:
        loop.gt250,
      rafCount:
        raf.count,
      rafMaxMs:
        raf.max,
      rafGt50:
        raf.gt50,
      rafGt100:
        raf.gt100,
      rafGt250:
        raf.gt250,
      conversationObserverMs:
        costs.conversationObserverMs,
      sidebarObserverMs:
        costs.sidebarObserverMs,
      turnScanMs:
        costs.turnScanMs,
      toolProcessMs:
        costs.toolProcessMs,
    };

    telemetry.loop =
      emptyLagBucket();
    telemetry.raf =
      emptyLagBucket();
    telemetry.costs =
      emptyCostBucket();

    return sample;
  }

  function queueTelemetrySample(
    reason = 'interval'
  ) {
    if (
      !state.settings.telemetryEnabled
    ) {
      return;
    }

    const telemetry = state.telemetry;

    telemetry.queue.push(
      telemetrySample(reason)
    );

    if (
      telemetry.queue.length >
      TELEMETRY_QUEUE_MAX
    ) {
      telemetry.queue.splice(
        0,
        telemetry.queue.length -
        TELEMETRY_QUEUE_MAX
      );
    }

    if (
      telemetry.queue.length >=
      Math.min(
        4,
        telemetry.config.maxBatch
      )
    ) {
      flushTelemetry();
    }

    updateTelemetryUI();
  }

  function completeTelemetryUpload(
    ok,
    batchId,
    detail = ''
  ) {
    const telemetry = state.telemetry;
    const active =
      telemetry.activeBatch;

    if (
      !active ||
      active.id !== batchId
    ) {
      return;
    }

    clearTimeout(
      telemetry.uploadTimer
    );
    telemetry.uploadTimer = 0;

    if (ok) {
      telemetry.queue.splice(
        0,
        active.count
      );
      telemetry.lastUploadAt =
        Date.now();
      telemetry.status =
        telemetry.debugId
          ? 'debug'
          : 'metrics';
      telemetry.lastError = '';
    } else {
      telemetry.status = 'error';
      telemetry.lastError =
        String(detail || 'upload_failed')
          .slice(0, 64);
    }

    telemetry.activeBatch = null;
    telemetry.uploadInFlight = false;
    updateTelemetryUI();

    if (
      ok &&
      telemetry.queue.length
    ) {
      window.setTimeout(
        () => flushTelemetry(),
        250
      );
    }
  }

  function nativeTelemetryResult(
    result
  ) {
    if (
      !result ||
      result.type !== 'telemetry'
    ) {
      return false;
    }

    completeTelemetryUpload(
      result.ok === true,
      String(result.batchId || ''),
      result.status || ''
    );

    return true;
  }

  async function directTelemetryUpload(
    payload,
    batchId
  ) {
    try {
      const response = await fetch(
        TELEMETRY_ENDPOINT,
        {
          method: 'POST',
          mode: 'cors',
          cache: 'no-store',
          credentials: 'omit',
          keepalive: true,
          headers: {
            'Content-Type':
              'application/json',
            'X-ChatGPT-Web-Telemetry':
              '1',
          },
          body: JSON.stringify(payload),
        }
      );

      completeTelemetryUpload(
        response.ok,
        batchId,
        'http_' + response.status
      );
    } catch (error) {
      completeTelemetryUpload(
        false,
        batchId,
        error?.name || 'fetch_error'
      );
    }
  }

  function flushTelemetry() {
    const telemetry = state.telemetry;

    if (
      !state.settings.telemetryEnabled ||
      telemetry.uploadInFlight ||
      telemetry.queue.length === 0
    ) {
      return;
    }

    const count =
      Math.min(
        telemetry.queue.length,
        telemetry.config.maxBatch
      );
    const batchId =
      randomTelemetryId(
        'b_',
        6
      );
    const samples =
      telemetry.queue
        .slice(0, count);

    const payload = {
      schema: 1,
      installId:
        telemetry.installId,
      sessionId:
        telemetry.sessionId,
      scriptVersion:
        VERSION,
      appVersion:
        state.nativeStatus?.appVersion ||
        '',
      gestureVersion:
        state.nativeStatus
          ?.gestureVersion ||
        '',
      samples,
    };

    telemetry.uploadInFlight = true;
    telemetry.activeBatch = {
      id: batchId,
      count,
    };
    telemetry.status = 'uploading';

    const handler =
      window.webkit?.messageHandlers
        ?.chatGPTNative;

    if (
      IS_NATIVE_IOS &&
      state.nativeStatus
        ?.telemetryTransport === true &&
      handler?.postMessage
    ) {
      telemetry.transport = 'native';

      handler.postMessage({
        type: 'telemetry',
        batchId,
        payload,
      });

      telemetry.uploadTimer =
        window.setTimeout(() => {
          completeTelemetryUpload(
            false,
            batchId,
            'native_timeout'
          );
        }, 15000);

      updateTelemetryUI();
      return;
    }

    telemetry.transport = 'fetch';
    updateTelemetryUI();

    directTelemetryUpload(
      payload,
      batchId
    );
  }

  function restartTelemetryTimers() {
    const telemetry = state.telemetry;

    clearInterval(
      telemetry.sampleTimer
    );
    clearInterval(
      telemetry.flushTimer
    );

    telemetry.sampleTimer = 0;
    telemetry.flushTimer = 0;

    if (
      !state.settings.telemetryEnabled
    ) {
      return;
    }

    telemetry.sampleTimer =
      window.setInterval(() => {
        queueTelemetrySample(
          'interval'
        );
      }, telemetry.config.sampleMs);

    telemetry.flushTimer =
      window.setInterval(() => {
        flushTelemetry();
      }, telemetry.config.flushMs);

    startLoopProbe();
  }

  function stopTelemetryRuntime(
    clearQueue = false
  ) {
    const telemetry = state.telemetry;

    clearInterval(
      telemetry.sampleTimer
    );
    clearInterval(
      telemetry.flushTimer
    );
    clearTimeout(
      telemetry.loopTimer
    );
    clearTimeout(
      telemetry.debugTimer
    );
    clearTimeout(
      telemetry.uploadTimer
    );

    telemetry.sampleTimer = 0;
    telemetry.flushTimer = 0;
    telemetry.loopTimer = 0;
    telemetry.debugTimer = 0;
    telemetry.uploadTimer = 0;

    stopDebugRafProbe();

    telemetry.debugId = '';
    telemetry.debugUntil = 0;
    telemetry.status = 'off';

    if (clearQueue) {
      telemetry.queue = [];
      telemetry.activeBatch = null;
      telemetry.uploadInFlight = false;
    }

    updateTelemetryUI();
  }

  function startTelemetryRuntime() {
    if (
      !state.settings.telemetryEnabled
    ) {
      return;
    }

    const telemetry = state.telemetry;

    telemetry.status =
      telemetry.debugId
        ? 'debug'
        : 'connecting';
    telemetry.lastCounters =
      telemetryCounters();

    restartTelemetryTimers();
    loadTelemetryConfig();
    queueTelemetrySample(
      'telemetry_on'
    );
    flushTelemetry();
    updateTelemetryUI();
  }

  function setTelemetryEnabled(
    value
  ) {
    state.settings.telemetryEnabled =
      Boolean(value);
    saveSettings();

    if (
      state.ui?.telemetrySwitch
    ) {
      state.ui.telemetrySwitch.checked =
        state.settings.telemetryEnabled;
    }

    if (
      state.settings.telemetryEnabled
    ) {
      startTelemetryRuntime();
    } else {
      stopTelemetryRuntime(true);
    }
  }

  function startDebugSession() {
    if (
      !state.settings.telemetryEnabled
    ) {
      setTelemetryEnabled(true);
    }

    const telemetry = state.telemetry;

    if (telemetry.debugId) {
      return telemetry.debugId;
    }

    telemetry.debugId =
      randomTelemetryId(
        'D_',
        5
      ).toUpperCase();
    telemetry.debugUntil =
      Date.now() +
      telemetry.config
        .debugDurationMs;
    telemetry.status = 'debug';

    startDebugRafProbe();
    queueTelemetrySample(
      'debug_start'
    );

    clearTimeout(
      telemetry.debugTimer
    );
    telemetry.debugTimer =
      window.setTimeout(() => {
        stopDebugSession();
      }, telemetry.config.debugDurationMs);

    updateTelemetryUI();

    return telemetry.debugId;
  }

  function stopDebugSession() {
    const telemetry = state.telemetry;

    if (!telemetry.debugId) {
      return '';
    }

    const finishedId =
      telemetry.debugId;

    queueTelemetrySample(
      'debug_end'
    );
    flushTelemetry();

    telemetry.debugId = '';
    telemetry.debugUntil = 0;
    telemetry.status = 'metrics';

    clearTimeout(
      telemetry.debugTimer
    );
    telemetry.debugTimer = 0;

    stopDebugRafProbe();
    updateTelemetryUI();

    return finishedId;
  }

  function updateTelemetryUI() {
    const telemetry =
      state.telemetry;
    const ui = state.ui;

    if (!ui) return;

    if (ui.telemetrySwitch) {
      ui.telemetrySwitch.checked =
        state.settings.telemetryEnabled;
    }

    if (ui.telemetryInfo) {
      let text = '关闭';

      if (
        state.settings.telemetryEnabled
      ) {
        if (telemetry.debugId) {
          text =
            'DEBUG ' +
            telemetry.debugId;
        } else if (
          telemetry.status === 'error'
        ) {
          text = '上传失败';
        } else if (
          telemetry.status ===
            'uploading'
        ) {
          text = '上传中';
        } else if (
          telemetry.status ===
            'connecting'
        ) {
          text = '连接中';
        } else {
          text = '采集中';
        }
      }

      ui.telemetryInfo.textContent =
        text;
    }

  }

  function loadSettings() {
    try {
      const stored = JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}');
      const shouldRestoreControl = localStorage.getItem(CONTROL_MIGRATION_KEY) !== '1';
      const shouldApplySafeLoadReset =
        localStorage.getItem(SAFE_LOAD_MIGRATION_KEY) !== '1';
      if (shouldRestoreControl) {
        localStorage.setItem(CONTROL_MIGRATION_KEY, '1');
      }
      if (shouldApplySafeLoadReset) {
        localStorage.setItem(SAFE_LOAD_MIGRATION_KEY, '1');
      }
      return {
        enabled: stored.enabled !== false,
        showControl:
          shouldRestoreControl
            ? true
            : stored.showControl !== false,
        aggressiveWindowing:
          shouldApplySafeLoadReset
            ? false
            : stored.aggressiveWindowing === true,
        telemetryEnabled:
          stored.telemetryEnabled === true,
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

  function reconcileSidebarConversationLinks() {
    if (state.destroyed) return;

    const root =
      ChatGPTDOMAdapter.sidebarRoot();

    if (!(root instanceof Element)) {
      state.conversationLinks.clear();
      return;
    }

    state.sidebarRoot = root;
    state.conversationLinks.clear();

    registerConversationLinks(root);
    renderConversationStates();
  }

  function scheduleSidebarReconcile(
    delay = 80
  ) {
    if (state.destroyed) return;

    clearTimeout(
      state.sidebarReconcileTimer
    );

    state.sidebarReconcileTimer =
      window.setTimeout(() => {
        state.sidebarReconcileTimer = 0;
        reconcileSidebarConversationLinks();
      }, delay);
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
      '[data-cgpt-passive-turn="1"] {',
      '  content-visibility: auto !important;',
      '  contain-intrinsic-size: auto 320px !important;',
      '}',
      '[data-cgpt-tool-group="1"] {',
      '  content-visibility: auto !important;',
      '  contain: layout style paint !important;',
      '  contain-intrinsic-size: auto 42px !important;',
      '}',
      '[data-cgpt-tool-hidden="1"] {',
      '  display: none !important;',
      '  content-visibility: hidden !important;',
      '  contain: strict !important;',
      '  height: 0 !important;',
      '  min-height: 0 !important;',
      '  max-height: 0 !important;',
      '  margin: 0 !important;',
      '  padding: 0 !important;',
      '  overflow: hidden !important;',
      '  pointer-events: none !important;',
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
    const scanStarted = now;

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

    if (
      EXTREME_NATIVE_MODE &&
      state.settings.enabled
    ) {
      const passiveBefore =
        Math.max(
          0,
          turns.length -
            NATIVE_PASSIVE_RECENT_TURNS
        );

      for (
        let index = 0;
        index < turns.length;
        index += 1
      ) {
        const turn = turns[index];

        if (!(turn instanceof HTMLElement)) {
          continue;
        }

        if (index < passiveBefore) {
          turn.setAttribute(
            'data-cgpt-passive-turn',
            '1'
          );
        } else {
          turn.removeAttribute(
            'data-cgpt-passive-turn'
          );
        }
      }
    }

    state.turnCacheDirty = false;
    state.lastTurnScanAt = now;
    state.metrics.turnRefreshes += 1;

    recordTelemetryCost(
      'turnScanMs',
      performance.now() - scanStarted
    );

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
    let fallback = null;

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

      if (node.parentElement === turn) {
        break;
      }

      fallback ||= node;

      if (node.children.length >= 2) {
        return node;
      }

      if (
        !EXTREME_NATIVE_MODE &&
        toolActionNodes(node).length > 0
      ) {
        return node;
      }
    }

    return fallback;
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

  function toolGroupRequiresUserAction(group) {
    const nodes =
      group.querySelectorAll(
        'button,[role="button"],summary,[aria-label]'
      );

    for (const node of nodes) {
      if (
        TOOL_USER_ACTION_RE.test(
          nodeLabel(node)
        )
      ) {
        return true;
      }
    }

    return false;
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
        ) ||
        group.hasAttribute(
          'data-cgpt-tool-hidden'
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

    if (EXTREME_NATIVE_MODE) {
      const requiresAction =
        group.matches(':focus-within') ||
        toolGroupRequiresUserAction(
          group
        );

      group.removeAttribute(
        'data-cgpt-tool-collapsed'
      );
      group.removeAttribute(
        'data-cgpt-tool-summary'
      );

      if (requiresAction) {
        group.removeAttribute(
          'data-cgpt-tool-hidden'
        );
      } else {
        group.setAttribute(
          'data-cgpt-tool-hidden',
          '1'
        );
      }

      return;
    }

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
      group.removeAttribute(
        'data-cgpt-tool-hidden'
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

    const isProcessHeading = (node) => {
      const label = nodeLabel(node);

      return (
        TOOL_GROUP_RE.test(label) ||
        TOOL_ACTION_RE.test(label) ||
        PROCESS_GROUP_RE.test(label)
      );
    };

    if (
      scope.matches(selector) &&
      isProcessHeading(scope)
    ) {
      result.push(scope);
    }

    for (
      const node of
        scope.querySelectorAll(selector)
    ) {
      if (isProcessHeading(node)) {
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

    const toolStarted =
      performance.now();

    const turn =
      ChatGPTDOMAdapter.turnFromNode(node);

    if (!(turn instanceof HTMLElement)) {
      return;
    }

    const selector =
      'button,[role="button"],' +
      'summary,[aria-expanded]';

    const candidates = [];

    if (node.matches?.(selector)) {
      candidates.push(node);
    }

    if (candidates.length < 12) {
      for (
        const candidate of
          node.querySelectorAll?.(
            selector
          ) || []
      ) {
        candidates.push(candidate);
        if (candidates.length >= 12) {
          break;
        }
      }
    }

    for (const candidate of candidates) {
      const label =
        nodeLabel(candidate);

      const existing =
        candidate.closest?.(
          '[data-cgpt-tool-group="1"]'
        );

      if (
        existing &&
        TOOL_USER_ACTION_RE.test(label)
      ) {
        existing.removeAttribute(
          'data-cgpt-tool-hidden'
        );
        continue;
      }

      if (
        !TOOL_GROUP_RE.test(label) &&
        !TOOL_ACTION_RE.test(label) &&
        !PROCESS_GROUP_RE.test(label)
      ) {
        continue;
      }

      const group =
        findToolGroupContainer(
          candidate,
          turn
        );

      if (
        !(group instanceof HTMLElement) ||
        group === turn
      ) {
        continue;
      }

      group.setAttribute(
        'data-cgpt-tool-group',
        '1'
      );

      if (
        TOOL_USER_ACTION_RE.test(label)
      ) {
        group.removeAttribute(
          'data-cgpt-tool-hidden'
        );
      } else {
        group.setAttribute(
          'data-cgpt-tool-hidden',
          '1'
        );
      }
    }

    state.metrics.toolNodesProcessed +=
      candidates.length;

    recordTelemetryCost(
      'toolProcessMs',
      performance.now() - toolStarted
    );
  }

  function finalizeTrackedToolGroups() {
    if (
      EXTREME_NATIVE_MODE ||
      !state.settings.enabled
    ) {
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
        document.querySelectorAll(
          '[data-cgpt-tool-group="1"],' +
          '[data-cgpt-tool-hidden="1"],' +
          '[data-cgpt-tool-collapsed="1"]'
        )
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
      group.removeAttribute(
        'data-cgpt-tool-hidden'
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

    for (
      const turn of
        Array.from(state.turnSet)
    ) {
      if (turn instanceof HTMLElement) {
        turn.removeAttribute(
          'data-cgpt-passive-turn'
        );
      }
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

    if (
      state.settings.aggressiveWindowing
    ) {
      const streaming = isStreaming();
      const liveTurn =
        streaming && turns.length
          ? turns[turns.length - 1]
          : null;

      applyAggressiveWindowing(
        turns,
        liveTurn
      );
    } else if (
      state.optimizedTurns.size > 0
    ) {
      restoreOptimizedTurns();
    }

    if (!EXTREME_NATIVE_MODE) {
      updateToolCounts();
    }

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

  

  

  function scrollConversationToBottom() {
    if (!currentConversationId()) {
      return false;
    }

    const target =
      ChatGPTDOMAdapter.activeTurn() ||
      lastConversationTurn();

    try {
      if (
        target instanceof HTMLElement
      ) {
        target.scrollIntoView({
          block: 'end',
          inline: 'nearest',
          behavior: 'auto',
        });
        return true;
      }

      window.scrollTo(
        0,
        Math.max(
          document.body?.scrollHeight || 0,
          document.documentElement
            ?.scrollHeight || 0
        )
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  function clearInitialBottomScroll() {
    for (
      const timer of
        state.bottomScrollTimers
    ) {
      clearTimeout(timer);
    }

    state.bottomScrollTimers.clear();
  }

  function scheduleInitialBottomScroll(
    force = false
  ) {
    if (!EXTREME_NATIVE_MODE) {
      return;
    }

    const id = currentConversationId();

    if (!id) {
      clearInitialBottomScroll();
      state.lastBottomConversationId = '';
      return;
    }

    if (
      !force &&
      state.lastBottomConversationId === id
    ) {
      return;
    }

    clearInitialBottomScroll();
    state.lastBottomConversationId = id;
    for (
      const delay of
        INITIAL_BOTTOM_SCROLL_DELAYS
    ) {
      const timer =
        window.setTimeout(() => {
          state.bottomScrollTimers
            .delete(timer);

          if (
            state.destroyed ||
            currentConversationId() !== id
          ) {
            return;
          }

          window.requestAnimationFrame(
            scrollConversationToBottom
          );
        }, delay);

      state.bottomScrollTimers.add(timer);
    }
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

  async function checkAppUpdate() {
    const endpoint = state.nativeStatus?.appUpdateEndpoint;
    if (!IS_NATIVE_IOS || !endpoint) return null;
    try {
      const response = await fetch(endpoint, { cache: 'no-store' });
      if (!response.ok) return null;
      const latest = await response.json();
      const currentBuild = Number.parseInt(state.nativeStatus?.appBuild || '0', 10) || 0;
      const latestBuild = Number.parseInt(latest?.build || '0', 10) || 0;
      setNativeStatus({
        latestAppVersion: latest?.version || null,
        latestAppBuild: String(latest?.build || ''),
        appInstallURL: latest?.install_url || null,
        appUpdateAvailable: latestBuild > currentBuild,
      });
      return latest;
    } catch (_) {
      return null;
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

    const host =
      document.createElement('div');
    host.id = HOST_ID;
    host.style.position = 'fixed';
    host.style.top =
      'max(8px, env(safe-area-inset-top))';
    host.style.right = '10px';
    host.style.zIndex = '2147483646';
    host.style.pointerEvents = 'auto';

    const shadow =
      host.attachShadow({ mode: 'open' });
    const wrap =
      document.createElement('div');

    const style =
      document.createElement('style');
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
      '.panel { position: absolute; top: 42px; right: 0; width: 232px; padding: 8px; border-radius: 13px; background: rgba(28,28,30,.94); color: white; box-shadow: 0 12px 34px rgba(0,0,0,.28); backdrop-filter: blur(24px); -webkit-backdrop-filter: blur(24px); display: none; }',
      ':host([data-panel-side="left"]) .panel { left: 0; right: auto; }',
      ':host([data-panel-side="right"]) .panel { left: auto; right: 0; }',
      ':host([data-panel-vertical="up"]) .panel { top: auto; bottom: 42px; }',
      ':host([data-panel-vertical="down"]) .panel { top: 42px; bottom: auto; }',
      '.panel.open { display: block; }',
      '.view[hidden] { display: none !important; }',
      '.title-row { display: flex; align-items: center; gap: 8px; min-height: 28px; }',
      '.title { flex: 1; font-size: 12px; font-weight: 700; }',
      '.status { font-size: 10.5px; opacity: .72; margin: 2px 2px 6px; line-height: 1.35; }',
      '.info { margin: 0 0 6px; padding: 6px 8px; border-radius: 9px; background: rgba(255,255,255,.07); }',
      '.info-row { min-height: 19px; display: flex; align-items: center; justify-content: space-between; gap: 10px; font-size: 10.5px; }',
      '.info-key { opacity: .58; }',
      '.info-value { opacity: .92; text-align: right; font-variant-numeric: tabular-nums; }',
      '.row { width: 100%; min-height: 34px; display: flex; align-items: center; justify-content: space-between; gap: 9px; border-top: 1px solid rgba(255,255,255,.11); }',
      '.label { font-size: 12px; }',
      'button.action { width: 100%; border: 0; background: transparent; color: white; text-align: left; padding: 8px 2px; font-size: 12px; }',
      'button.compact { width: auto; min-width: 44px; border: 0; border-radius: 8px; padding: 5px 8px; background: rgba(255,255,255,.09); color: white; font-size: 11px; }',
      '.switch { appearance: none; -webkit-appearance: none; width: 42px; height: 24px; border-radius: 12px; background: rgba(255,255,255,.20); position: relative; transition: .15s ease; margin: 0; }',
      '.switch::after { content: ""; position: absolute; width: 20px; height: 20px; border-radius: 50%; background: white; top: 2px; left: 2px; transition: .15s ease; }',
      '.switch:checked { background: #34c759; }',
      '.switch:checked::after { transform: translateX(18px); }',
      '.foot { font-size: 10px; opacity: .48; margin: 8px 2px 1px; }',
    ].join('\n');

    const button =
      document.createElement('button');
    button.className = 'fab';
    button.type = 'button';
    button.textContent = 'S';
    button.setAttribute(
      'aria-label',
      'ChatGPT Web 控制'
    );

    const panel =
      document.createElement('div');
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

    const mainView =
      document.createElement('div');
    mainView.className = 'view';

    const settingsView =
      document.createElement('div');
    settingsView.className = 'view';
    settingsView.hidden = true;

    const title =
      document.createElement('div');
    title.className = 'title';
    title.textContent = 'ChatGPT Web';

    const status =
      document.createElement('div');
    status.className = 'status';

    const updateRow =
      document.createElement('div');
    updateRow.className = 'row';
    const update =
      document.createElement('button');
    update.type = 'button';
    update.className = 'action';
    update.textContent = '检查更新';
    updateRow.appendChild(update);

    const reloadRow =
      document.createElement('div');
    reloadRow.className = 'row';
    const reload =
      document.createElement('button');
    reload.type = 'button';
    reload.className = 'action';
    reload.textContent = '重新加载 ChatGPT';
    reloadRow.appendChild(reload);

    const settingsRow =
      document.createElement('div');
    settingsRow.className = 'row';
    const settings =
      document.createElement('button');
    settings.type = 'button';
    settings.className = 'action';
    settings.textContent = '设置';
    settingsRow.appendChild(settings);

    mainView.append(
      title,
      status,
      updateRow,
      reloadRow,
      settingsRow
    );

    const settingsTitleRow =
      document.createElement('div');
    settingsTitleRow.className =
      'title-row';

    const settingsTitle =
      document.createElement('div');
    settingsTitle.className = 'title';
    settingsTitle.textContent = '设置';

    const settingsBack =
      document.createElement('button');
    settingsBack.type = 'button';
    settingsBack.className =
      'compact';
    settingsBack.textContent = '返回';

    settingsTitleRow.append(
      settingsBack,
      settingsTitle
    );

    const info =
      document.createElement('div');
    info.className = 'info';

    const scriptInfo =
      makeInfoRow('脚本');
    const appInfo =
      makeInfoRow('容器');
    const updateInfo =
      makeInfoRow('更新');
    const telemetryInfo =
      makeInfoRow('在线诊断');
    const gestureInfo =
      state.nativeStatus?.gestureVersion
        ? makeInfoRow('iOS 手势')
        : null;

    info.append(
      scriptInfo.row,
      appInfo.row,
      updateInfo.row,
      telemetryInfo.row
    );
    if (gestureInfo) {
      info.append(gestureInfo.row);
    }

    const perfRow =
      document.createElement('label');
    perfRow.className = 'row';
    const perfLabel =
      document.createElement('span');
    perfLabel.className = 'label';
    perfLabel.textContent = '极速模式';
    const perfSwitch =
      document.createElement('input');
    perfSwitch.className = 'switch';
    perfSwitch.type = 'checkbox';
    perfSwitch.checked =
      state.settings.enabled;
    perfRow.append(
      perfLabel,
      perfSwitch
    );

    const telemetryRow =
      document.createElement('label');
    telemetryRow.className = 'row';
    const telemetryLabel =
      document.createElement('span');
    telemetryLabel.className = 'label';
    telemetryLabel.textContent =
      '匿名性能诊断';
    const telemetrySwitch =
      document.createElement('input');
    telemetrySwitch.className = 'switch';
    telemetrySwitch.type = 'checkbox';
    telemetrySwitch.checked =
      state.settings.telemetryEnabled;
    telemetryRow.append(
      telemetryLabel,
      telemetrySwitch
    );

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

    const restoreRow =
      document.createElement('div');
    restoreRow.className = 'row';
    const restore =
      document.createElement('button');
    restore.type = 'button';
    restore.className = 'action';
    restore.textContent =
      '恢复官方页面显示';
    restoreRow.appendChild(restore);

    const hideRow =
      document.createElement('div');
    hideRow.className = 'row';
    const hide =
      document.createElement('button');
    hide.type = 'button';
    hide.className = 'action';
    hide.textContent = '隐藏悬浮按钮';
    hideRow.appendChild(hide);

    settingsView.append(
      settingsTitleRow,
      info,
      perfRow,
      telemetryRow
    );

    if (IS_NATIVE_IOS) {
      settingsView.append(cacheRow);
    } else {
      settingsView.append(hideRow);
    }

    settingsView.append(restoreRow);

    const foot =
      document.createElement('div');
    foot.className = 'foot';
    foot.textContent = versionLine();

    panel.append(
      mainView,
      settingsView,
      foot
    );

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
        ) return;

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
        ) return;

        const dx =
          event.clientX - drag.startX;
        const dy =
          event.clientY - drag.startY;

        if (
          !drag.moved &&
          Math.hypot(dx, dy) < 6
        ) return;

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
      ) return;

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

    button.addEventListener(
      'click',
      () => {
        if (
          performance.now() <
          drag.suppressClickUntil
        ) return;

        const opening =
          !panel.classList.contains(
            'open'
          );

        panel.classList.toggle('open');
        panel.setAttribute(
          'aria-hidden',
          opening ? 'false' : 'true'
        );

        if (opening) {
          mainView.hidden = false;
          settingsView.hidden = true;
          updateUI(currentTurnCount());
        }
      }
    );

    settings.addEventListener(
      'click',
      () => {
        mainView.hidden = true;
        settingsView.hidden = false;
        updateUI(currentTurnCount());
      }
    );

    settingsBack.addEventListener(
      'click',
      () => {
        settingsView.hidden = true;
        mainView.hidden = false;
      }
    );

    perfSwitch.addEventListener(
      'change',
      () => {
        setEnabled(perfSwitch.checked);
      }
    );

    telemetrySwitch.addEventListener(
      'change',
      () => {
        setTelemetryEnabled(
          telemetrySwitch.checked
        );
      }
    );

    update.addEventListener(
      'click',
      async () => {
        if (
          state.nativeStatus
            ?.appUpdateAvailable &&
          state.nativeStatus
            ?.appInstallURL
        ) {
          requestNativeAction(
            'install-app-update',
            {
              url:
                state.nativeStatus
                  .appInstallURL,
            }
          );
          return;
        }

        update.disabled = true;
        update.textContent = '检查中…';

        requestNativeUpdateCheck();

        if (IS_NATIVE_IOS) {
          await checkAppUpdate();
        }

        update.disabled = false;
        updateUI(currentTurnCount());
      }
    );

    reload.addEventListener(
      'click',
      () => location.reload()
    );

    clearCache.addEventListener(
      'click',
      () => {
        clearCache.disabled = true;
        clearCache.style.opacity = '.55';
        clearCache.textContent = '清理中…';

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

    restore.addEventListener(
      'click',
      () => {
        setEnabled(false);
        perfSwitch.checked = false;
        panel.classList.remove('open');
        panel.setAttribute(
          'aria-hidden',
          'true'
        );
      }
    );

    hide.addEventListener(
      'click',
      () => {
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
      }
    );

    state.ui = {
      host,
      button,
      panel,
      mainView,
      settingsView,
      status,
      perfSwitch,
      telemetrySwitch,
      update,
      clearCache,
      foot,
      scriptInfo: scriptInfo.value,
      appInfo: appInfo.value,
      updateInfo: updateInfo.value,
      telemetryInfo:
        telemetryInfo.value,
      gestureInfo:
        gestureInfo?.value || null,
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

  function nativePanelRenderState() {
    const panel = state.ui?.panel;

    if (!(panel instanceof HTMLElement)) {
      return {
        ok: false,
        open: false,
        ready: false,
      };
    }

    const open =
      panel.classList.contains('open');

    return {
      ok: true,
      open,
      ready:
        open &&
        Boolean(
          state.ui?.update
            ?.isConnected
        ) &&
        Boolean(
          state.ui?.clearCache
            ?.isConnected
        ),
    };
  }

  function toggleNativePanel(anchor) {
    if (!nativeAnchorSupported()) {
      return {
        ok: false,
        open: false,
        ready: false,
      };
    }

    ensureControlMounted();

    const panel = state.ui?.panel;

    if (!(panel instanceof HTMLElement)) {
      return {
        ok: false,
        open: false,
        ready: false,
      };
    }

    const opening =
      !panel.classList.contains('open');

    if (!opening) {
      panel.classList.remove('open');
      panel.setAttribute(
        'aria-hidden',
        'true'
      );

      return {
        ok: true,
        open: false,
        ready: true,
      };
    }

    panel.classList.add('open');
    panel.setAttribute(
      'aria-hidden',
      'false'
    );

    if (state.ui?.mainView) {
      state.ui.mainView.hidden = false;
    }
    if (state.ui?.settingsView) {
      state.ui.settingsView.hidden = true;
    }

    positionNativePanel(anchor);

    state.nativeStatus = {
      ...state.nativeStatus,
      ...(window.__CHATGPT_NATIVE__ || {}),
    };

    updateUI(
      state.turnCache.length
    );

    return nativePanelRenderState();
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
    if (nativeTelemetryResult(result)) {
      return;
    }

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
    const chatStatus =
      id
        ? state.conversationStates[id]
            ?.status
        : null;

    if (
      chatStatus &&
      chatStatus !== 'completed_read'
    ) {
      ui.button.dataset.chatState =
        chatStatus;
    } else {
      delete ui.button.dataset.chatState;
    }

    if (ui.status) {
      ui.status.textContent =
        'v' + VERSION +
        ' · ' +
        statusLabel(chatStatus);
    }

    if (ui.scriptInfo) {
      ui.scriptInfo.textContent =
        'v' + VERSION;
    }

    if (ui.appInfo) {
      const current =
        state.nativeStatus?.appVersion
          ? 'v' +
            state.nativeStatus.appVersion
          : '浏览器';

      const latest =
        state.nativeStatus
          ?.latestAppVersion;

      ui.appInfo.textContent =
        latest &&
        state.nativeStatus
          ?.appUpdateAvailable
          ? current + ' → v' + latest
          : current;
    }

    if (ui.updateInfo) {
      ui.updateInfo.textContent =
        updateStatusLabel();
    }

    if (ui.update) {
      const scriptStatus =
        String(
          state.nativeStatus
            ?.updateStatus || ''
        );

      const checking =
        scriptStatus === 'checking';

      const failed = [
        'offline',
        'timeout',
        'error',
      ].includes(scriptStatus);

      ui.update.disabled = checking;
      ui.update.style.opacity =
        checking ? '.5' : '1';

      ui.update.textContent =
        state.nativeStatus
          ?.appUpdateAvailable
          ? '安装更新 v' +
            (
              state.nativeStatus
                ?.latestAppVersion || ''
            )
          : checking
            ? '检查更新中…'
            : failed
              ? '重试检查更新'
              : '检查更新';
    }

    if (ui.gestureInfo) {
      const version =
        state.nativeStatus
          ?.gestureVersion || '未知';

      ui.gestureInfo.textContent =
        'v' + version;
    }

    updateTelemetryUI();

    if (ui.foot) {
      ui.foot.textContent =
        versionLine();
    }
  }

  function scheduleStateEvaluation(
    delay = STATE_EVAL_DEBOUNCE_MS
  ) {
    if (state.destroyed) return;

    clearTimeout(state.stateEvalTimer);

    state.stateEvalTimer =
      window.setTimeout(() => {
        state.stateEvalTimer = 0;

        if (!state.destroyed) {
          evaluateConversationState();
        }
      }, delay);
  }

  function registerTurnsFromScope(scope) {
    if (!(scope instanceof Element)) {
      return false;
    }

    const turns = [];

    if (scope.matches(TURN_ELEMENT_QUERY)) {
      turns.push(scope);
    }

    turns.push(
      ...scope.querySelectorAll(
        TURN_ELEMENT_QUERY
      )
    );

    let found = false;

    for (const turn of turns) {
      if (!(turn instanceof HTMLElement)) {
        continue;
      }

      registerTurn(turn);
      found = true;
    }

    if (found) {
      invalidateTurnCache();
    }

    return found;
  }

  function routeChanged() {
    return (
      location.pathname +
      location.search
    ) !== state.lastRoute;
  }

  function routeIsSettling() {
    return (
      performance.now() <
      state.routeSettlingUntil
    );
  }

  function scheduleRouteRebind(
    delay = ROUTE_SETTLE_DELAY_MS
  ) {
    if (state.destroyed) return;

    clearTimeout(state.routeRebindTimer);

    const remaining =
      Math.max(
        0,
        state.routeSettlingUntil -
          performance.now()
      );

    state.routeRebindTimer =
      window.setTimeout(() => {
        state.routeRebindTimer = 0;
        state.routeSettlingUntil = 0;

        if (
          state.destroyed ||
          !state.phaseTwoStarted
        ) {
          return;
        }

        bindScopedObservers(true);
        invalidateTurnCache();
        turnCandidates(true);
        scheduleInitialBottomScroll(true);
        scheduleRefresh(120);
        scheduleStateEvaluation(180);
      }, Math.max(delay, remaining));
  }

  function handleConversationMutations(
    mutations
  ) {
    const observerStarted =
      performance.now();

    state.metrics.observerCallbacks += 1;
    state.metrics.conversationMutations +=
      mutations.length;

    if (routeChanged()) {
      recordTelemetryCost(
        'conversationObserverMs',
        performance.now() - observerStarted
      );
      onRoute();
      return;
    }

    if (routeIsSettling()) {
      recordTelemetryCost(
        'conversationObserverMs',
        performance.now() - observerStarted
      );
      scheduleRouteRebind();
      return;
    }

    let turnStructureChanged = false;
    let stateRelevant = false;

    for (const mutation of mutations) {
      const target =
        mutation.target instanceof Element
          ? mutation.target
          : mutation.target?.parentElement;

      if (
        target?.closest?.(
          TURN_ELEMENT_QUERY
        )
      ) {
        stateRelevant = true;
      }

      for (const node of mutation.removedNodes) {
        if (!(node instanceof Element)) {
          continue;
        }

        if (
          node.matches?.(TURN_ELEMENT_QUERY) ||
          node.querySelector?.(
            TURN_ELEMENT_QUERY
          )
        ) {
          invalidateTurnCache();
          turnStructureChanged = true;
          break;
        }
      }

      for (const node of mutation.addedNodes) {
        if (!(node instanceof Element)) {
          continue;
        }

        if (
          registerTurnsFromScope(node)
        ) {
          turnStructureChanged = true;
        }

        if (EXTREME_NATIVE_MODE) {
          processToolMutationNode(node);
        }

        if (
          node.matches?.(
            '[aria-busy="true"],' +
            '[role="progressbar"],' +
            '[data-state="loading"],' +
            '[data-loading="true"],' +
            '[data-testid="stop-button"]'
          )
        ) {
          stateRelevant = true;
        }
      }
    }

    if (turnStructureChanged) {
      scheduleRefresh(80);
    }

    if (
      stateRelevant ||
      turnStructureChanged
    ) {
      scheduleStateEvaluation();
    }

    recordTelemetryCost(
      'conversationObserverMs',
      performance.now() - observerStarted
    );
  }

  function handleSidebarMutations(
    mutations
  ) {
    const observerStarted =
      performance.now();

    state.metrics.observerCallbacks += 1;
    state.metrics.sidebarMutations +=
      mutations.length;

    if (routeChanged()) {
      recordTelemetryCost(
        'sidebarObserverMs',
        performance.now() - observerStarted
      );
      onRoute();
      return;
    }

    let needsReconcile = false;

    for (const mutation of mutations) {
      if (mutation.type === 'attributes') {
        needsReconcile = true;
        continue;
      }

      if (
        mutation.addedNodes.length ||
        mutation.removedNodes.length
      ) {
        needsReconcile = true;
      }

      for (const node of mutation.addedNodes) {
        if (!(node instanceof Element)) {
          continue;
        }

        registerConversationLinks(node);
        renderConversationStates(node);
      }
    }

    if (needsReconcile) {
      scheduleSidebarReconcile(60);
    }

    recordTelemetryCost(
      'sidebarObserverMs',
      performance.now() - observerStarted
    );
  }

  function bindScopedObservers(
    force = false
  ) {
    const conversationRoot =
      ChatGPTDOMAdapter.conversationRoot();

    if (
      force ||
      conversationRoot !==
        state.conversationRoot
    ) {
      state.conversationObserver
        ?.disconnect();

      state.conversationRoot =
        conversationRoot;
      state.conversationObserver = null;

      if (conversationRoot) {
        state.conversationObserver =
          new MutationObserver(
            handleConversationMutations
          );

        state.conversationObserver.observe(
          conversationRoot,
          {
            childList: true,
            subtree: true,
          }
        );

        invalidateTurnCache();
        turnCandidates(true);

        const activeTurn =
          ChatGPTDOMAdapter.activeTurn();

        if (
          EXTREME_NATIVE_MODE &&
          activeTurn
        ) {
          processToolMutationNode(
            activeTurn
          );
        }
      }
    }

    const sidebarRoot =
      ChatGPTDOMAdapter.sidebarRoot();

    if (
      force ||
      sidebarRoot !==
        state.sidebarRoot
    ) {
      state.sidebarObserver?.disconnect();

      state.sidebarRoot = sidebarRoot;
      state.sidebarObserver = null;
      state.conversationLinks.clear();

      if (sidebarRoot) {
        state.sidebarObserver =
          new MutationObserver(
            handleSidebarMutations
          );

        state.sidebarObserver.observe(
          sidebarRoot,
          {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: [
              'href',
              'data-conversation-id',
            ],
          }
        );

        reconcileSidebarConversationLinks();
      }
    }
  }

  function setupPerformanceDiagnostics() {
    if (
      typeof PerformanceObserver !==
        'function'
    ) {
      return;
    }

    try {
      const supported =
        PerformanceObserver
          .supportedEntryTypes || [];

      if (!supported.includes('longtask')) {
        return;
      }

      state.longTaskObserver =
        new PerformanceObserver(
          (list) => {
            const entries =
              list.getEntries();

            state.metrics.longTasks +=
              entries.length;

            if (entries.length) {
              state.metrics.lastLongTaskAt =
                Date.now();
            }
          }
        );

      state.longTaskObserver.observe({
        type: 'longtask',
        buffered: true,
      });
    } catch (_) {
      state.longTaskObserver = null;
    }
  }

  function setupObservers() {
    bindScopedObservers(true);
    setupPerformanceDiagnostics();

    const root =
      document.body ||
      document.documentElement;

    state.observer =
      new MutationObserver(() => {
        state.metrics.observerCallbacks += 1;

        if (
          IS_NATIVE_IOS &&
          !document.getElementById(HOST_ID)
        ) {
          scheduleControlRecovery(40);
        }

        if (routeChanged()) {
          onRoute();
          return;
        }

        if (routeIsSettling()) {
          scheduleRouteRebind();
          return;
        }

        if (
          ChatGPTDOMAdapter
            .conversationRoot() !==
            state.conversationRoot ||
          ChatGPTDOMAdapter.sidebarRoot() !==
            state.sidebarRoot
        ) {
          bindScopedObservers();
        }
      });

    state.observer.observe(root, {
      childList: true,
      subtree: false,
    });

    window.addEventListener(
      'popstate',
      onRoute,
      { passive: true }
    );
    window.addEventListener(
      'hashchange',
      onRoute,
      { passive: true }
    );
    document.addEventListener(
      'visibilitychange',
      onVisibility,
      { passive: true }
    );

    if (
      IS_NATIVE_IOS &&
      !document.getElementById(HOST_ID)
    ) {
      scheduleControlRecovery(0);
    }

    state.statusTimer =
      window.setInterval(() => {
        if (state.destroyed) return;

        if (
          IS_NATIVE_IOS &&
          !document.getElementById(HOST_ID)
        ) {
          scheduleControlRecovery(0);
        }

        if (routeChanged()) {
          onRoute();
          return;
        }

        evaluateConversationState();
        scheduleSidebarReconcile(0);
      }, STATUS_INTERVAL_MS);
  }

  function startPhaseTwoRuntime() {
    if (
      state.destroyed ||
      state.phaseTwoStarted
    ) {
      return;
    }

    state.phaseTwoStarted = true;
    state.metrics.phaseTwoStartedAt =
      Date.now();

    setupObservers();
    invalidateTurnCache();
    turnCandidates(true);
    scheduleInitialBottomScroll(true);
    scheduleRefresh(0);
    evaluateConversationState();
    renderConversationStates();

    if (state.settings.telemetryEnabled) {
      startTelemetryRuntime();
    }
  }

  function schedulePhaseTwoRuntime() {
    if (
      state.destroyed ||
      state.phaseTwoStarted
    ) {
      return;
    }

    const start = () => {
      if (!state.destroyed) {
        startPhaseTwoRuntime();
      }
    };

    if (
      typeof window.requestIdleCallback ===
        'function'
    ) {
      window.requestIdleCallback(
        start,
        {
          timeout:
            PHASE_TWO_IDLE_TIMEOUT_MS,
        }
      );
      return;
    }

    clearTimeout(state.phaseTwoTimer);
    state.phaseTwoTimer =
      window.setTimeout(
        start,
        IS_NATIVE_IOS ? 420 : 220
      );
  }

  function onRoute() {
    state.metrics.routeChanges += 1;
    state.lastRoute =
      location.pathname +
      location.search;
    state.activeConversationId = null;
    state.activeRouteSince = Date.now();
    state.settlingSince = 0;

    restoreOptimizedTurns();
    restoreToolGroups();
    state.nearTurns.clear();
    state.conversationLinks.clear();
    invalidateTurnCache();

    scheduleInitialBottomScroll(true);

    state.routeSettlingUntil =
      performance.now() +
      ROUTE_SETTLE_DELAY_MS;

    state.conversationObserver
      ?.disconnect();
    state.conversationObserver = null;
    state.conversationRoot =
      ChatGPTDOMAdapter.conversationRoot();

    if (state.phaseTwoStarted) {
      scheduleRouteRebind();
    }

    scheduleRefresh(
      ROUTE_SETTLE_DELAY_MS + 120
    );
    scheduleStateEvaluation(
      ROUTE_SETTLE_DELAY_MS + 180
    );
    renderConversationStates();

    if (state.settings.telemetryEnabled) {
      queueTelemetrySample('route');
    }
  }

  function onVisibility() {
    if (!document.hidden) {
      if (
        IS_NATIVE_IOS &&
        !document.getElementById(HOST_ID)
      ) {
        scheduleControlRecovery(0);
      }

      if (state.phaseTwoStarted) {
        bindScopedObservers();
      }

      scheduleInitialBottomScroll(false);
      scheduleRefresh(0);
      scheduleStateEvaluation(0);
      scheduleSidebarReconcile(0);
      renderConversationStates();
    }
  }

  function showControl() {
    state.settings.showControl = true;
    saveSettings();
    createControl();
  }

  function setEnabled(value) {
    state.settings.enabled =
      Boolean(value);
    saveSettings();

    if (state.ui) {
      state.ui.perfSwitch.checked =
        state.settings.enabled;
    }

    if (!state.settings.enabled) {
      restoreOptimizedTurns();
      restoreToolGroups();
    }

    scheduleRefresh(0);
  }

  function setAggressiveWindowing(
    value
  ) {
    state.settings.aggressiveWindowing =
      Boolean(value);
    saveSettings();

    if (
      !state.settings.aggressiveWindowing
    ) {
      restoreOptimizedTurns();
      state.windowObserver?.disconnect();
      state.windowObserver = null;
      state.nearTurns.clear();
    } else {
      invalidateTurnCache();
      ensureWindowObserver();

      for (
        const turn of
          turnCandidates(true)
      ) {
        state.windowObserver?.observe(
          turn
        );
      }
    }

    scheduleRefresh(0);
  }

  function getState() {
    const turns = turnCandidates();
    return {
      version: VERSION,
      enabled: state.settings.enabled,
      turns: turns.length,
      mountedTurns: turns.length,
      adapter: {
        conversationRoot:
          Boolean(
            ChatGPTDOMAdapter
              .conversationRoot()
          ),
        sidebarRoot:
          Boolean(
            ChatGPTDOMAdapter.sidebarRoot()
          ),
      },
      windowing: {
        aggressive:
          state.settings
            .aggressiveWindowing,
        cachedTurns:
          state.turnCache.length,
        nearTurns:
          state.nearTurns.size,
        windowedTurns:
          state.optimizedTurns.size,
        observer:
          Boolean(state.windowObserver),
      },
      toolGroups: {
        ...state.toolCounts,
      },
      diagnostics: {
        ...state.metrics,
        phaseTwoStarted:
          state.phaseTwoStarted,
        conversationLinks:
          state.conversationLinks.size,
      },
      telemetry: {
        enabled: state.settings.telemetryEnabled,
        status: state.telemetry.status,
        transport: state.telemetry.transport,
        queue: state.telemetry.queue.length,
        debugId: state.telemetry.debugId,
        configStatus: state.telemetry.configStatus,
        lastUploadAt: state.telemetry.lastUploadAt,
      },
      streaming: isStreaming(),
      conversationId:
        currentConversationId(),
      conversationStatus:
        currentConversationId()
          ? state.conversationStates[
              currentConversationId()
            ]?.status || null
          : null,
      conversationStates: {
        ...state.conversationStates,
      },
      nativeStatus: {
        ...state.nativeStatus,
      },
      route:
        location.pathname +
        location.search,
    };
  }

  function destroy() {
    if (state.destroyed) return;
    state.destroyed = true;

    stopTelemetryRuntime(true);

    clearTimeout(state.refreshTimer);
    clearTimeout(state.stateEvalTimer);
    clearTimeout(state.phaseTwoTimer);
    clearTimeout(state.routeRebindTimer);
    clearTimeout(state.updateWatchdogTimer);
    clearTimeout(state.controlRecoveryTimer);
    clearTimeout(state.sidebarReconcileTimer);
    clearInitialBottomScroll();
    clearInterval(state.statusTimer);

    state.observer?.disconnect();
    state.conversationObserver?.disconnect();
    state.sidebarObserver?.disconnect();
    state.windowObserver?.disconnect();
    state.longTaskObserver?.disconnect();

    state.observer = null;
    state.conversationObserver = null;
    state.sidebarObserver = null;
    state.windowObserver = null;
    state.longTaskObserver = null;

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
    state.conversationLinks.clear();

    for (
      const item of
        document.querySelectorAll(
          '[data-cgpt-safari-chat-state]'
        )
    ) {
      item.removeAttribute(
        'data-cgpt-safari-chat-state'
      );
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
    setAggressiveWindowing,
    setTelemetryEnabled,
    startDebugSession,
    stopDebugSession,
    flushTelemetry,
    nativeTelemetryResult,
    setNativeStatus,
    nativeActionResult,
    toggleNativePanel,
    nativePanelRenderState,
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

  if (document.readyState === 'loading') {
    document.addEventListener(
      'DOMContentLoaded',
      () => {
        createControl();
        schedulePhaseTwoRuntime();
      },
      { once: true }
    );
  } else {
    createControl();
    schedulePhaseTwoRuntime();
  }
})();
