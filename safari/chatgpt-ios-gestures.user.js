// ==UserScript==
// @name         ChatGPT Web iOS Gestures
// @namespace    https://github.com/masakacj/chatgpt-web
// @version      0.1.1
// @description  iOS-only gesture layer for the ChatGPT Web IPA shell.
// @author       masakacj
// @match        https://chatgpt.com/*
// @run-at       document-start
// @grant        none
// @updateURL    https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-ios-gestures.user.js
// @downloadURL  https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-ios-gestures.user.js
// ==/UserScript==

(() => {
  'use strict';

  const VERSION = '0.1.1';
  const GLOBAL_KEY = 'ChatGPTIOSGestures';

  try {
    window[GLOBAL_KEY]?.destroy?.();
  } catch (_) {}

  if (!window.__CHATGPT_NATIVE__?.hotUpdate) {
    return;
  }

  const CONFIG = Object.freeze({
    openRegionMinPx: 72,
    openRegionMaxRatio: 0.96,
    closeRegionMaxPx: 520,
    closeRegionRatio: 0.92,
    triggerPx: 18,
    axisRatio: 0.90,
    maxDurationMs: 1500,
  });

  const state = {
    gesture: null,
    destroyed: false,
  };

  function visible(node) {
    return node instanceof HTMLElement &&
      node.getClientRects().length > 0;
  }

  function clickFirst(selectors) {
    for (const selector of selectors) {
      const button = document.querySelector(selector);
      if (visible(button)) {
        button.click();
        return true;
      }
    }
    return false;
  }

  function openSidebar() {
    if (isSidebarOpen()) return true;

    if (clickFirst([
      '[data-testid="open-sidebar-button"]',
      '[data-testid="sidebar-button"][aria-expanded="false"]',
      'button[aria-label*="Open sidebar"]',
      'button[aria-label*="Show sidebar"]',
      'button[aria-label*="Open navigation"]',
      'button[aria-label*="打开侧边栏"]',
      'button[aria-label*="显示侧边栏"]',
      'button[aria-label*="展开侧边栏"]',
      'button[aria-label*="打开导航"]',
    ])) {
      return true;
    }

    for (const button of document.querySelectorAll('button,[role="button"]')) {
      if (!(button instanceof HTMLElement)) continue;

      const rect = button.getBoundingClientRect();
      if (
        rect.left > 110 ||
        rect.top > 140 ||
        rect.width <= 20 ||
        rect.height <= 20 ||
        rect.width >= 90 ||
        rect.height >= 90
      ) {
        continue;
      }

      const label = [
        button.getAttribute('aria-label') || '',
        button.getAttribute('title') || '',
        button.textContent || '',
      ].join(' ').replace(/\s+/g, ' ').trim();

      if (
        /(sidebar|navigation|menu|侧边栏|导航|菜单)/i.test(label) &&
        !/(close|hide|collapse|关闭|隐藏|收起)/i.test(label)
      ) {
        button.click();
        return true;
      }
    }

    return false;
  }

  function isSidebarOpen() {
    const control = document.querySelector(
      '[data-testid="sidebar-button"][aria-expanded="true"],' +
      '[data-testid="close-sidebar-button"],' +
      'button[aria-label*="Close sidebar"],' +
      'button[aria-label*="Hide sidebar"],' +
      'button[aria-label*="Collapse sidebar"],' +
      'button[aria-label*="关闭侧边栏"],' +
      'button[aria-label*="隐藏侧边栏"],' +
      'button[aria-label*="收起侧边栏"]'
    );

    if (visible(control)) return true;

    const candidates = [
      'aside nav',
      '[data-testid*="sidebar"] nav',
      'nav[aria-label*="Chat"]',
      'nav[aria-label*="聊天"]',
    ];

    for (const selector of candidates) {
      const nav = document.querySelector(selector);
      if (!(nav instanceof HTMLElement)) continue;

      const rect = nav.getBoundingClientRect();
      if (rect.width > 140 && rect.right > 40) {
        return true;
      }
    }

    return false;
  }

  function closeSidebar() {
    if (!isSidebarOpen()) return true;

    if (clickFirst([
      '[data-testid="close-sidebar-button"]',
      '[data-testid="sidebar-button"][aria-expanded="true"]',
      'button[aria-label*="Close sidebar"]',
      'button[aria-label*="Hide sidebar"]',
      'button[aria-label*="Collapse sidebar"]',
      'button[aria-label*="关闭侧边栏"]',
      'button[aria-label*="隐藏侧边栏"]',
      'button[aria-label*="收起侧边栏"]',
      'button[aria-label*="关闭导航"]',
    ])) {
      return true;
    }

    for (const button of document.querySelectorAll('button,[role="button"]')) {
      if (!(button instanceof HTMLElement) || !visible(button)) continue;

      const label = [
        button.getAttribute('aria-label') || '',
        button.getAttribute('title') || '',
        button.textContent || '',
      ].join(' ').replace(/\s+/g, ' ').trim();

      if (
        /(sidebar|navigation|menu|侧边栏|导航|菜单)/i.test(label) &&
        /(close|hide|collapse|关闭|隐藏|收起)/i.test(label)
      ) {
        button.click();
        return true;
      }
    }

    return false;
  }

  function start(event) {
    if (state.destroyed || event.touches?.length !== 1) return;

    const touch = event.touches[0];
    const open = isSidebarOpen();

    const closeStartPx = Math.min(
      CONFIG.closeRegionMaxPx,
      Math.max(240, window.innerWidth * CONFIG.closeRegionRatio)
    );

    const openMaxPx = Math.max(
      CONFIG.openRegionMinPx + 120,
      window.innerWidth * CONFIG.openRegionMaxRatio
    );

    const eligible = open
      ? touch.clientX <= closeStartPx
      : (
          touch.clientX >= CONFIG.openRegionMinPx &&
          touch.clientX <= openMaxPx
        );

    state.gesture = eligible
      ? {
          x: touch.clientX,
          y: touch.clientY,
          at: performance.now(),
          open,
          fired: false,
        }
      : null;
  }

  function move(event) {
    const gesture = state.gesture;
    if (!gesture || gesture.fired || event.touches?.length !== 1) return;

    const touch = event.touches[0];
    const dx = touch.clientX - gesture.x;
    const dy = touch.clientY - gesture.y;

    if (performance.now() - gesture.at > CONFIG.maxDurationMs) {
      state.gesture = null;
      return;
    }

    const horizontalIntent =
      Math.abs(dx) >= CONFIG.triggerPx &&
      Math.abs(dx) >= Math.abs(dy) * CONFIG.axisRatio;

    if (!horizontalIntent) return;

    const shouldClose =
      gesture.open && dx >= CONFIG.triggerPx;

    const shouldOpen =
      !gesture.open && dx <= -CONFIG.triggerPx;

    if (!shouldClose && !shouldOpen) return;

    gesture.fired = true;

    if (shouldClose) {
      closeSidebar();
    } else {
      openSidebar();
    }
  }

  function end() {
    state.gesture = null;
  }

  function install() {
    document.addEventListener('touchstart', start, {
      passive: true,
      capture: true,
    });
    document.addEventListener('touchmove', move, {
      passive: true,
      capture: true,
    });
    document.addEventListener('touchend', end, {
      passive: true,
      capture: true,
    });
    document.addEventListener('touchcancel', end, {
      passive: true,
      capture: true,
    });
  }

  function destroy() {
    if (state.destroyed) return;
    state.destroyed = true;

    document.removeEventListener('touchstart', start, true);
    document.removeEventListener('touchmove', move, true);
    document.removeEventListener('touchend', end, true);
    document.removeEventListener('touchcancel', end, true);

    state.gesture = null;

    try {
      delete window[GLOBAL_KEY];
    } catch (_) {
      window[GLOBAL_KEY] = undefined;
    }
  }

  window[GLOBAL_KEY] = {
    version: VERSION,
    config: CONFIG,
    isSidebarOpen,
    openSidebar,
    closeSidebar,
    destroy,
  };

  install();
})();
