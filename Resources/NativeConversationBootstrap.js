// Native app bootstrap only. No network hooks, request replay, or page pruning.
(() => {
  'use strict';
  if (window !== window.top || location.origin !== 'https://chatgpt.com' ||
      !window.webkit?.messageHandlers?.chatGPTNative) return;
  window.__CHATGPT_NATIVE_PARITY__ = true;
  const token = String(performance.timeOrigin) + '-' + Math.random().toString(36).slice(2);
  const mark = () => document.documentElement?.setAttribute('data-native-conversation-document',token);
  mark();
  document.addEventListener('DOMContentLoaded',mark,{once:true});
})();
