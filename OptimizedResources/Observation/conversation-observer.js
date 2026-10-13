(() => {
  'use strict';
  if (window !== window.top || location.origin !== 'https://chatgpt.com' ||
      !window.webkit?.messageHandlers?.optimizedConversation) return;
  const VERSION = '0.1.0';
  const api = window.webkit.messageHandlers.optimizedConversation;
  const documentId = 'wk-' + (crypto.randomUUID?.() || Math.random().toString(36).slice(2));
  const timers = new Set();
  let current = null, priorTurnKey = null, lastTurnKey = null;
  let observer = null, observedList = null, observedState = null;
  let eventTimer = 0, activeTimer = 0, routeSerial = 0, sequence = 0;
  let submitUntil = 0, recoveryCanceled = false, destroyed = false;

  const later = (fn, ms) => {
    const timer = setTimeout(() => { timers.delete(timer); if (!destroyed) fn(); }, ms);
    timers.add(timer); return timer;
  };
  const visible = node => node instanceof HTMLElement && !node.closest('[hidden],[aria-hidden="true"]') &&
    node.getClientRects().length > 0 && getComputedStyle(node).visibility !== 'hidden';
  const conversationId = (href = location.href) => {
    try {
      const url = new URL(href, location.href);
      return url.origin === location.origin ? url.pathname.match(/(?:^|\/)c\/([A-Za-z0-9_-]{12,80})(?:\/|$)/)?.[1] || null : null;
    } catch { return null; }
  };
  const send = async body => {
    try { return await api.postMessage({ ...body, document: documentId }); }
    catch { return null; }
  };
  const latest = () => {
    const root = document.querySelector('main [class*="transcriptContent"]') || document.querySelector('main');
    const turns = root?.querySelectorAll('[data-turn-key],[data-testid^="conversation-turn-"]') || [];
    const turn = turns[turns.length - 1] || null;
    const states = turn?.querySelectorAll('[data-talvt-turn-state]') || [];
    const stateNode = turn?.hasAttribute('data-talvt-turn-state') ? turn : states[states.length - 1] || null;
    return { root, turn, stateNode, key: turn?.getAttribute('data-turn-key') || turn?.getAttribute('data-testid') || null };
  };
  const answerReady = turn => {
    if (!turn) return false;
    const valid = node => Boolean((node?.textContent || '').trim()) &&
      !node.closest('[data-testid*="activity" i],[data-testid*="reasoning" i],[class*="group/activity-header"]');
    const roots = turn.querySelectorAll('[class*="DilResponseRoot"],[data-dil-message-id],[class*="MarkdownRoot"],[data-message-author-role="assistant"]');
    if ([...roots].some(valid)) return true;
    const headings = turn.querySelectorAll('h4[data-conversation-role="assistant"],h4[data-message-author-role="assistant"]');
    return [...headings].some(heading => {
      const sibling = heading.nextElementSibling;
      if (!sibling || !valid(sibling)) return false;
      const bodies = sibling.matches('[class*="MarkdownRoot"],[class*="DilResponseRoot"],.markdown') ?
        [sibling] : [...sibling.querySelectorAll('[class*="MarkdownRoot"],[class*="DilResponseRoot"],.markdown')];
      return bodies.some(valid);
    });
  };
  const loadError = main => {
    if (!main) return null;
    const loadMessage = /(?:unable|failed|could not|couldn.t)\s+(?:to\s+)?load\s+(?:(?:this|the)\s+)?(?:(?:chatgpt|gpt)\s+)?(?:conversation|chat)|(?:对话|会话).{0,12}加载失败|(?:无法|未能)加载.{0,8}(?:对话|会话)|error loading (?:(?:this|the)\s+)?(?:(?:chatgpt|gpt)\s+)?(?:conversation|chat)/i;
    const button = root => [...root.querySelectorAll('button')].find(node => visible(node) && !node.disabled &&
      /^(?:retry|try again|reload|重试|重新加载|再试一次)$/i.test((node.textContent || node.getAttribute('aria-label') || '').trim()));
    const noTurns = !main.querySelector('[data-turn-key],[data-testid^="conversation-turn-"]');
    const panels = (noTurns ? document : main).querySelectorAll('[data-testid*="conversation-error" i],[data-testid*="error-boundary" i],[role="alert"]');
    for (const panel of panels) {
      if (!visible(panel) || panel.closest('[data-turn-key],[data-testid^="conversation-turn-"]')) continue;
      const text = (panel.textContent || '').trim().slice(0, 1200);
      const named = /conversation-error|error-boundary/i.test(panel.getAttribute('data-testid') || '');
      if (loadMessage.test(text) || (named && /something went wrong|出错|发生错误|try again/i.test(text))) {
        return { panel, button: button(panel) || null };
      }
    }
    if (!noTurns) return null;
    const text = (main.textContent || '').trim();
    if (text.length > 800 || !loadMessage.test(text)) return null;
    return { panel: main, button: button(main) || null };
  };
  const snapshot = () => {
    const { root, turn, stateNode, key } = latest();
    const raw = stateNode?.getAttribute('data-talvt-turn-state') || '';
    const currentTurn = !(priorTurnKey && key === priorTurnKey);
    const newTurn = Boolean(currentTurn && key && lastTurnKey && key !== lastTurnKey);
    if (currentTurn && key) { priorTurnKey = null; lastTurnKey = key; }
    const waiting = ['waiting_user','waiting_for_user','waiting','approval'].includes(raw) || Boolean(turn &&
      [...turn.querySelectorAll('[data-testid*="approval" i] button,[data-testid*="permission" i] button,button[aria-label*="Approve" i],button[aria-label*="授权"]')].some(visible));
    const stopVisible = Boolean(root && [...root.querySelectorAll('button[data-testid="stop-button"],button[aria-label*="Stop generating" i],button[aria-label*="停止生成"]')].some(visible));
    const running = ['running','in_progress','streaming','thinking'].includes(raw) || (!raw && stopVisible);
    const fields = [...document.querySelectorAll('#prompt-textarea,main textarea,main [contenteditable="true"]')];
    const hasDraft = fields.some(node => ((node.value || node.textContent || '').trim().length > 0));
    const error = loadError(root || document.querySelector('main'));
    let nativeStatus = 'unknown';
    if (waiting) nativeStatus = 'waiting';
    else if (running) nativeStatus = 'running';
    else if (['complete','completed','done'].includes(raw)) nativeStatus = 'completed';
    else if (['error','failed','errored'].includes(raw)) nativeStatus = 'error';
    else if (['cancelled','canceled','stopped'].includes(raw)) {
      const failed = turn && [...turn.querySelectorAll('span,div,p,small,strong,[role="status"]')].some(node => {
        const text = (node.textContent || '').trim();
        return visible(node) && text.length <= 70 && /^(?:无法思考|无法继续思考|思考失败|could(?: not|n't) think|unable to think|thinking failed|failed to think)$/i.test(text) &&
          !node.closest('[data-conversation-role="user"],[data-message-author-role="user"]');
      });
      nativeStatus = failed ? 'error' : 'stopped';
    }
    return {
      conversationId: current, turnKey: key, currentTurn, nativeStatus,
      answerReady: answerReady(turn), visible: document.visibilityState === 'visible',
      selected: document.visibilityState === 'visible' && current === conversationId(),
      newTurn,
      activeGenerationControl: stopVisible,
      hasDraft, running, waiting, hasAnswer: answerReady(turn),
      loadError: Boolean(error), canRetry: Boolean(error?.button),
      recoveryCanceled: recoveryCanceled || submitUntil > Date.now()
    };
  };
  const emit = async (kind = 'native', extra = {}) => {
    if (!current || destroyed) return;
    const value = { ...snapshot(), ...extra };
    const next = ++sequence;
    await send({ type: 'observe', observation: {
      ...value, kind, sequence: next, at: Date.now(),
      eventId: [documentId, next, kind].join(':')
    }});
    if (value.nativeStatus === 'completed' && !value.answerReady && value.turnKey && value.currentTurn && value.visible) {
      for (const ms of [500, 1800, 5500]) later(() => current === value.conversationId && emit(), ms);
    }
    if ((value.running && value.currentTurn) || submitUntil > Date.now()) watchActive();
  };
  const bind = () => {
    const { root, turn, stateNode } = latest();
    const list = turn?.parentElement || root;
    if (!list || (observer && observedList === list && observedState === stateNode)) return;
    observer?.disconnect(); observedList = list; observedState = stateNode;
    observer = new MutationObserver(() => {
      if (!eventTimer) eventTimer = later(() => { eventTimer = 0; bind(); emit(); }, 180);
    });
    observer.observe(list, { childList: true, subtree: false });
    if (stateNode && stateNode !== list) observer.observe(stateNode, { attributes: true, attributeFilter: ['data-talvt-turn-state'], subtree: false });
  };
  const watchActive = () => {
    if (activeTimer || destroyed) return;
    activeTimer = later(() => { activeTimer = 0; bind(); emit(); }, document.hidden ? 6000 : 2500);
  };
  const route = (force = false) => {
    const id = conversationId();
    if (!force && id === current) { bind(); return; }
    if (id !== current) {
      priorTurnKey = current ? lastTurnKey : null; current = id; routeSerial++;
      recoveryCanceled = false; submitUntil = 0;
      clearTimeout(activeTimer); timers.delete(activeTimer); activeTimer = 0;
      observer?.disconnect(); observedList = null; observedState = null;
    }
    const serial = routeSerial;
    for (const ms of [0, 450, 1600, 4500, 10000, 20000, 45000, 65000]) {
      later(() => serial === routeSerial && (bind(), emit()), ms);
    }
  };
  const submit = () => {
    if (!current) return;
    submitUntil = Date.now() + 30000; recoveryCanceled = true;
    emit('submit'); watchActive();
  };
  const clicked = event => {
    const target = event.target instanceof Element ? event.target : null;
    const button = target?.closest('button');
    if (button && !button.disabled && button.matches('[data-testid="send-button"],button[aria-label="Send prompt"],button[aria-label="发送消息"]')) submit();
    if (button?.matches('[data-testid="stop-button"]')) emit('stop', { turnKey: lastTurnKey });
    if (target?.closest('a[href*="/c/"],button[aria-label*="sidebar" i],button[aria-label*="侧边栏"]')) {
      for (const ms of [0, 200, 800, 2400]) later(() => route(), ms);
    }
  };
  const input = event => {
    if (event.target instanceof Element && event.target.closest('#prompt-textarea,textarea,[contenteditable="true"]')) recoveryCanceled = true;
  };
  const retry = (requestedDocument, requestedSequence) => {
    if (requestedDocument !== documentId || requestedSequence !== sequence || document.hidden) return false;
    const value = snapshot();
    if (!value.loadError || !value.canRetry || value.hasDraft || value.running || value.waiting || value.hasAnswer || value.recoveryCanceled) return false;
    const error = loadError(document.querySelector('main'));
    if (!error?.button || !visible(error.button) || error.button.disabled) return false;
    error.button.click();
    for (const ms of [400, 1600, 5000]) later(() => emit(), ms);
    return true;
  };
  const destroy = () => {
    destroyed = true; observer?.disconnect(); timers.forEach(clearTimeout); timers.clear();
    document.removeEventListener('click', clicked, true);
    document.removeEventListener('submit', submit, true);
    document.removeEventListener('input', input, true);
    delete globalThis.__CHATGPT_WEB_OPTIMIZED_OBSERVER__;
  };
  document.addEventListener('click', clicked, true);
  document.addEventListener('submit', submit, true);
  document.addEventListener('input', input, true);
  document.addEventListener('visibilitychange', () => !document.hidden && route());
  window.addEventListener('popstate', () => route());
  globalThis.__CHATGPT_WEB_OPTIMIZED_OBSERVER__ = { version: VERSION, documentId, retry, destroy,
    audit: () => ({ version: VERSION, documentId, sequence, attached: !destroyed, observer: Boolean(observedList?.isConnected) }) };
  send({ type: 'boot' }).then(reply => reply?.ok && route(true));
})();
