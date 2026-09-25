// ==UserScript==
// @name         ChatGPT Web iOS Gestures
// @namespace    https://github.com/masakacj/chatgpt-web
// @version      0.1.7
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

  const VERSION = '0.1.7';
  const GLOBAL_KEY = 'ChatGPTIOSGestures';

  try {
    window[GLOBAL_KEY]?.destroy?.();
  } catch (_) {}

  if (!window.__CHATGPT_NATIVE__?.hotUpdate) {
    return;
  }

  const CONFIG = Object.freeze({
    edgeStartPx: 96,
    triggerPx: 18,
    axisRatio: 0.90,
    maxDurationMs: 1500,
    twoFingerTriggerPx: 6,
    twoFingerAxisRatio: 0.75,
    twoFingerScrollMultiplier: 1.0,
  });

  const state = {
    gesture: null,
    twoFingerScroll: null,
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

  function findSidebarDrawer() {
    const selectors = [
      '[data-testid="sidebar"]',
      '[data-testid*="sidebar"]',
      'aside',
      'nav[aria-label*="Chat"]',
      'nav[aria-label*="聊天"]',
    ];

    for (const selector of selectors) {
      for (const node of document.querySelectorAll(selector)) {
        if (!(node instanceof HTMLElement) || !visible(node)) continue;

        const rect = node.getBoundingClientRect();
        const tallEnough = rect.height >= window.innerHeight * 0.55;
        const drawerWidth =
          rect.width >= 180 &&
          rect.width <= Math.min(520, window.innerWidth * 0.96);
        const leftAnchored = rect.left <= 24 && rect.right > 120;

        if (tallEnough && drawerWidth && leftAnchored) {
          return node;
        }
      }
    }

    return null;
  }

  function isScrollable(node) {
    if (!(node instanceof HTMLElement) || !visible(node)) return false;

    const range = node.scrollHeight - node.clientHeight;
    if (range < 2 || node.clientHeight < 24) return false;

    const style = getComputedStyle(node);
    const overflowY = String(style.overflowY || '');

    return (
      /(auto|scroll|overlay)/i.test(overflowY) ||
      node.matches?.(
        '[data-radix-scroll-area-viewport],' +
        '[class*="overflow-y-auto"],' +
        '[class*="overflow-auto"],' +
        '[class*="scroll"]'
      ) ||
      range >= 80
    );
  }

  function canScrollBy(node, delta) {
    if (!(node instanceof HTMLElement) || !isScrollable(node)) return false;

    const max = Math.max(0, node.scrollHeight - node.clientHeight);
    if (max <= 0) return false;

    if (delta > 0) {
      return node.scrollTop < max - 1;
    }

    if (delta < 0) {
      return node.scrollTop > 1;
    }

    return true;
  }

  function uniquePush(list, node) {
    if (!(node instanceof HTMLElement)) return;
    if (!list.includes(node)) list.push(node);
  }

  function ancestorsOf(node) {
    const result = [];
    let current = node instanceof HTMLElement
      ? node
      : node?.parentElement;

    while (current instanceof HTMLElement) {
      uniquePush(result, current);
      current = current.parentElement;
    }

    return result;
  }

  function pointElements(point) {
    if (!point) return [];

    try {
      return document.elementsFromPoint(point.x, point.y)
        .filter((node) => node instanceof HTMLElement);
    } catch (_) {
      const single = document.elementFromPoint(point.x, point.y);
      return single instanceof HTMLElement ? [single] : [];
    }
  }

  function globalScrollCandidates(event, point) {
    const candidates = [];

    const touchTargets = Array.from(event.touches || [])
      .map((touch) => touch.target)
      .filter((node) => node instanceof HTMLElement);

    for (const node of [
      ...pointElements(point),
      ...touchTargets,
    ]) {
      for (const ancestor of ancestorsOf(node)) {
        if (isScrollable(ancestor)) {
          uniquePush(candidates, ancestor);
        }
      }
    }

    const targeted = [
      '[data-radix-scroll-area-viewport]',
      '[class*="overflow-y-auto"]',
      '[class*="overflow-auto"]',
      '[class*="scroll"]',
      '[style*="overflow-y"]',
      'aside',
      'nav',
      'main',
      'section',
    ];

    for (const node of document.querySelectorAll(targeted.join(','))) {
      if (!(node instanceof HTMLElement) || !isScrollable(node)) continue;

      const rect = node.getBoundingClientRect();
      if (
        point &&
        point.x >= rect.left &&
        point.x <= rect.right &&
        point.y >= rect.top &&
        point.y <= rect.bottom
      ) {
        uniquePush(candidates, node);
      }
    }

    const root = document.scrollingElement;

    if (
      root instanceof HTMLElement &&
      root.scrollHeight - root.clientHeight > 2
    ) {
      uniquePush(candidates, root);
    }

    return candidates;
  }

  function pickScrollContainer(event, point, delta) {
    const candidates = globalScrollCandidates(event, point);

    for (const node of candidates) {
      if (canScrollBy(node, delta)) {
        return node;
      }
    }

    return candidates.find(isScrollable) || null;
  }

  function touchCenter(touches) {
    if (!touches || touches.length < 2) return null;

    const a = touches[0];
    const b = touches[1];

    return {
      x: (a.clientX + b.clientX) / 2,
      y: (a.clientY + b.clientY) / 2,
    };
  }

  function beginTwoFingerScroll(event) {
    if (event.touches?.length !== 2) {
      return false;
    }

    const point = touchCenter(event.touches);
    if (!point) return false;

    state.gesture = null;
    state.twoFingerScroll = {
      startX: point.x,
      startY: point.y,
      lastX: point.x,
      lastY: point.y,
      scroller: null,
      claimed: false,
    };

    return true;
  }

  function moveTwoFingerScroll(event) {
    const scroll = state.twoFingerScroll;

    if (!scroll || event.touches?.length < 2) {
      return false;
    }

    const point = touchCenter(event.touches);
    if (!point) return false;

    const totalDx = point.x - scroll.startX;
    const totalDy = point.y - scroll.startY;

    const verticalIntent =
      Math.abs(totalDy) >= CONFIG.twoFingerTriggerPx &&
      Math.abs(totalDy) >=
        Math.abs(totalDx) * CONFIG.twoFingerAxisRatio;

    if (!scroll.claimed && !verticalIntent) {
      scroll.lastX = point.x;
      scroll.lastY = point.y;
      return true;
    }

    const deltaY = point.y - scroll.lastY;
    const scrollDelta =
      -deltaY * CONFIG.twoFingerScrollMultiplier;

    if (!scroll.claimed) {
      scroll.claimed = true;
    }

    if (event.cancelable) {
      event.preventDefault();
    }
    event.stopImmediatePropagation();

    if (
      !(scroll.scroller instanceof HTMLElement) ||
      !canScrollBy(scroll.scroller, scrollDelta)
    ) {
      scroll.scroller = pickScrollContainer(
        event,
        point,
        scrollDelta
      );
    }

    if (scroll.scroller instanceof HTMLElement) {
      const before = scroll.scroller.scrollTop;
      scroll.scroller.scrollTop += scrollDelta;

      if (
        Math.abs(scroll.scroller.scrollTop - before) < 0.5 &&
        Math.abs(scrollDelta) > 0.5
      ) {
        const next = pickScrollContainer(
          event,
          point,
          scrollDelta
        );

        if (
          next instanceof HTMLElement &&
          next !== scroll.scroller
        ) {
          scroll.scroller = next;
          scroll.scroller.scrollTop += scrollDelta;
        }
      }
    }

    scroll.lastX = point.x;
    scroll.lastY = point.y;

    return true;
  }

  function endTwoFingerScroll() {
    state.twoFingerScroll = null;
    state.gesture = null;
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

    return Boolean(findSidebarDrawer());
  }

  function dispatchEscape() {
    const init = {
      key: 'Escape',
      code: 'Escape',
      keyCode: 27,
      which: 27,
      bubbles: true,
      cancelable: true,
    };

    for (const target of [
      document.activeElement,
      document,
      window,
    ]) {
      try {
        target?.dispatchEvent?.(
          new KeyboardEvent('keydown', init)
        );
        target?.dispatchEvent?.(
          new KeyboardEvent('keyup', init)
        );
      } catch (_) {}
    }
  }

  function clickSidebarBackdrop() {
    const y = Math.max(
      80,
      Math.min(window.innerHeight - 80, window.innerHeight * 0.5)
    );

    const points = [
      [window.innerWidth - 4, y],
      [window.innerWidth - 24, y],
      [window.innerWidth * 0.78, y],
    ];

    for (const [x, py] of points) {
      const node = document.elementFromPoint(x, py);
      if (!(node instanceof HTMLElement)) continue;

      const drawer = findSidebarDrawer();
      if (drawer?.contains(node)) continue;

      try {
        node.click();
        return true;
      } catch (_) {}
    }

    return false;
  }

  function closeSidebar() {
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

    dispatchEscape();

    window.setTimeout(() => {
      if (isSidebarOpen()) {
        clickSidebarBackdrop();
      }
    }, 40);

    return true;
  }

  function start(event) {
    if (state.destroyed) return;

    if (event.touches?.length === 2) {
      state.gesture = null;
      beginTwoFingerScroll(event);
      return;
    }

    if (event.touches?.length !== 1) {
      state.gesture = null;
      state.twoFingerScroll = null;
      return;
    }

    const touch = event.touches[0];
    const width = window.innerWidth;

    const edge =
      touch.clientX <= CONFIG.edgeStartPx
        ? 'left'
        : touch.clientX >= width - CONFIG.edgeStartPx
          ? 'right'
          : null;

    state.gesture = edge
      ? {
          x: touch.clientX,
          y: touch.clientY,
          at: performance.now(),
          edge,
          open: isSidebarOpen(),
          claimed: false,
          fired: false,
        }
      : null;
  }

  function move(event) {
    if (event.touches?.length >= 2 || state.twoFingerScroll) {
      if (!state.twoFingerScroll && event.touches?.length === 2) {
        beginTwoFingerScroll(event);
      }

      if (state.twoFingerScroll) {
        moveTwoFingerScroll(event);
      }
      return;
    }

    const gesture = state.gesture;
    if (!gesture || event.touches?.length !== 1) return;

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

    if (!gesture.claimed && !horizontalIntent) return;

    if (!gesture.claimed) {
      gesture.claimed = true;
    }

    if (event.cancelable) {
      event.preventDefault();
    }
    event.stopImmediatePropagation();

    if (gesture.fired) return;

    const leftEdgeOpen =
      gesture.edge === 'left' &&
      dx >= CONFIG.triggerPx;

    const rightEdgeClose =
      gesture.edge === 'right' &&
      dx <= -CONFIG.triggerPx;

    if (!leftEdgeOpen && !rightEdgeClose) {
      return;
    }

    gesture.fired = true;

    if (leftEdgeOpen) {
      if (!gesture.open) {
        openSidebar();
      }
    } else if (rightEdgeClose) {
      closeSidebar();
    }
  }

  function end(event) {
    if (state.twoFingerScroll) {
      if (!event?.touches || event.touches.length < 2) {
        endTwoFingerScroll();
      }
      return;
    }

    state.gesture = null;
  }

  function install() {
    window.addEventListener('touchstart', start, {
      passive: false,
      capture: true,
    });
    window.addEventListener('touchmove', move, {
      passive: false,
      capture: true,
    });
    window.addEventListener('touchend', end, {
      passive: true,
      capture: true,
    });
    window.addEventListener('touchcancel', end, {
      passive: true,
      capture: true,
    });
  }

  function destroy() {
    if (state.destroyed) return;
    state.destroyed = true;

    window.removeEventListener('touchstart', start, true);
    window.removeEventListener('touchmove', move, true);
    window.removeEventListener('touchend', end, true);
    window.removeEventListener('touchcancel', end, true);

    state.gesture = null;
    state.twoFingerScroll = null;

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
