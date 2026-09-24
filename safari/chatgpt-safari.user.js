// ==UserScript==
// @name         ChatGPT Safari Lite
// @namespace    https://github.com/masakacj/chatgpt-web
// @version      0.2.0
// @description  Safari-first ChatGPT helper: keep the official page intact and only apply conservative long-chat rendering hints.
// @author       masakacj
// @match        https://chatgpt.com/*
// @run-at       document-start
// @grant        none
// @updateURL    https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-safari.user.js
// @downloadURL  https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-safari.user.js
// ==/UserScript==

(() => {
  'use strict';

  const VERSION = '0.2.0';
  const GLOBAL_KEY = 'ChatGPTSafari';
  const STYLE_ID = 'cgpt-safari-lite-style';
  const HOST_ID = 'cgpt-safari-lite-host';
  const SETTINGS_KEY = 'cgpt-safari-lite-settings-v1';

  try {
    window[GLOBAL_KEY]?.destroy?.();
  } catch (_) {}

  const defaults = {
    enabled: true,
    minTurns: 32,
    keepRecent: 16,
    showControl: true,
  };

  const state = {
    settings: loadSettings(),
    destroyed: false,
    observer: null,
    refreshTimer: 0,
    statusTimer: 0,
    coldTurns: new Set(),
    lastRoute: location.pathname + location.search,
    ui: null,
  };

  function clamp(value, min, max) {
    const n = Number(value);
    return Math.min(max, Math.max(min, Number.isFinite(n) ? n : min));
  }

  function loadSettings() {
    try {
      const stored = JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}');
      return {
        enabled: stored.enabled !== false,
        minTurns: clamp(stored.minTurns ?? defaults.minTurns, 12, 200),
        keepRecent: clamp(stored.keepRecent ?? defaults.keepRecent, 6, 60),
        showControl: stored.showControl !== false,
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

  function installStyle() {
    if (document.getElementById(STYLE_ID)) return;

    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = [
      '[data-cgpt-safari-cold="1"] {',
      '  content-visibility: auto !important;',
      '  contain-intrinsic-size: auto 720px !important;',
      '}',
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

  function restoreColdTurns() {
    for (const turn of Array.from(state.coldTurns)) {
      if (turn instanceof HTMLElement) {
        turn.removeAttribute('data-cgpt-safari-cold');
      }
    }
    state.coldTurns.clear();
  }

  function applyPerformanceHints() {
    const turns = turnCandidates();

    if (!state.settings.enabled || turns.length < state.settings.minTurns) {
      restoreColdTurns();
      updateUI(turns.length);
      return;
    }

    const cutoff = Math.max(0, turns.length - state.settings.keepRecent);
    const nextCold = new Set();

    for (let i = 0; i < cutoff; i += 1) {
      const turn = turns[i];
      if (!(turn instanceof HTMLElement)) continue;
      if (turn.matches(':focus-within')) continue;
      turn.setAttribute('data-cgpt-safari-cold', '1');
      nextCold.add(turn);
    }

    for (const oldTurn of Array.from(state.coldTurns)) {
      if (!nextCold.has(oldTurn) && oldTurn instanceof HTMLElement) {
        oldTurn.removeAttribute('data-cgpt-safari-cold');
      }
    }

    state.coldTurns = nextCold;
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
        restoreColdTurns();
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
      '.fab[data-streaming="1"]::after { content: ""; width: 7px; height: 7px; border-radius: 50%; background: #34c759; position: absolute; right: 1px; top: 1px; box-shadow: 0 0 0 2px rgba(255,255,255,.82); }',
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
    title.textContent = 'ChatGPT Safari Lite';

    const status = document.createElement('div');
    status.className = 'status';

    const perfRow = document.createElement('label');
    perfRow.className = 'row';
    const perfLabel = document.createElement('span');
    perfLabel.className = 'label';
    perfLabel.textContent = '长对话轻量优化';
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
    foot.textContent = 'v' + VERSION + ' · Safari 原生页面，无 WKWebView';

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
      restoreColdTurns();
      updateUI(turnCandidates().length);
      panel.classList.remove('open');
    });

    hide.addEventListener('click', () => {
      state.settings.showControl = false;
      saveSettings();
      host.remove();
      state.ui = null;
    });

    state.ui = { host, button, panel, status, perfSwitch };
    updateUI(turnCandidates().length);
  }

  function updateUI(turnCount) {
    const ui = state.ui;
    if (!ui) return;

    const streaming = isStreaming();
    ui.button.dataset.streaming = streaming ? '1' : '0';

    let mode = '官方原生';
    if (state.settings.enabled && turnCount >= state.settings.minTurns) {
      mode = '轻量优化';
    } else if (state.settings.enabled) {
      mode = '自动待命';
    }

    ui.status.textContent =
      mode + ' · ' +
      turnCount + ' 轮 · 保留最近 ' +
      state.settings.keepRecent + ' 轮 · ' +
      (streaming ? '正在回复' : '空闲');
  }

  function setupObservers() {
    state.observer = new MutationObserver(() => scheduleRefresh(180));
    state.observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
    });

    window.addEventListener('popstate', onRoute, { passive: true });
    window.addEventListener('hashchange', onRoute, { passive: true });
    document.addEventListener('visibilitychange', onVisibility, { passive: true });

    state.statusTimer = window.setInterval(() => {
      if (!state.destroyed) updateUI(turnCandidates().length);
    }, 1600);
  }

  function onRoute() {
    scheduleRefresh(0);
  }

  function onVisibility() {
    if (!document.hidden) scheduleRefresh(0);
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

  function setKeepRecent(value) {
    state.settings.keepRecent = clamp(value, 6, 60);
    saveSettings();
    scheduleRefresh(0);
  }

  function getState() {
    const turns = turnCandidates();
    return {
      version: VERSION,
      enabled: state.settings.enabled,
      minTurns: state.settings.minTurns,
      keepRecent: state.settings.keepRecent,
      turns: turns.length,
      optimizedTurns: state.coldTurns.size,
      streaming: isStreaming(),
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

    restoreColdTurns();
    document.getElementById(STYLE_ID)?.remove();
    document.getElementById(HOST_ID)?.remove();
    state.ui = null;

    try {
      delete window[GLOBAL_KEY];
    } catch (_) {
      window[GLOBAL_KEY] = undefined;
    }
  }

  window[GLOBAL_KEY] = {
    version: VERSION,
    getState,
    setEnabled,
    setKeepRecent,
    showControl,
    refresh: () => scheduleRefresh(0),
    destroy,
  };

  installStyle();
  setupObservers();

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      createControl();
      scheduleRefresh(0);
    }, { once: true });
  } else {
    createControl();
    scheduleRefresh(0);
  }
})();
