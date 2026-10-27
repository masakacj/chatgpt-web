import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const observerCode = readFileSync(new URL('../../OptimizedResources/Observation/conversation-observer.js', import.meta.url), 'utf8');
const adapterCode = readFileSync(new URL('../../OptimizedResources/Observation/pc-long-chat-adapter.js', import.meta.url), 'utf8');

function createEnvironment(initialHref = 'https://chatgpt.com/c/123456789012') {
  const events = [];
  const timers = new Map();
  let nextTimerId = 1;
  let currentTime = 1000;

  const docListeners = new Map();
  const winListeners = new Map();

  class MockElement {
    constructor(tagName = 'div', attrs = {}) {
      this.tagName = tagName.toUpperCase();
      this.attrs = new Map(Object.entries(attrs));
      this.children = [];
      this.parentElement = null;
      this.textContent = '';
      this.disabled = false;
      this.isConnected = true;
    }
    getAttribute(k) { return this.attrs.get(k) ?? null; }
    hasAttribute(k) { return this.attrs.has(k); }
    setAttribute(k, v) { this.attrs.set(k, String(v)); }
    removeAttribute(k) { this.attrs.delete(k); }
    appendChild(child) {
      child.parentElement = this;
      this.children.push(child);
      return child;
    }
    closest(sel) {
      if (this.matches(sel)) return this;
      return this.parentElement?.closest(sel) || null;
    }
    matches(sel) {
      const parts = sel.split(',').map(s => s.trim().toLowerCase());
      for (const p of parts) {
        if (p === 'button' && this.tagName === 'BUTTON') return true;
        if (p === 'textarea' && this.tagName === 'TEXTAREA') return true;
        if (p === 'iframe' && this.tagName === 'IFRAME') return true;
        if (p === 'main' && this.tagName === 'MAIN') return true;
        if (p === '.markdown' && (this.attrs.get('class') || '').includes('markdown')) return true;
        if (p.startsWith('#') && this.attrs.get('id') === p.slice(1)) return true;
        if (p.startsWith('[data-testid=') && this.attrs.get('data-testid') === p.slice(14, -2)) return true;
        if (p.includes('data-testid*="approval"')) {
          const testid = this.attrs.get('data-testid') || '';
          if (/approval/i.test(testid)) return true;
        }
        if (p.includes('data-testid*="permission"')) {
          const testid = this.attrs.get('data-testid') || '';
          if (/permission/i.test(testid)) return true;
        }
        if (p.includes('data-testid="stop-button"')) {
          if (this.attrs.get('data-testid') === 'stop-button') return true;
        }
        if (p.includes('data-testid="send-button"')) {
          if (this.attrs.get('data-testid') === 'send-button') return true;
        }
        if (p.includes('aria-label*="approve"') || p.includes('aria-label*="授权"')) {
          const label = this.attrs.get('aria-label') || '';
          if (/approve|授权/i.test(label)) return true;
        }
        if (p.includes('aria-label*="stop generating"') || p.includes('aria-label*="停止生成"')) {
          const label = this.attrs.get('aria-label') || '';
          if (/stop generating|停止生成/i.test(label)) return true;
        }
        if (p.includes('data-talvt-turn-state')) {
          if (this.attrs.has('data-talvt-turn-state')) return true;
        }
        if (p.includes('data-turn-key')) {
          if (this.attrs.has('data-turn-key')) return true;
        }
        if (p.includes('data-testid^="conversation-turn-"')) {
          const id = this.attrs.get('data-testid') || '';
          if (id.startsWith('conversation-turn-')) return true;
        }
        if (p.includes('class*="dilresponseroot"') || p.includes('class*="markdownroot"')) {
          const cls = (this.attrs.get('class') || '').toLowerCase();
          if (cls.includes('dilresponseroot') || cls.includes('markdownroot')) return true;
        }
        if (p.includes('data-dil-message-id')) {
          if (this.attrs.has('data-dil-message-id')) return true;
        }
        if (p.includes('data-message-author-role="assistant"')) {
          if (this.attrs.get('data-message-author-role') === 'assistant') return true;
        }
        if (p.includes('data-optimized-pc-history')) {
          if (this.attrs.has('data-optimized-pc-history')) return true;
        }
      }
      return false;
    }
    querySelector(sel) {
      return this.querySelectorAll(sel)[0] || null;
    }
    querySelectorAll(sel) {
      const results = [];
      const traverse = node => {
        for (const child of node.children) {
          if (child.matches(sel)) results.push(child);
          traverse(child);
        }
      };
      traverse(this);
      return results;
    }
    getClientRects() { return [{ width: 100, height: 100, top: 0, bottom: 100 }]; }
    getBoundingClientRect() { return { width: 100, height: 100, top: 0, bottom: 100 }; }
  }

  class MockHTMLElement extends MockElement {
    static [Symbol.hasInstance](inst) { return Boolean(inst && inst.tagName); }
  }

  const main = new MockHTMLElement('main');
  const transcript = new MockHTMLElement('div', { class: 'transcriptContent' });
  main.appendChild(transcript);

  const doc = {
    visibilityState: 'visible',
    hidden: false,
    querySelector: sel => {
      if (sel.includes('transcriptContent')) return transcript;
      if (sel === 'main') return main;
      return main.querySelector(sel);
    },
    querySelectorAll: sel => main.querySelectorAll(sel),
    getElementById: () => null,
    addEventListener: (type, fn) => {
      if (!docListeners.has(type)) docListeners.set(type, new Set());
      docListeners.get(type).add(fn);
    },
    removeEventListener: (type, fn) => {
      docListeners.get(type)?.delete(fn);
    },
    dispatchEvent: event => {
      docListeners.get(event.type)?.forEach(fn => fn(event));
    }
  };

  const win = {
    location: {
      origin: 'https://chatgpt.com',
      href: initialHref
    },
    webkit: {
      messageHandlers: {
        optimizedConversation: {
          postMessage: async body => {
            events.push(body);
            return { ok: true };
          }
        }
      }
    },
    addEventListener: (type, fn) => {
      if (!winListeners.has(type)) winListeners.set(type, new Set());
      winListeners.get(type).add(fn);
    },
    removeEventListener: (type, fn) => {
      winListeners.get(type)?.delete(fn);
    }
  };
  win.top = win;
  win.window = win;

  class MockMutationObserver {
    constructor(cb) { this.cb = cb; }
    observe() {}
    disconnect() {}
  }

  const setTimeoutMock = (fn, ms = 0) => {
    const id = nextTimerId++;
    timers.set(id, { fn, fireAt: currentTime + ms, ms });
    return id;
  };
  const clearTimeoutMock = id => {
    timers.delete(id);
  };

  const advanceTimersByTime = async ms => {
    const target = currentTime + ms;
    while (true) {
      let earliestId = null;
      let earliestTime = Infinity;
      for (const [id, timer] of timers) {
        if (timer.fireAt <= target && timer.fireAt < earliestTime) {
          earliestTime = timer.fireAt;
          earliestId = id;
        }
      }
      if (!earliestId) break;
      const timer = timers.get(earliestId);
      timers.delete(earliestId);
      currentTime = timer.fireAt;
      timer.fn();
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    currentTime = target;
    await new Promise(resolve => setTimeout(resolve, 10));
  };

  const context = {
    window: win,
    top: win,
    location: win.location,
    document: doc,
    HTMLElement: MockHTMLElement,
    Element: MockElement,
    MutationObserver: MockMutationObserver,
    setTimeout: setTimeoutMock,
    clearTimeout: clearTimeoutMock,
    Date: {
      now: () => currentTime
    },
    crypto: {
      randomUUID: () => 'mock-uuid-1234'
    },
    getComputedStyle: () => ({ visibility: 'visible' }),
    URL,
    setImmediate
  };

  return {
    context,
    doc,
    win,
    main,
    transcript,
    events,
    timers,
    advanceTimersByTime,
    triggerDocEvent: (type, target) => {
      docListeners.get(type)?.forEach(fn => fn({ type, target }));
    },
    MockHTMLElement
  };
}

test('H1 avalanche: 10+ consecutive complete/no-answer events schedule at most 3 bounded follow-up callbacks', async () => {
  const env = createEnvironment('https://chatgpt.com/c/123456789012');
  runInNewContext(adapterCode, env.context);
  runInNewContext(observerCode, env.context);

  await env.advanceTimersByTime(10);
  assert.equal(env.events[0]?.type, 'boot');

  // Turn is completed but answer text is not ready
  const turn = new env.MockHTMLElement('div', {
    'data-turn-key': 'turn-001',
    'data-talvt-turn-state': 'completed'
  });
  env.transcript.appendChild(turn);

  // Trigger observation for the turn
  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  // Check initial follow-ups scheduled (500, 1800, 5500)
  let followUps = Array.from(env.timers.values()).filter(t => [500, 1800, 5500].includes(t.ms));
  assert.equal(followUps.length, 3, 'Initial observation schedules exactly 3 follow-ups');

  // Trigger 15 consecutive complete/no-answer events for the same turn
  for (let i = 0; i < 15; i++) {
    env.doc.dispatchEvent({ type: 'visibilitychange' });
    await env.advanceTimersByTime(5);
  }

  // Verify timer count did not multiply
  followUps = Array.from(env.timers.values()).filter(t => [500, 1800, 5500].includes(t.ms));
  assert.equal(followUps.length, 3, 'No recursive re-arming: remains bounded at 3 follow-ups');

  // Track the actual execution of follow-up callbacks
  let followUpFires = 0;
  for (const [id, t] of env.timers) {
    if ([500, 1800, 5500].includes(t.ms)) {
      const origFn = t.fn;
      t.fn = () => { followUpFires++; origFn(); };
    }
  }

  // Advance time past all 3 follow-ups (5500ms)
  await env.advanceTimersByTime(6000);

  // Exactly 3 follow-up callbacks fired
  assert.equal(followUpFires, 3, 'Follow-up callbacks fire exactly 3 times across [500, 1800, 5500]');

  // No lingering follow-up timers remain
  const remaining = Array.from(env.timers.values()).filter(t => [500, 1800, 5500].includes(t.ms));
  assert.equal(remaining.length, 0, 'All follow-up callbacks resolved without self-propagation');
});

test('H1 route: route change invalidates pending follow-up timers and resets state', async () => {
  const env = createEnvironment('https://chatgpt.com/c/111111111111');
  runInNewContext(adapterCode, env.context);
  runInNewContext(observerCode, env.context);

  await env.advanceTimersByTime(10);

  const turn = new env.MockHTMLElement('div', {
    'data-turn-key': 'turn-c1',
    'data-talvt-turn-state': 'completed'
  });
  env.transcript.appendChild(turn);

  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  let followUps = Array.from(env.timers.values()).filter(t => [500, 1800, 5500].includes(t.ms));
  assert.equal(followUps.length, 3);

  // Switch route to conversation 2
  env.win.location.href = 'https://chatgpt.com/c/222222222222';
  env.win.location.pathname = '/c/222222222222';
  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  // Old follow-up timers must be cancelled
  followUps = Array.from(env.timers.values()).filter(t => [500, 1800, 5500].includes(t.ms));
  assert.equal(followUps.length, 0, 'Route change invalidates old follow-up timers');

  // Verify events for old conversation do not fire late
  const eventsBefore = env.events.length;
  await env.advanceTimersByTime(6000);
  const oldConversationEvents = env.events.slice(eventsBefore).filter(e => e.observation?.conversationId === '111111111111');
  assert.equal(oldConversationEvents.length, 0, 'No late events emitted for old conversation');
});

test('H1 destroy: observer destroy cancels all timers and removes listeners', async () => {
  const env = createEnvironment('https://chatgpt.com/c/123456789012');
  runInNewContext(adapterCode, env.context);
  runInNewContext(observerCode, env.context);

  await env.advanceTimersByTime(10);

  const turn = new env.MockHTMLElement('div', {
    'data-turn-key': 'turn-destroy',
    'data-talvt-turn-state': 'completed'
  });
  env.transcript.appendChild(turn);

  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  assert.ok(Array.from(env.timers.values()).some(t => [500, 1800, 5500].includes(t.ms)));

  // Destroy observer
  const obs = env.context.__CHATGPT_WEB_OPTIMIZED_OBSERVER__;
  obs.destroy();

  assert.equal(env.timers.size, 0, 'All timers cleared on destroy');

  // Advancing time should not fire anything
  const countBefore = env.events.length;
  await env.advanceTimersByTime(6000);
  assert.equal(env.events.length, countBefore, 'No events emitted after destroy');
});

test('H1 visibility: background hidden suppresses recurring scans, foreground restores native evidence', async () => {
  const env = createEnvironment('https://chatgpt.com/c/123456789012');
  runInNewContext(adapterCode, env.context);
  runInNewContext(observerCode, env.context);

  await env.advanceTimersByTime(10);

  // Set running state
  const turn = new env.MockHTMLElement('div', {
    'data-turn-key': 'turn-run',
    'data-talvt-turn-state': 'running'
  });
  env.transcript.appendChild(turn);

  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  // While visible and running, activeTimer is scheduled (2500ms)
  let activeTimers = Array.from(env.timers.values()).filter(t => t.ms === 2500);
  assert.equal(activeTimers.length, 1, 'Active timer scheduled while visible and running');

  // App enters background
  env.doc.hidden = true;
  env.doc.visibilityState = 'hidden';
  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  // Active timer must be cleared immediately
  activeTimers = Array.from(env.timers.values()).filter(t => t.ms === 2500);
  assert.equal(activeTimers.length, 0, 'Active timer cancelled on hidden');

  // Advance time while hidden: no recurring scans should be scheduled
  await env.advanceTimersByTime(15000);
  activeTimers = Array.from(env.timers.values()).filter(t => t.ms === 2500);
  assert.equal(activeTimers.length, 0, 'No recurring scans while hidden in background');

  // App returns to foreground; turn is now completed with real evidence
  env.doc.hidden = false;
  env.doc.visibilityState = 'visible';
  turn.setAttribute('data-talvt-turn-state', 'running'); // still running in DOM

  const countBefore = env.events.length;
  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  // Foreground restores native evidence (reported as running, NOT falsely completed)
  const latestEvent = env.events[env.events.length - 1];
  assert.equal(latestEvent?.observation?.nativeStatus, 'running', 'Native evidence restored without false completion');
});

test('H1 waiting: approval buttons report waiting and suppress unneeded scans', async () => {
  const env = createEnvironment('https://chatgpt.com/c/123456789012');
  runInNewContext(adapterCode, env.context);
  runInNewContext(observerCode, env.context);

  await env.advanceTimersByTime(10);

  const turn = new env.MockHTMLElement('div', { 'data-turn-key': 'turn-wait' });
  const approvalDiv = new env.MockHTMLElement('div', { 'data-testid': 'approval-panel' });
  const approveBtn = new env.MockHTMLElement('button', { 'aria-label': 'Approve tool execution' });
  approvalDiv.appendChild(approveBtn);
  turn.appendChild(approvalDiv);
  env.transcript.appendChild(turn);

  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  const lastEvent = env.events[env.events.length - 1];
  assert.equal(lastEvent?.observation?.waiting, true);
  assert.equal(lastEvent?.observation?.nativeStatus, 'waiting');

  // No active scan timer should be scheduled while waiting for user approval
  const activeTimers = Array.from(env.timers.values()).filter(t => t.ms === 2500);
  assert.equal(activeTimers.length, 0, 'No recurring scans while waiting for user approval');
});

test('H1 answer-ready: arrival of answer cancels follow-ups and reports answerReady', async () => {
  const env = createEnvironment('https://chatgpt.com/c/123456789012');
  runInNewContext(adapterCode, env.context);
  runInNewContext(observerCode, env.context);

  await env.advanceTimersByTime(10);

  const turn = new env.MockHTMLElement('div', {
    'data-turn-key': 'turn-ans',
    'data-talvt-turn-state': 'completed'
  });
  env.transcript.appendChild(turn);

  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  let followUps = Array.from(env.timers.values()).filter(t => [500, 1800, 5500].includes(t.ms));
  assert.equal(followUps.length, 3);

  // Markdown answer arrives in the turn
  const answerNode = new env.MockHTMLElement('div', { class: 'MarkdownRoot' });
  answerNode.textContent = 'Here is the completed answer.';
  turn.appendChild(answerNode);

  // Trigger observation (e.g. from 500ms follow-up)
  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  const lastEvent = env.events[env.events.length - 1];
  assert.equal(lastEvent?.observation?.answerReady, true);
  assert.equal(lastEvent?.observation?.hasAnswer, true);

  // Remaining follow-ups must be cancelled now that answer is ready
  followUps = Array.from(env.timers.values()).filter(t => [500, 1800, 5500].includes(t.ms));
  assert.equal(followUps.length, 0, 'Follow-up timers cancelled once answer becomes ready');
});

test('H1 adapter idempotency: repeated refresh on stable history does not reapply attributes', () => {
  const idle = [];
  const ATTR = 'data-optimized-pc-history';
  const turns = Array.from({ length: 30 }, (_, i) => ({
    index: i,
    isConnected: true,
    attrs: new Map(),
    parentElement: { closest: () => null },
    setAttribute(k, v) { this.attrs.set(k, v); setCalls++; },
    removeAttribute(k) { this.attrs.delete(k); },
    getAttribute(k) { return this.attrs.get(k) ?? null; },
    hasAttribute(k) { return this.attrs.has(k); },
    querySelector: () => null
  }));

  let setCalls = 0;
  const doc = {
    hidden: false,
    head: { appendChild: () => {} },
    documentElement: { appendChild: () => {} },
    createElement: () => ({ remove: () => {} }),
    getElementById: () => null,
    querySelectorAll: sel => sel === '[' + ATTR + ']' ? turns.filter(t => t.attrs.has(ATTR)) : []
  };

  const win = { top: null };
  win.top = win;
  const world = {
    window: win, top: win,
    location: { origin: 'https://chatgpt.com' },
    document: doc,
    __OPTIMIZED_PC_HISTORY_ENABLED__: true,
    requestIdleCallback: fn => idle.push(fn),
    setTimeout: fn => idle.push(fn),
    Date
  };

  runInNewContext(adapterCode, world);
  const adapter = world.__CHATGPT_WEB_PC_LONG_CHAT__;

  // First refresh: optimizes history (18 turns)
  adapter.refresh('chat-stable', turns, { running: false, waiting: false });
  while (idle.length) idle.shift()();
  assert.equal(turns.filter(t => t.attrs.has(ATTR)).length, 18);
  assert.equal(setCalls, 18);

  // Second refresh on stable history after 15 seconds: should NOT reapply setAttribute
  const timeOriginal = Date.now;
  try {
    Date.now = () => timeOriginal() + 15000;
    adapter.refresh('chat-stable', turns, { running: false, waiting: false });
    while (idle.length) idle.shift()();

    // setCalls should NOT have increased because turns are already marked
    assert.equal(setCalls, 18, 'Idempotent: setAttribute not called on already marked turns');
    assert.equal(turns.filter(t => t.attrs.has(ATTR)).length, 18);
  } finally {
    Date.now = timeOriginal;
  }
});

test('H1 adapter safety: approval blocks and iframes are untouched by history adapter', () => {
  const idle = [];
  const ATTR = 'data-optimized-pc-history';
  const turns = Array.from({ length: 30 }, (_, i) => ({
    index: i,
    isConnected: true,
    attrs: new Map(),
    parentElement: { closest: () => null },
    setAttribute(k, v) { this.attrs.set(k, v); },
    removeAttribute(k) { this.attrs.delete(k); },
    getAttribute(k) { return this.attrs.get(k) ?? null; },
    hasAttribute(k) { return this.attrs.has(k); },
    matches(sel) { return sel === 'iframe' && i === 2; },
    querySelector(sel) {
      if (i === 0 && sel.includes('approval')) return {};
      if (i === 1 && sel.includes('iframe')) return {};
      return null;
    }
  }));

  const doc = {
    hidden: false,
    head: { appendChild: () => {} },
    documentElement: { appendChild: () => {} },
    createElement: () => ({ remove: () => {} }),
    getElementById: () => null,
    querySelectorAll: sel => sel === '[' + ATTR + ']' ? turns.filter(t => t.attrs.has(ATTR)) : []
  };

  const win = { top: null };
  win.top = win;
  const world = {
    window: win, top: win,
    location: { origin: 'https://chatgpt.com' },
    document: doc,
    __OPTIMIZED_PC_HISTORY_ENABLED__: true,
    requestIdleCallback: fn => idle.push(fn),
    setTimeout: fn => idle.push(fn),
    Date
  };

  runInNewContext(adapterCode, world);
  const adapter = world.__CHATGPT_WEB_PC_LONG_CHAT__;

  adapter.refresh('chat-iframe-approval', turns, { running: false, waiting: false });
  while (idle.length) idle.shift()();

  // Turn 0 (approval), Turn 1 (contains iframe), Turn 2 (is iframe) must NOT have ATTR
  assert.equal(turns[0].attrs.has(ATTR), false, 'Turn with approval is untouched');
  assert.equal(turns[1].attrs.has(ATTR), false, 'Turn containing iframe is untouched');
  assert.equal(turns[2].attrs.has(ATTR), false, 'Turn matching iframe is untouched');

  // Latest 12 turns (18..29) must also be untouched
  for (let i = 18; i < 30; i++) {
    assert.equal(turns[i].attrs.has(ATTR), false, `Latest turn ${i} is untouched`);
  }
});

test('H1 new-turn: new turn invalidates prior turn follow-ups and arms for new turn', async () => {
  const env = createEnvironment('https://chatgpt.com/c/123456789012');
  runInNewContext(adapterCode, env.context);
  runInNewContext(observerCode, env.context);

  await env.advanceTimersByTime(10);

  // Turn 1 completed without answer
  const turn1 = new env.MockHTMLElement('div', {
    'data-turn-key': 'turn-101',
    'data-talvt-turn-state': 'completed'
  });
  env.transcript.appendChild(turn1);

  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  let followUps = Array.from(env.timers.values()).filter(t => [500, 1800, 5500].includes(t.ms));
  assert.equal(followUps.length, 3, 'Turn 1 arms 3 follow-ups');

  // Turn 2 arrives (new turn) and also completes
  const turn2 = new env.MockHTMLElement('div', {
    'data-turn-key': 'turn-102',
    'data-talvt-turn-state': 'completed'
  });
  env.transcript.appendChild(turn2);

  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  // Turn 1 follow-ups must be invalidated; exactly 3 follow-ups for Turn 2 should exist
  followUps = Array.from(env.timers.values()).filter(t => [500, 1800, 5500].includes(t.ms));
  assert.equal(followUps.length, 3, 'Old turn follow-ups invalidated, new turn armed exactly 3');

  const latestEvent = env.events[env.events.length - 1];
  assert.equal(latestEvent?.observation?.turnKey, 'turn-102', 'Latest event reflects new turn key');
});

test('H1 streaming & stop: stop button click halts active generation and clears active timer', async () => {
  const env = createEnvironment('https://chatgpt.com/c/123456789012');
  runInNewContext(adapterCode, env.context);
  runInNewContext(observerCode, env.context);

  await env.advanceTimersByTime(10);

  const turn = new env.MockHTMLElement('div', { 'data-turn-key': 'turn-stream' });
  const stopBtn = new env.MockHTMLElement('button', {
    'data-testid': 'stop-button',
    'aria-label': 'Stop generating'
  });
  env.transcript.appendChild(turn);
  env.transcript.appendChild(stopBtn);

  env.doc.dispatchEvent({ type: 'visibilitychange' });
  await env.advanceTimersByTime(10);

  const runningEvent = env.events[env.events.length - 1];
  assert.equal(runningEvent?.observation?.running, true);
  assert.equal(runningEvent?.observation?.nativeStatus, 'running');

  // Active recurring timer is armed while streaming
  let activeTimers = Array.from(env.timers.values()).filter(t => t.ms === 2500);
  assert.equal(activeTimers.length, 1, 'Active timer running during streaming');

  // User clicks stop button
  env.triggerDocEvent('click', stopBtn);
  await env.advanceTimersByTime(10);

  // Stop button clicked clears active recurring timer
  activeTimers = Array.from(env.timers.values()).filter(t => t.ms === 2500);
  assert.equal(activeTimers.length, 0, 'Active timer cancelled when stop clicked');

  const stopEvent = env.events.find(e => e.observation?.kind === 'stop');
  assert.ok(stopEvent, 'Stop event was reported');
});

test('H1 short/long chat switching: adapter resets attributes when shrinking below 24 turns', () => {
  const idle = [];
  const ATTR = 'data-optimized-pc-history';
  const turns = Array.from({ length: 30 }, (_, i) => ({
    index: i,
    isConnected: true,
    attrs: new Map(),
    parentElement: { closest: () => null },
    setAttribute(k, v) { this.attrs.set(k, v); },
    removeAttribute(k) { this.attrs.delete(k); },
    getAttribute(k) { return this.attrs.get(k) ?? null; },
    hasAttribute(k) { return this.attrs.has(k); },
    querySelector: () => null
  }));

  const doc = {
    hidden: false,
    head: { appendChild: () => {} },
    documentElement: { appendChild: () => {} },
    createElement: () => ({ remove: () => {} }),
    getElementById: () => null,
    querySelectorAll: sel => sel === '[' + ATTR + ']' ? turns.filter(t => t.attrs.has(ATTR)) : []
  };

  const win = { top: null };
  win.top = win;
  const world = {
    window: win, top: win,
    location: { origin: 'https://chatgpt.com' },
    document: doc,
    __OPTIMIZED_PC_HISTORY_ENABLED__: true,
    requestIdleCallback: fn => idle.push(fn),
    setTimeout: fn => idle.push(fn),
    Date
  };

  runInNewContext(adapterCode, world);
  const adapter = world.__CHATGPT_WEB_PC_LONG_CHAT__;

  // 30 turns optimizes history
  adapter.refresh('chat-switch', turns, { running: false, waiting: false });
  while (idle.length) idle.shift()();
  assert.equal(turns.filter(t => t.attrs.has(ATTR)).length, 18);

  // Shrinks to 10 turns (short chat): must reset all optimized attributes
  const shortTurns = turns.slice(0, 10);
  adapter.refresh('chat-switch', shortTurns, { running: false, waiting: false });
  while (idle.length) idle.shift()();
  assert.equal(turns.some(t => t.attrs.has(ATTR)), false, 'Short chat shrinks below 24 turns, all attributes reset');
});
