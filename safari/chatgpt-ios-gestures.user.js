// ==UserScript==
// @name         ChatGPT Web iOS Gestures
// @namespace    https://github.com/masakacj/chatgpt-web
// @version      0.2.0
// @description  iOS-only two-finger vertical scroll compatibility for the native ChatGPT Web shell.
// @author       masakacj
// @match        https://chatgpt.com/*
// @run-at       document-start
// @grant        none
// @updateURL    https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-ios-gestures.user.js
// @downloadURL  https://raw.githubusercontent.com/masakacj/chatgpt-web/main/safari/chatgpt-ios-gestures.user.js
// ==/UserScript==

(() => {
  'use strict';

  const VERSION = '0.2.0';
  const GLOBAL_KEY = 'ChatGPTIOSGestures';

  const HOST =
    location.hostname.toLowerCase();

  if (
    HOST !== 'chatgpt.com' &&
    !HOST.endsWith('.chatgpt.com')
  ) {
    return;
  }

  try {
    window[GLOBAL_KEY]?.destroy?.();
  } catch (_) {}

  if (
    !window.__CHATGPT_NATIVE__?.hotUpdate ||
    window.__CHATGPT_NATIVE__
      ?.nativeGestures !== true
  ) {
    return;
  }

  const CONFIG = Object.freeze({
    triggerPx: 6,
    axisRatio: 0.75,
    horizontalReleaseRatio: 1.15,
    multiplier: 1.0,
  });

  const state = {
    scroll: null,
    listening: false,
    destroyed: false,
  };

  function visible(node) {
    return (
      node instanceof HTMLElement &&
      node.getClientRects().length > 0
    );
  }

  function isScrollable(node) {
    if (
      !(node instanceof HTMLElement) ||
      !visible(node)
    ) {
      return false;
    }

    const range =
      node.scrollHeight -
      node.clientHeight;

    if (
      range < 2 ||
      node.clientHeight < 24
    ) {
      return false;
    }

    const overflowY =
      String(
        getComputedStyle(node)
          .overflowY || ''
      );

    return (
      /(auto|scroll|overlay)/i
        .test(overflowY) ||
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
    if (!isScrollable(node)) {
      return false;
    }

    const max = Math.max(
      0,
      node.scrollHeight -
        node.clientHeight
    );

    if (delta > 0) {
      return node.scrollTop < max - 1;
    }

    if (delta < 0) {
      return node.scrollTop > 1;
    }

    return false;
  }

  function touchCenter(touches) {
    if (
      !touches ||
      touches.length < 2
    ) {
      return null;
    }

    return {
      x:
        (
          touches[0].clientX +
          touches[1].clientX
        ) / 2,
      y:
        (
          touches[0].clientY +
          touches[1].clientY
        ) / 2,
    };
  }

  function ancestorsOf(node) {
    const result = [];
    let current =
      node instanceof HTMLElement
        ? node
        : node?.parentElement;

    while (
      current instanceof HTMLElement
    ) {
      result.push(current);
      current = current.parentElement;
    }

    return result;
  }

  function pickScrollContainer(
    event,
    point,
    delta
  ) {
    const seen = new Set();
    const candidates = [];

    const add = (node) => {
      if (
        !(node instanceof HTMLElement) ||
        seen.has(node)
      ) {
        return;
      }

      seen.add(node);

      if (isScrollable(node)) {
        candidates.push(node);
      }
    };

    try {
      for (
        const node of
          document.elementsFromPoint(
            point.x,
            point.y
          )
      ) {
        for (
          const ancestor of
            ancestorsOf(node)
        ) {
          add(ancestor);
        }
      }
    } catch (_) {}

    for (
      const touch of
        Array.from(event.touches || [])
    ) {
      for (
        const ancestor of
          ancestorsOf(touch.target)
      ) {
        add(ancestor);
      }
    }

    for (const node of candidates) {
      if (canScrollBy(node, delta)) {
        return node;
      }
    }

    return null;
  }

  function detachActiveListeners() {
    if (!state.listening) {
      return;
    }

    state.listening = false;

    window.removeEventListener(
      'touchmove',
      move,
      true
    );
    window.removeEventListener(
      'touchend',
      end,
      true
    );
    window.removeEventListener(
      'touchcancel',
      end,
      true
    );
  }

  function finish() {
    state.scroll = null;
    detachActiveListeners();
  }

  function move(event) {
    const scroll = state.scroll;

    if (
      !scroll ||
      event.touches?.length < 2
    ) {
      finish();
      return;
    }

    const point =
      touchCenter(event.touches);

    if (!point) {
      finish();
      return;
    }

    const totalDx =
      point.x - scroll.startX;
    const totalDy =
      point.y - scroll.startY;

    if (!scroll.claimed) {
      if (
        Math.abs(totalDx) >=
          CONFIG.triggerPx &&
        Math.abs(totalDx) >
          Math.abs(totalDy) *
            CONFIG.horizontalReleaseRatio
      ) {
        // Native UIKit owns horizontal
        // two-finger navigation.
        finish();
        return;
      }

      if (
        Math.abs(totalDy) <
          CONFIG.triggerPx ||
        Math.abs(totalDy) <
          Math.abs(totalDx) *
            CONFIG.axisRatio
      ) {
        scroll.lastX = point.x;
        scroll.lastY = point.y;
        return;
      }

      scroll.claimed = true;
    }

    if (event.cancelable) {
      event.preventDefault();
    }
    event.stopImmediatePropagation();

    const deltaY =
      point.y - scroll.lastY;

    const scrollDelta =
      -deltaY * CONFIG.multiplier;

    if (!scroll.scroller) {
      scroll.scroller =
        pickScrollContainer(
          event,
          point,
          scrollDelta
        );
    }

    if (
      scroll.scroller instanceof
        HTMLElement
    ) {
      const max = Math.max(
        0,
        scroll.scroller.scrollHeight -
          scroll.scroller.clientHeight
      );

      scroll.scroller.scrollTop =
        Math.min(
          max,
          Math.max(
            0,
            scroll.scroller.scrollTop +
              scrollDelta
          )
        );
    }

    scroll.lastX = point.x;
    scroll.lastY = point.y;
  }

  function end(event) {
    if (
      !event?.touches ||
      event.touches.length < 2
    ) {
      finish();
    }
  }

  function begin(event) {
    if (
      state.destroyed ||
      state.scroll ||
      event.touches?.length !== 2
    ) {
      return;
    }

    const point =
      touchCenter(event.touches);

    if (!point) {
      return;
    }

    state.scroll = {
      startX: point.x,
      startY: point.y,
      lastX: point.x,
      lastY: point.y,
      scroller: null,
      claimed: false,
    };

    state.listening = true;

    window.addEventListener(
      'touchmove',
      move,
      {
        passive: false,
        capture: true,
      }
    );
    window.addEventListener(
      'touchend',
      end,
      {
        passive: true,
        capture: true,
      }
    );
    window.addEventListener(
      'touchcancel',
      end,
      {
        passive: true,
        capture: true,
      }
    );
  }

  function install() {
    window.addEventListener(
      'touchstart',
      begin,
      {
        passive: true,
        capture: true,
      }
    );
  }

  function destroy() {
    if (state.destroyed) {
      return;
    }

    state.destroyed = true;
    finish();

    window.removeEventListener(
      'touchstart',
      begin,
      true
    );

    try {
      delete window[GLOBAL_KEY];
    } catch (_) {
      window[GLOBAL_KEY] = undefined;
    }
  }

  window[GLOBAL_KEY] = {
    version: VERSION,
    config: CONFIG,
    destroy,
  };

  install();
})();
