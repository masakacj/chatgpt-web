(() => {
  'use strict';

  const ENGINE_VERSION = '0.1.1';
  const GLOBAL_KEY = 'ChatGPTPerf';

  try {
    const previous = window[GLOBAL_KEY];
    if (previous?.version === ENGINE_VERSION) return;
    previous?.destroy?.();
  } catch (_) {}

  const native = window.__CHATGPT_WEB_NATIVE__ || {};
  const remote = native.remote || {};

  const config = {
    balancedThreshold: Number(remote.balancedThreshold ?? 28),
    aggressiveThreshold: Number(remote.aggressiveThreshold ?? 70),
    extremeThreshold: Number(remote.extremeThreshold ?? 140),
    coldViewportDistance: Number(remote.coldViewportDistance ?? 6),
    extremeViewportDistance: Number(remote.extremeViewportDistance ?? 12),
    unloadMedia: remote.unloadMedia !== false,
    packExtreme: remote.packExtreme === true,
    disableAnimations: remote.disableAnimations !== false,
    disableBackdropFilters: remote.disableBackdropFilters !== false,
    toolMode: String(remote.toolMode || native.toolMode || 'minimal'),
  };

  const state = {
    mode: String(native.mode || 'auto'),
    keepRecent: clamp(Number(native.keepRecent || 18), 8, 40),
    effectiveMode: 'off',
    memoryPressure: false,
    turns: [],
    observed: new Set(),
    records: new WeakMap(),
    toolRecords: new WeakMap(),
    toolGroups: new Set(),
    mutationObserver: null,
    intersectionObserver: null,
    refreshQueued: false,
    refreshTimer: 0,
    metricsTimer: 0,
    driftTimer: 0,
    lastDriftAt: performance.now(),
    longTaskMs: 0,
    destroyed: false,
    routeKey: location.pathname + location.search,
    lastToolCounts: { groups: 0, collapsed: 0 },
  };

  const STYLE_ID = 'cgpt-web-perf-style';
  const ROOT_CLASSES = [
    'cgp-perf-balanced',
    'cgp-perf-aggressive',
    'cgp-perf-extreme',
    'cgp-perf-off',
  ];

  const transparentPixel =
    'data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=';

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, Number.isFinite(value) ? value : min));
  }

  function post(message) {
    try {
      window.webkit?.messageHandlers?.perf?.postMessage(message);
    } catch (_) {}
  }

  function injectStyle() {
    if (document.getElementById(STYLE_ID)) return;

    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      [data-cgp-turn="1"] {
        content-visibility: auto;
        contain-intrinsic-size: auto 640px;
      }

      [data-cgp-tier="cold"] {
        box-sizing: border-box !important;
        height: var(--cgp-height) !important;
        min-height: var(--cgp-height) !important;
        max-height: var(--cgp-height) !important;
        overflow: hidden !important;
        content-visibility: hidden !important;
        contain: strict !important;
        pointer-events: none !important;
      }

      [data-cgp-tier="packed"] {
        box-sizing: border-box !important;
        height: var(--cgp-height) !important;
        min-height: var(--cgp-height) !important;
        max-height: var(--cgp-height) !important;
        overflow: hidden !important;
        content-visibility: auto !important;
        contain: strict !important;
      }

      .cgp-packed-placeholder {
        height: 100%;
        min-height: 100%;
        box-sizing: border-box;
        display: flex;
        align-items: center;
        justify-content: center;
        opacity: .18;
        font: 11px/1.2 -apple-system, BlinkMacSystemFont, sans-serif;
        user-select: none;
      }

      html.cgp-perf-aggressive [data-cgp-turn="1"] *,
      html.cgp-perf-extreme [data-cgp-turn="1"] * {
        transition-duration: .001ms !important;
        animation-duration: .001ms !important;
        animation-iteration-count: 1 !important;
      }

      html.cgp-perf-aggressive [data-cgp-tier="cold"] *,
      html.cgp-perf-extreme [data-cgp-tier="cold"] * {
        visibility: hidden !important;
      }

      html.cgp-perf-aggressive [class*="backdrop-blur"],
      html.cgp-perf-extreme [class*="backdrop-blur"],
      html.cgp-perf-aggressive [style*="backdrop-filter"],
      html.cgp-perf-extreme [style*="backdrop-filter"] {
        backdrop-filter: none !important;
        -webkit-backdrop-filter: none !important;
      }

      [data-cgp-media-suspended="1"] {
        visibility: hidden !important;
      }

      [data-cgp-tool-group="1"] {
        content-visibility: auto;
        contain: layout style paint;
        contain-intrinsic-size: auto 48px;
      }

      .cgp-tool-summary {
        box-sizing: border-box;
        width: 100%;
        min-height: 36px;
        margin: 2px 0;
        padding: 7px 10px;
        border: 1px solid color-mix(in srgb, currentColor 14%, transparent);
        border-radius: 10px;
        background: color-mix(in srgb, Canvas 94%, transparent);
        color: CanvasText;
        font: 12px/1.25 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
        text-align: left;
        opacity: .78;
        cursor: pointer;
        user-select: none;
      }

      .cgp-tool-summary:hover {
        opacity: 1;
      }

      [data-cgp-tool-collapsed="1"] > :not(.cgp-tool-summary) {
        display: none !important;
      }

      [data-cgp-tool-collapsed="1"] {
        min-height: 40px !important;
        max-height: 48px !important;
        overflow: hidden !important;
        contain: layout style paint !important;
      }

      [data-cgp-tool-active="1"] > .cgp-tool-summary {
        display: none !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  }

  function getTurns() {
    const selectors = [
      'article[data-testid^="conversation-turn-"]',
      '[data-testid^="conversation-turn-"]',
      'main article',
    ];

    for (const selector of selectors) {
      const candidates = Array.from(document.querySelectorAll(selector));
      if (!candidates.length) continue;

      return candidates.filter((node, index) => {
        return !candidates.some((other, otherIndex) =>
          otherIndex !== index && other.contains(node)
        );
      });
    }

    return [];
  }

  function recordFor(turn) {
    let record = state.records.get(turn);
    if (!record) {
      record = {
        height: 0,
        packedHTML: null,
        packed: false,
        staticRestored: false,
      };
      state.records.set(turn, record);
    }
    return record;
  }

  function measureHeight(turn) {
    const record = recordFor(turn);
    const rect = turn.getBoundingClientRect();
    const height = Math.ceil(rect.height);
    if (Number.isFinite(height) && height > 32) {
      record.height = height;
    }
    return record.height || 320;
  }

  function viewportDistance(turn) {
    const rect = turn.getBoundingClientRect();
    const viewport = Math.max(window.innerHeight, 1);

    if (rect.bottom < 0) return -rect.bottom / viewport;
    if (rect.top > viewport) return (rect.top - viewport) / viewport;
    return 0;
  }

  function isStreaming() {
    return Boolean(
      document.querySelector(
        '[data-testid="stop-button"], button[aria-label*="Stop"], button[aria-label*="停止"], button[data-testid*="stop"]'
      )
    );
  }

  const TOOL_GROUP_RE = /^(?:已调用工具|调用工具|工具调用|Called tools?|Tool calls?|Tools called)\s*$/i;
  const TOOL_ACTION_RE = /(?:Ran command|Run command|Called tool|Searched|Read file|Wrote file|Edited file|Opened workspace|Fetched|Executed|运行命令|执行命令|调用工具|搜索|读取文件|写入文件|编辑文件|打开工作区|已运行|已调用)/i;
  const TOOL_ATTENTION_RE = /(?:running|in progress|pending|waiting|failed|error|approval|required|confirm|permission|正在|执行中|等待|失败|错误|需要确认|确认操作|授权|权限)/i;
  const TOOL_NAME_RE = /\b(?:mcp[a-z0-9_-]+|mcpoffice|mcpdebian|mcphome|web|python|container|functions|image_gen|automations|genui)\b/gi;

  function normalizedText(node) {
    return String(node?.textContent || '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function toolRecordFor(group) {
    let record = state.toolRecords.get(group);
    if (!record) {
      record = {
        manualExpanded: false,
        summaryButton: null,
      };
      state.toolRecords.set(group, record);
    }
    return record;
  }

  function toolActionNodes(scope) {
    return Array.from(
      scope.querySelectorAll('button,[role="button"],summary,[aria-expanded]')
    ).filter((node) => {
      const text = normalizedText(node);
      return TOOL_ACTION_RE.test(text) && !TOOL_GROUP_RE.test(text);
    });
  }

  function findToolGroupContainer(heading, turn) {
    let node = heading.parentElement;

    for (let depth = 0; node && node !== turn && depth < 7; depth += 1, node = node.parentElement) {
      const role = node.getAttribute?.('role');
      if (node.tagName === 'BUTTON' || node.tagName === 'SUMMARY' || role === 'button') {
        continue;
      }

      const text = normalizedText(node);
      if (!text || text.length > 30000) continue;

      const actions = toolActionNodes(node);
      if (actions.length > 0) return node;
    }

    return null;
  }

  function findToolGroups(turn) {
    const headings = Array.from(
      turn.querySelectorAll('button,[role="button"],summary,[aria-expanded]')
    ).filter((node) => TOOL_GROUP_RE.test(normalizedText(node)));

    const groups = [];
    for (const heading of headings) {
      const group = findToolGroupContainer(heading, turn);
      if (!group) continue;
      if (groups.some((existing) => existing === group || existing.contains(group))) continue;

      for (let i = groups.length - 1; i >= 0; i -= 1) {
        if (group.contains(groups[i])) groups.splice(i, 1);
      }
      groups.push(group);
    }
    return groups;
  }

  function toolGroupNeedsAttention(group) {
    const interactiveText = Array.from(
      group.querySelectorAll('button,[role="button"],summary,[aria-live],[aria-label]')
    )
      .map((node) => `${normalizedText(node)} ${node.getAttribute?.('aria-label') || ''}`)
      .join(' ');

    return TOOL_ATTENTION_RE.test(interactiveText);
  }

  function toolSummary(group) {
    const text = normalizedText(group);
    const actions = toolActionNodes(group);
    const names = Array.from(new Set(text.match(TOOL_NAME_RE) || []))
      .slice(0, 3);

    const lineMatches = Array.from(text.matchAll(/(\d{1,6})\s*(?:lines?|行)\b/gi));
    const lineCount = lineMatches.reduce((max, match) => Math.max(max, Number(match[1]) || 0), 0);
    const chinese = /已调用工具|调用工具|工具调用/.test(text) ||
      (document.documentElement.lang || '').toLowerCase().startsWith('zh');

    const count = Math.max(1, actions.length);
    const parts = [
      chinese ? `🛠 ${count} 次工具调用` : `🛠 ${count} tool call${count === 1 ? '' : 's'}`,
    ];

    if (names.length) parts.push(names.join(' · '));
    if (lineCount > 0) parts.push(chinese ? `${lineCount} 行` : `${lineCount} lines`);

    return parts.join(' · ');
  }

  function ensureToolSummaryButton(group) {
    const record = toolRecordFor(group);
    if (record.summaryButton?.isConnected) return record.summaryButton;

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'cgp-tool-summary';
    button.setAttribute('data-cgp-owned', '1');

    button.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();

      const expanded = group.getAttribute('data-cgp-tool-collapsed') !== '1';
      record.manualExpanded = !expanded;
      group.setAttribute('data-cgp-tool-collapsed', expanded ? '1' : '0');
      button.textContent = expanded
        ? toolSummary(group)
        : `${toolSummary(group)} · ${/zh/i.test(document.documentElement.lang || '') ? '收起' : 'collapse'}`;
    }, true);

    try {
      group.prepend(button);
    } catch (_) {
      group.appendChild(button);
    }

    record.summaryButton = button;
    return button;
  }

  function optimizeToolGroups(turns) {
    let groups = 0;
    let collapsed = 0;
    const seen = new Set();

    for (const turn of turns) {
      if (!(turn instanceof HTMLElement)) continue;

      for (const group of findToolGroups(turn)) {
        if (!(group instanceof HTMLElement) || seen.has(group)) continue;
        seen.add(group);
        state.toolGroups.add(group);
        groups += 1;

        group.setAttribute('data-cgp-tool-group', '1');

        const active = toolGroupNeedsAttention(group);
        group.setAttribute('data-cgp-tool-active', active ? '1' : '0');

        const button = ensureToolSummaryButton(group);
        const record = toolRecordFor(group);
        const summary = toolSummary(group);
        const chinese = /已调用工具|调用工具|工具调用/.test(normalizedText(group)) ||
          (document.documentElement.lang || '').toLowerCase().startsWith('zh');
        const desiredText = record.manualExpanded
          ? `${summary} · ${chinese ? '收起' : 'collapse'}`
          : summary;
        if (button.textContent !== desiredText) button.textContent = desiredText;

        const toolMode = config.toolMode === 'full' ? 'full' :
          (config.toolMode === 'auto' ? 'auto' : 'minimal');

        let shouldCollapse = false;
        if (!active && !record.manualExpanded) {
          if (toolMode === 'minimal') {
            shouldCollapse = true;
          } else if (toolMode === 'auto') {
            shouldCollapse = viewportDistance(group) > 0.4 || toolActionNodes(group).length > 1;
          }
        }

        if (toolMode === 'full' || active || record.manualExpanded) {
          group.setAttribute('data-cgp-tool-collapsed', '0');
        } else if (shouldCollapse) {
          group.setAttribute('data-cgp-tool-collapsed', '1');
          collapsed += 1;
        }
      }
    }

    for (const group of Array.from(state.toolGroups)) {
      if (!group.isConnected) {
        state.toolGroups.delete(group);
        continue;
      }
      if (!seen.has(group) && group.getAttribute('data-cgp-tool-active') !== '1') {
        group.removeAttribute('data-cgp-tool-group');
        group.removeAttribute('data-cgp-tool-collapsed');
        group.removeAttribute('data-cgp-tool-active');
        group.querySelector(':scope > .cgp-tool-summary')?.remove();
        state.toolGroups.delete(group);
      }
    }

    state.lastToolCounts = { groups, collapsed };
    return state.lastToolCounts;
  }

  function restoreToolGroups() {
    for (const group of Array.from(state.toolGroups)) {
      if (!(group instanceof HTMLElement) || !group.isConnected) continue;
      group.removeAttribute('data-cgp-tool-group');
      group.removeAttribute('data-cgp-tool-collapsed');
      group.removeAttribute('data-cgp-tool-active');
      group.querySelector(':scope > .cgp-tool-summary')?.remove();
    }
    state.toolGroups.clear();
    state.lastToolCounts = { groups: 0, collapsed: 0 };
  }

  function resolveMode(turnCount) {
    if (state.mode !== 'auto') return state.mode;
    if (state.memoryPressure) return 'extreme';
    if (turnCount >= config.extremeThreshold) return 'extreme';
    if (turnCount >= config.aggressiveThreshold) return 'aggressive';
    if (turnCount >= config.balancedThreshold) return 'balanced';
    return 'off';
  }

  function applyRootMode(mode) {
    const root = document.documentElement;
    if (!root) return;
    ROOT_CLASSES.forEach((name) => root.classList.remove(name));
    root.classList.add(`cgp-perf-${mode}`);
  }

  function suspendMedia(turn) {
    if (!config.unloadMedia) return;

    for (const img of turn.querySelectorAll('img')) {
      if (img.dataset.cgpMediaSuspended === '1') continue;
      const src = img.getAttribute('src');
      const srcset = img.getAttribute('srcset');
      if (!src || src.startsWith('data:')) continue;

      img.dataset.cgpSrc = src;
      if (srcset) img.dataset.cgpSrcset = srcset;
      img.dataset.cgpMediaSuspended = '1';
      img.setAttribute('loading', 'lazy');
      img.removeAttribute('srcset');
      img.setAttribute('src', transparentPixel);
    }

    for (const media of turn.querySelectorAll('video, audio')) {
      try { media.pause(); } catch (_) {}

      if (media.dataset.cgpMediaSuspended !== '1') {
        const src = media.getAttribute('src');
        if (src) media.dataset.cgpSrc = src;
        media.dataset.cgpMediaSuspended = '1';
      }

      media.removeAttribute('src');
      for (const source of media.querySelectorAll('source[src]')) {
        if (!source.dataset.cgpSrc) {
          source.dataset.cgpSrc = source.getAttribute('src') || '';
        }
        source.removeAttribute('src');
      }

      try { media.load(); } catch (_) {}
    }

    for (const frame of turn.querySelectorAll('iframe[src]')) {
      if (frame.dataset.cgpMediaSuspended === '1') continue;
      frame.dataset.cgpSrc = frame.getAttribute('src') || '';
      frame.dataset.cgpMediaSuspended = '1';
      frame.setAttribute('src', 'about:blank');
    }
  }

  function restoreMedia(turn) {
    for (const img of turn.querySelectorAll('img[data-cgp-media-suspended="1"]')) {
      const src = img.dataset.cgpSrc;
      const srcset = img.dataset.cgpSrcset;
      if (src) img.setAttribute('src', src);
      if (srcset) img.setAttribute('srcset', srcset);
      delete img.dataset.cgpSrc;
      delete img.dataset.cgpSrcset;
      delete img.dataset.cgpMediaSuspended;
    }

    for (const media of turn.querySelectorAll('video[data-cgp-media-suspended="1"], audio[data-cgp-media-suspended="1"]')) {
      const src = media.dataset.cgpSrc;
      if (src) media.setAttribute('src', src);
      delete media.dataset.cgpSrc;
      delete media.dataset.cgpMediaSuspended;

      for (const source of media.querySelectorAll('source[data-cgp-src]')) {
        const sourceSrc = source.dataset.cgpSrc;
        if (sourceSrc) source.setAttribute('src', sourceSrc);
        delete source.dataset.cgpSrc;
      }

      try { media.load(); } catch (_) {}
    }

    for (const frame of turn.querySelectorAll('iframe[data-cgp-media-suspended="1"]')) {
      const src = frame.dataset.cgpSrc;
      if (src) frame.setAttribute('src', src);
      delete frame.dataset.cgpSrc;
      delete frame.dataset.cgpMediaSuspended;
    }
  }

  function unpackTurn(turn) {
    const record = recordFor(turn);
    if (!record.packed) return;

    const html = record.packedHTML;
    if (typeof html === 'string') {
      turn.innerHTML = html;
      record.staticRestored = true;
    }

    record.packed = false;
    turn.removeAttribute('data-cgp-tier');
    turn.style.removeProperty('--cgp-height');
  }

  function packTurn(turn) {
    const record = recordFor(turn);
    if (record.packed || turn.matches(':focus-within')) return;

    const height = measureHeight(turn);
    const html = turn.innerHTML;
    if (!html || html.length < 256) return;

    record.packedHTML = html;
    record.packed = true;

    const placeholder = document.createElement('div');
    placeholder.className = 'cgp-packed-placeholder';
    placeholder.textContent = 'optimized';

    turn.replaceChildren(placeholder);
    turn.style.setProperty('--cgp-height', `${height}px`);
    turn.setAttribute('data-cgp-tier', 'packed');
  }

  function makeHot(turn) {
    unpackTurn(turn);
    restoreMedia(turn);
    turn.setAttribute('data-cgp-tier', 'hot');
    turn.style.removeProperty('--cgp-height');
  }

  function makeWarm(turn) {
    unpackTurn(turn);
    restoreMedia(turn);
    turn.setAttribute('data-cgp-tier', 'warm');
    turn.style.removeProperty('--cgp-height');
  }

  function makeCold(turn) {
    const height = measureHeight(turn);
    suspendMedia(turn);
    turn.style.setProperty('--cgp-height', `${height}px`);
    turn.setAttribute('data-cgp-tier', 'cold');
  }

  function restoreTurn(turn) {
    unpackTurn(turn);
    restoreMedia(turn);
    turn.removeAttribute('data-cgp-tier');
    turn.style.removeProperty('--cgp-height');
  }

  function classifyTurn(turn, index, total, effectiveMode) {
    turn.setAttribute('data-cgp-turn', '1');

    if (effectiveMode === 'off') {
      restoreTurn(turn);
      return 'hot';
    }

    const recentBoundary = Math.max(0, total - state.keepRecent);
    if (index >= recentBoundary || turn.matches(':focus-within')) {
      makeHot(turn);
      return 'hot';
    }

    const distance = viewportDistance(turn);

    if (distance <= 1.5) {
      makeHot(turn);
      return 'hot';
    }

    if (effectiveMode === 'balanced') {
      makeWarm(turn);
      return 'warm';
    }

    if (distance <= config.coldViewportDistance) {
      makeWarm(turn);
      return 'warm';
    }

    const manualExtreme = state.mode === 'extreme';
    const mayPack =
      effectiveMode === 'extreme' &&
      distance >= config.extremeViewportDistance &&
      (config.packExtreme || state.memoryPressure || manualExtreme);

    if (mayPack) {
      suspendMedia(turn);
      packTurn(turn);
      return 'packed';
    }

    makeCold(turn);
    return 'cold';
  }

  function refresh() {
    state.refreshQueued = false;
    if (state.destroyed) return;

    injectStyle();

    const routeKey = location.pathname + location.search;
    if (routeKey !== state.routeKey) {
      state.routeKey = routeKey;
      state.memoryPressure = false;
    }

    const turns = getTurns();
    state.turns = turns;

    const effectiveMode = resolveMode(turns.length);
    state.effectiveMode = effectiveMode;
    applyRootMode(effectiveMode);

    let hot = 0;
    let warm = 0;
    let cold = 0;
    let packed = 0;

    turns.forEach((turn, index) => {
      if (!(turn instanceof HTMLElement)) return;

      const tier = classifyTurn(turn, index, turns.length, effectiveMode);
      if (tier === 'hot') hot += 1;
      else if (tier === 'warm') warm += 1;
      else if (tier === 'cold') cold += 1;
      else if (tier === 'packed') packed += 1;

      if (!state.observed.has(turn)) {
        state.observed.add(turn);
        state.intersectionObserver?.observe(turn);
      }
    });

    for (const turn of Array.from(state.observed)) {
      if (!turn.isConnected) {
        state.intersectionObserver?.unobserve(turn);
        state.observed.delete(turn);
      }
    }

    optimizeToolGroups(turns);
    state.lastCounts = { hot, warm, cold, packed };
  }

  function scheduleRefresh(delay = 0) {
    if (state.destroyed) return;

    if (delay > 0) {
      clearTimeout(state.refreshTimer);
      state.refreshTimer = window.setTimeout(() => scheduleRefresh(0), delay);
      return;
    }

    if (state.refreshQueued) return;
    state.refreshQueued = true;

    requestAnimationFrame(() => {
      if ('requestIdleCallback' in window) {
        window.requestIdleCallback(refresh, { timeout: 450 });
      } else {
        setTimeout(refresh, 0);
      }
    });
  }

  function setupObservers() {
    state.intersectionObserver = new IntersectionObserver(
      () => scheduleRefresh(40),
      {
        root: null,
        rootMargin: '220% 0px 220% 0px',
        threshold: 0,
      }
    );

    state.mutationObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type !== 'childList') continue;
        if (mutation.addedNodes.length || mutation.removedNodes.length) {
          scheduleRefresh(180);
          return;
        }
      }
    });

    const target = document.documentElement || document;
    state.mutationObserver.observe(target, {
      subtree: true,
      childList: true,
    });
  }

  function onScroll() {
    scheduleRefresh(30);
  }

  function onResize() {
    for (const turn of state.turns) {
      if (turn instanceof HTMLElement && turn.getAttribute('data-cgp-tier') !== 'packed') {
        turn.style.removeProperty('--cgp-height');
      }
    }
    scheduleRefresh(120);
  }

  function trackTimerDrift() {
    const now = performance.now();
    const expected = state.lastDriftAt + 1000;
    const drift = Math.max(0, now - expected);
    state.lastDriftAt = now;
    state.longTaskMs = Math.max(drift, state.longTaskMs * 0.65);
    state.driftTimer = window.setTimeout(trackTimerDrift, 1000);
  }

  function sendMetrics() {
    const counts = state.lastCounts || { hot: 0, warm: 0, cold: 0, packed: 0 };

    post({
      type: 'metrics',
      turns: state.turns.length,
      hot: counts.hot,
      warm: counts.warm,
      cold: counts.cold,
      packed: counts.packed,
      toolGroups: state.lastToolCounts.groups,
      toolCollapsed: state.lastToolCounts.collapsed,
      domNodes: document.getElementsByTagName('*').length,
      longTaskMs: Math.round(state.longTaskMs),
      streaming: isStreaming(),
      effectiveMode: state.effectiveMode,
      engineVersion: ENGINE_VERSION,
    });
  }

  function setMode(mode) {
    const allowed = new Set(['auto', 'balanced', 'aggressive', 'extreme', 'off']);
    state.mode = allowed.has(String(mode)) ? String(mode) : 'auto';
    if (state.mode !== 'auto') state.memoryPressure = false;
    scheduleRefresh(0);
  }

  function setKeepRecent(value) {
    state.keepRecent = clamp(Number(value), 8, 40);
    scheduleRefresh(0);
  }

  function setToolMode(value) {
    const allowed = new Set(['full', 'auto', 'minimal']);
    config.toolMode = allowed.has(String(value)) ? String(value) : 'minimal';

    if (config.toolMode === 'full') {
      for (const group of Array.from(state.toolGroups)) {
        if (!(group instanceof HTMLElement) || !group.isConnected) continue;
        group.setAttribute('data-cgp-tool-collapsed', '0');
        const record = toolRecordFor(group);
        record.manualExpanded = true;
      }
    } else {
      for (const group of Array.from(state.toolGroups)) {
        const record = toolRecordFor(group);
        record.manualExpanded = false;
      }
    }

    scheduleRefresh(0);
  }

  function onMemoryWarning() {
    state.memoryPressure = true;
    scheduleRefresh(0);

    setTimeout(() => {
      if (state.mode === 'auto') {
        state.memoryPressure = false;
        scheduleRefresh(0);
      }
    }, 5 * 60 * 1000);
  }

  function destroy() {
    if (state.destroyed) return;
    state.destroyed = true;

    clearTimeout(state.refreshTimer);
    clearTimeout(state.metricsTimer);
    clearTimeout(state.driftTimer);

    state.mutationObserver?.disconnect();
    state.intersectionObserver?.disconnect();

    document.removeEventListener('scroll', onScroll, true);
    window.removeEventListener('resize', onResize);
    window.removeEventListener('popstate', onResize);

    for (const turn of getTurns()) {
      if (turn instanceof HTMLElement) {
        restoreTurn(turn);
        turn.removeAttribute('data-cgp-turn');
      }
    }

    restoreToolGroups();

    ROOT_CLASSES.forEach((name) => document.documentElement?.classList.remove(name));
    document.getElementById(STYLE_ID)?.remove();
  }

  window[GLOBAL_KEY] = {
    version: ENGINE_VERSION,
    setMode,
    setKeepRecent,
    setToolMode,
    onMemoryWarning,
    refresh: () => scheduleRefresh(0),
    getState: () => ({
      version: ENGINE_VERSION,
      mode: state.mode,
      effectiveMode: state.effectiveMode,
      keepRecent: state.keepRecent,
      memoryPressure: state.memoryPressure,
      turns: state.turns.length,
      toolMode: config.toolMode,
      toolCounts: state.lastToolCounts,
      counts: state.lastCounts || {},
    }),
    destroy,
  };

  injectStyle();
  setupObservers();

  document.addEventListener('scroll', onScroll, { capture: true, passive: true });
  window.addEventListener('resize', onResize, { passive: true });
  window.addEventListener('popstate', onResize, { passive: true });

  trackTimerDrift();
  state.metricsTimer = window.setInterval(sendMetrics, 2500);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => scheduleRefresh(250), { once: true });
  } else {
    scheduleRefresh(250);
  }

  post({
    type: 'engine',
    event: 'ready',
    engineVersion: ENGINE_VERSION,
  });
})();
