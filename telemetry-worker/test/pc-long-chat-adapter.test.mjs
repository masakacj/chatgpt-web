import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';

const code = readFileSync(new URL('../../OptimizedResources/Observation/pc-long-chat-adapter.js', import.meta.url), 'utf8');
const ATTR = 'data-optimized-pc-history';

function createMockElement(tag, attrs = {}, textContent = '', children = []) {
  const attrMap = new Map(Object.entries(attrs));
  const el = {
    tagName: tag.toUpperCase(),
    isConnected: true,
    attrs: attrMap,
    textContent,
    children: [...children],
    hasAttribute(k) { return this.attrs.has(k); },
    getAttribute(k) { return this.attrs.get(k) || null; },
    setAttribute(k, v) { this.attrs.set(k, String(v)); },
    removeAttribute(k) { this.attrs.delete(k); },
    matches(sel) {
      return sel.split(',').some(rule => {
        const item = rule.trim();
        const tag = item.match(/^([a-z]+)(?:\[|$)/i)?.[1];
        if (tag && this.tagName.toLowerCase() !== tag.toLowerCase()) return false;
        if (item === 'a[href]') return this.tagName === 'A' && this.attrs.has('href');
        if (item === '.markdown') return (this.attrs.get('class') || '').split(/\s+/).includes('markdown');
        if (/^[a-z]+$/i.test(item)) return this.tagName.toLowerCase() === item.toLowerCase();
        const attr = item.match(/\[([\w-]+)(\*|\^)?="([^"]+)"(?: i)?\]/);
        if (!attr) return false;
        const value = this.attrs.get(attr[1]);
        if (typeof value !== 'string') return false;
        if (!attr[2]) return value === attr[3];
        if (attr[2] === '^') return value.toLowerCase().startsWith(attr[3].toLowerCase());
        return value.toLowerCase().includes(attr[3].toLowerCase());
      });
    },
    closest(sel) {
      if (this.matches(sel)) return this;
      return this.parent ? this.parent.closest(sel) : null;
    },
    querySelector(sel) {
      for (const child of this.children) {
        if (child.matches(sel)) return child;
        const sub = child.querySelector(sel);
        if (sub) return sub;
      }
      return null;
    },
    querySelectorAll(sel) {
      const res = [];
      for (const child of this.children) {
        if (child.matches(sel)) res.push(child);
        res.push(...child.querySelectorAll(sel));
      }
      return res;
    }
  };
  for (const child of children) {
    child.parent = el;
    child.parentElement = el;
  }
  return el;
}

function fixture(enabled = true, count = 30, coldStartClock = false) {
  const idle = [], styles = [];
  let now = 1000;
  const turns = Array.from({length:count}, (_,i)=>{
    const attrMap = new Map();
    attrMap.set('data-testid', `conversation-turn-${i}`);
    const t = {
      index: i,
      tagName: 'DIV',
      isConnected: true,
      attrs: attrMap,
      children: [],
      parentElement: {closest: () => null},
      hasAttribute(k) { return this.attrs.has(k); },
      getAttribute(k) { return this.attrs.get(k) || null; },
      setAttribute(k, v) { this.attrs.set(k, String(v)); },
      removeAttribute(k) { this.attrs.delete(k); },
      querySelector(sel) {
        this.approvalScans = (this.approvalScans || 0) + 1;
        for (const child of this.children) {
          if (child.matches(sel)) return child;
          const sub = child.querySelector(sel);
          if (sub) return sub;
        }
        return null;
      },
      querySelectorAll(sel) {
        const res = [];
        for (const child of this.children) {
          if (child.matches(sel)) res.push(child);
          res.push(...child.querySelectorAll(sel));
        }
        return res;
      },
      matches(sel) {
        if (sel.includes('conversation-turn') || sel.includes('data-turn-key')) return true;
        return false;
      },
      closest(sel) {
        if (this.matches(sel)) return this;
        return null;
      }
    };
    return t;
  });
  const doc = {
    hidden: false,
    head: { appendChild: x => styles.push(x) },
    documentElement: { appendChild: x => styles.push(x) },
    createElement: tag => ({
      tag, id: null, textContent: '',
      remove() { const i = styles.indexOf(this); if (i >= 0) styles.splice(i, 1); }
    }),
    getElementById: id => styles.find(x => x.id === id) || null,
    querySelectorAll: sel => {
      if (sel === '[' + ATTR + ']') {
        return turns.filter(t => t.attrs.has(ATTR));
      }
      return [];
    }
  };
  const win = {}; win.top = win; const location = {origin: 'https://chatgpt.com'};
  const world = {
    window: win,
    top: win,
    location,
    document: doc,
    __OPTIMIZED_PC_HISTORY_ENABLED__: enabled,
    requestIdleCallback: fn => idle.push(fn),
    setTimeout: fn => idle.push(fn),
    Date: { now: () => now }
  };
  if (coldStartClock) world.performance = {now: () => now};
  runInNewContext(code, world);
  const flush = () => { let i = 0; while (idle.length && i++ < 50) idle.shift()(); };
  return {
    api: world.__CHATGPT_WEB_PC_LONG_CHAT__,
    world,
    turns,
    flush,
    flushOne: deadline => idle.shift()?.(deadline),
    advanceTime: ms => { now += ms; },
    doc,
    styles,
    createMockElement
  };
}
test('PC port limits optimization to history, preserving latest twelve turns',()=>{
  const x=fixture(true,30);
  x.api.refresh('c-123',x.turns,{running:false,waiting:false});
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,0); // first batch waits for idle
  x.flushOne();
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,4);
  x.flush();
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,18);
  for(const node of x.turns.slice(-12))assert.equal(node.attrs.has(ATTR),false);
  assert.equal(x.api.audit().optimized,18);
  assert.equal(x.styles.length,1);
  assert.match(x.styles[0].textContent,/content-visibility:auto/);
});
test('short chat or running/awaiting-approval chat does not modify history',()=>{
  for(const [count,status] of [[23,{}],[30,{running:true}],[30,{waiting:true}]]) {
    const x=fixture(true,count);x.api.refresh('c-123',x.turns,status);x.flush();
    assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,0);
  }
});
test('native OFF policy means no layout mutations, no style, no scans',()=>{
  const x=fixture(false,200);x.api.refresh('c-123',x.turns,{});x.flush();
  assert.equal(x.api.audit().enabled,false);
  assert.equal(x.styles.length,0);
  assert.equal(x.turns.some(t=>t.attrs.has(ATTR)),false);
});
test('route switch cleans old node attributes and cancels retired idle chunks',()=>{
  const x=fixture(true,70);
  x.api.refresh('c-first',x.turns,{});
  x.flushOne();
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,4);
  const next=fixture(true,30).turns;
  x.api.refresh('c-second',next,{});
  x.flush();
  assert.equal(x.turns.some(t=>t.attrs.has(ATTR)),false);
  assert.equal(next.filter(t=>t.attrs.has(ATTR)).length,18);
});
test('leaving conversation clears previously optimized attributes and cancels queued chunks',()=>{
  const x=fixture(true,75);
  x.api.refresh('c-conversation',x.turns,{});
  x.flushOne();
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,4);
  x.api.refresh(null,null,{});
  x.flush();
  assert.equal(x.turns.some(t=>t.attrs.has(ATTR)),false);
  assert.equal(x.api.audit().mounted,0);
});
test('interactive approval blocks are preserved, destruction is reversible',()=>{
  const x=fixture(true,26);
  x.turns[0].querySelector=()=>({});
  x.api.refresh('c-safe',x.turns,{});
  x.flush();
  assert.equal(x.turns[0].attrs.has(ATTR),false);
  assert.equal(x.turns.slice(-12).some(t=>t.attrs.has(ATTR)),false);
  x.api.destroy();
  assert.equal(x.turns.some(t=>t.attrs.has(ATTR)),false);
  assert.equal(x.styles.length,0);
});
test('late approval in frozen turn restores native painting on waiting:true',()=>{
  const x=fixture(true,30);
  x.api.refresh('c-late',x.turns,{running:false,waiting:false});
  x.flush();
  assert.equal(x.turns[5].attrs.has(ATTR),true);
  x.turns[5].querySelector=sel=>sel.includes('approval')?{}:null;
  x.api.refresh('c-late',x.turns,{waiting:true});
  assert.equal(x.turns[5].attrs.has(ATTR),false);
  assert.equal(x.turns[4].attrs.has(ATTR),true);
});
test('late approval in frozen turn restores native painting on idle refresh',()=>{
  const x=fixture(true,30);
  x.api.refresh('c-late-idle',x.turns,{running:false,waiting:false});
  x.flush();
  assert.equal(x.turns[5].attrs.has(ATTR),true);
  x.turns[5].querySelector=sel=>sel.includes('approval')?{}:null;
  x.api.refresh('c-late-idle',x.turns,{running:false,waiting:false});
  x.flush();
  // CSS :has excludes newly interactive turns immediately, without O(all-turns) JS work.
  assert.match(x.styles[0].textContent, /:not\(:has\(/);
  assert.equal(x.turns[5].attrs.has(ATTR),true);
  x.advanceTime(12001);
  x.api.refresh('c-late-idle',x.turns,{running:false,waiting:false});
  x.flush();
  assert.equal(x.turns[5].attrs.has(ATTR),false);
  assert.equal(x.turns[4].attrs.has(ATTR),true);
});

test('stable history refresh avoids repeat approval scans between bounded checks',()=>{
  const x=fixture(true,90);
  x.api.refresh('c-stable',x.turns,{});
  x.flush();
  const before=x.turns.reduce((n,t)=>n+(t.approvalScans||0),0);
  x.api.refresh('c-stable',x.turns,{});
  x.flush();
  assert.equal(x.turns.reduce((n,t)=>n+(t.approvalScans||0),0),before);
  x.advanceTime(12001);
  x.api.refresh('c-stable',x.turns,{});
  x.flush();
  assert.ok(x.turns.reduce((n,t)=>n+(t.approvalScans||0),0)>before);
});

test('historical layout optimization leaves native details state unchanged',()=>{
  const x=fixture(true,31);
  const details={open:true,isConnected:true,
    querySelector:sel=>sel===':scope > summary'?{textContent:'MCP tool result'}:null};
  x.turns[0].querySelectorAll=sel=>sel==='details'?[details]:[];
  x.api.refresh('c-tools',x.turns,{});
  x.flush();
  assert.equal(details.open,true);
  x.advanceTime(12001);
  x.api.refresh('c-tools',x.turns,{});
  x.flush();
  assert.equal(details.open,true);
  x.api.destroy();
  assert.equal(details.open,true);
});

// Native renderer transitions replace the obsolete MCP JS-scanner cases.
// Native process visibility is covered by native-process tests and WebKit.
test('mixed legacy and native markers restore history and cancel queued batches', () => {
  const x=fixture(true,40);
  x.api.refresh('mixed',x.turns,{});
  x.flushOne();
  assert.equal(x.turns.filter(n=>n.attrs.has(ATTR)).length,4);
  x.turns[39].attrs.set('data-turn-key','native-late');
  x.api.refresh('mixed',x.turns,{running:true});
  x.flush();
  assert.equal(x.api.audit().nativeVirtualized,true);
  assert.equal(x.turns.some(n=>n.attrs.has(ATTR)),false);
  assert.equal(x.styles.length,0);
});

test('native marker inserted before first idle batch cancels all legacy marking', () => {
  const x=fixture(true,40);
  let marker=false;
  const root={isConnected:true,querySelector:()=>marker?{}:null};
  x.api.refresh('late',x.turns,{},root);
  marker=true;
  x.flush();
  assert.equal(x.api.audit().nativeVirtualized,true);
  assert.equal(x.turns.some(n=>n.attrs.has(ATTR)),false);
  assert.equal(x.styles.length,0);
});

test('native detection during cold start or waiting does not schedule history work',()=>{
  const x=fixture(true,30,true);
  x.turns[29].attrs.set('data-turn-key','native');
  x.api.refresh('mixed-cold',x.turns,{waiting:true});
  x.flush();
  assert.equal(x.api.audit().nativeVirtualized,true);
  assert.equal(x.turns.some(n=>n.attrs.has(ATTR)),false);
});

test('running updates skip historical approval walks while waiting restores controls', () => {
  const x = fixture(true, 40);
  x.api.refresh('c-running', x.turns, {});
  x.flush();
  const before = x.turns.reduce((n, t) => n + (t.approvalScans || 0), 0);
  for (let i = 0; i < 4; i++) x.api.refresh('c-running', x.turns, {running: true});
  assert.equal(x.turns.reduce((n, t) => n + (t.approvalScans || 0), 0), before);
  x.turns[3].querySelector = selector => selector.includes('approval') ? {} : null;
  x.api.refresh('c-running', x.turns, {waiting: true});
  assert.equal(x.turns[3].attrs.has(ATTR), false, 'pending approval remains accessible');
});

test('cold-start grace delays historic layout while ChatGPT hydrates sidebar', () => {
  const x=fixture(true,30,true);
  x.api.refresh('c-startup',x.turns,{});
  x.flush();
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,0);
  x.advanceTime(5001);
  x.api.refresh('c-startup',x.turns,{});
  x.flush();
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,18);
});

test('startup grace never blocks running/waiting statuses', () => {
  const x = fixture(true, 30, true);
  x.api.refresh('c-stream', x.turns, {running:true, waiting:false});
  x.flush();
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length, 0);
  x.api.refresh('c-stream', x.turns, {running:false, waiting:true});
  x.flush();
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length, 0);
  x.advanceTime(5200);
  x.api.refresh('c-stream', x.turns, {running:false, waiting:false});
  x.flush();
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length, 18);
});

test('optional history scheduler yields rather than forcing work on a busy idle deadline', () => {
  const x = fixture(true, 30);
  x.api.refresh('c-busy', x.turns, {});
  x.flushOne({timeRemaining: () => 0});
  assert.equal(x.turns.filter(t => t.attrs.has(ATTR)).length, 0);
  x.flushOne({timeRemaining: () => 50});
  assert.equal(x.turns.filter(t => t.attrs.has(ATTR)).length, 4);
  x.flush();
  assert.equal(x.turns.filter(t => t.attrs.has(ATTR)).length, 18);
});
