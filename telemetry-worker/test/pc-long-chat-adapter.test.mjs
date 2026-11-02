import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';

const code = readFileSync(new URL('../../OptimizedResources/Observation/pc-long-chat-adapter.js', import.meta.url), 'utf8');
const ATTR = 'data-optimized-pc-history';
const MCP_ATTR = 'data-optimized-mcp-output';

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
      if (sel.includes('button') && this.tagName === 'BUTTON') return true;
      if (sel.includes('iframe') && this.tagName === 'IFRAME') return true;
      if (sel.includes('summary') && this.tagName === 'SUMMARY') return true;
      if (sel.includes('header') && this.tagName === 'HEADER') return true;
      if (sel.includes('textarea') && this.tagName === 'TEXTAREA') return true;
      if (sel.includes('select') && this.tagName === 'SELECT') return true;
      if (sel.includes('a[href]') && this.tagName === 'A' && this.attrs.has('href')) return true;
      const testid = this.attrs.get('data-testid') || '';
      if (sel.includes('tool-result') && /tool-result/i.test(testid)) return true;
      if (sel.includes('tool-output') && /tool-output/i.test(testid)) return true;
      if (sel.includes('tool-response') && /tool-response/i.test(testid)) return true;
      if (sel.includes('mcp-result') && /mcp-result/i.test(testid)) return true;
      if (sel.includes('mcp-output') && /mcp-output/i.test(testid)) return true;
      if (sel.includes('approval') && /approval/i.test(testid)) return true;
      if (sel.includes('permission') && /permission/i.test(testid)) return true;
      if (sel.includes('mcp-app') && /mcp-app/i.test(testid)) return true;
      if (sel.includes('reasoning') && /reasoning/i.test(testid)) return true;
      if (sel.includes('thought') && /thought/i.test(testid)) return true;
      if (sel.includes('error') && /error/i.test(testid)) return true;
      const role = this.attrs.get('role') || '';
      if (sel.includes('dialog') && role === 'dialog') return true;
      if (sel.includes('alert') && role === 'alert') return true;
      if (sel.includes('status') && role === 'status') return true;
      return false;
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
  }
  return el;
}

function fixture(enabled = true, count = 30, mcpEnabled = false) {
  const idle = [], styles = [];
  let now = 1000;
  const turns = Array.from({length:count}, (_,i)=>{
    const attrMap = new Map();
    attrMap.set('data-turn-key', `turn-${i}`);
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
      if (sel === '[' + MCP_ATTR + ']') {
        const marked = [];
        const scan = el => {
          if (el.attrs?.has?.(MCP_ATTR)) marked.push(el);
          if (el.children) el.children.forEach(scan);
        };
        turns.forEach(scan);
        return marked;
      }
      if (sel.includes('tool-result') || sel.includes('tool-output') || sel.includes('mcp-output') || sel.includes('mcp-result') || sel.includes('tool-response')) {
        const matches = [];
        const scan = el => {
          const testid = el.attrs?.get?.('data-testid') || '';
          if (/tool-result|tool-output|tool-response|mcp-result|mcp-output/i.test(testid)) {
            matches.push(el);
          }
          if (el.children) el.children.forEach(scan);
        };
        turns.forEach(scan);
        return matches;
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
    __OPTIMIZED_MCP_OUTPUT_RELIEF_ENABLED__: mcpEnabled,
    requestIdleCallback: fn => idle.push(fn),
    setTimeout: fn => idle.push(fn),
    Date: { now: () => now }
  };
  runInNewContext(code, world);
  const flush = () => { let i = 0; while (idle.length && i++ < 50) idle.shift()(); };
  return {
    api: world.__CHATGPT_WEB_PC_LONG_CHAT__,
    world,
    turns,
    flush,
    flushOne: () => idle.shift()?.(),
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
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,16);
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
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,16);
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
  assert.equal(x.turns.filter(t=>t.attrs.has(ATTR)).length,16);
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

// --- MCP Tool OUTPUT Relief Test Suite ---

test('large explicit MCP tool output collapsed during running', () => {
  const x = fixture(true, 5, true);
  const output = createMockElement('div', {'data-testid': 'tool-output'}, 'X'.repeat(2048));
  x.turns[4].children.push(output);
  output.parent = x.turns[4];

  x.api.refresh('c-stream', x.turns, {running: true, waiting: false});
  assert.equal(output.attrs.get(MCP_ATTR), '1');
  assert.equal(x.api.audit().mcpRelieved, 1);
  const mcpStyle = x.styles.find(s => s.id === 'optimized-mcp-output-style');
  assert.ok(mcpStyle, 'MCP relief style element should be injected');
  assert.match(mcpStyle.textContent, /display:none!important/);
  // History optimization is not applied because count = 5 < 24 and running is true
  assert.equal(x.turns.some(t => t.attrs.has(ATTR)), false);
});

test('small tool output below threshold is skipped', () => {
  const x = fixture(false, 5, true);
  const smallOutput = createMockElement('div', {'data-testid': 'tool-output'}, 'short result 42');
  x.turns[2].children.push(smallOutput);
  smallOutput.parent = x.turns[2];

  x.api.refresh('c-small', x.turns, {running: false, waiting: false});
  assert.equal(smallOutput.attrs.has(MCP_ATTR), false);
  assert.equal(x.api.audit().mcpRelieved, 0);
});

test('ordinary text and user text with tool/MCP words untouched', () => {
  const x = fixture(true, 5, true);
  // Assistant ordinary markdown mentioning MCP
  const assistantMd = createMockElement('div', {class: 'MarkdownRoot'}, 'Here is the mcp-output explanation you requested.');
  x.turns[4].children.push(assistantMd);
  assistantMd.parent = x.turns[4];

  // User message containing tool-result text
  const userMsg = createMockElement('div', {'data-conversation-role': 'user'}, 'I want to see the tool-result from mcp-output: ' + 'Y'.repeat(1500));
  x.turns[0].children.push(userMsg);
  userMsg.parent = x.turns[0];

  x.api.refresh('c-md', x.turns, {running: true, waiting: false});
  assert.equal(assistantMd.attrs.has(MCP_ATTR), false);
  assert.equal(userMsg.attrs.has(MCP_ATTR), false);
  assert.equal(x.api.audit().mcpRelieved, 0);
});

test('tool status and header kept visible while large output body is collapsed', () => {
  const x = fixture(false, 5, true);
  const header = createMockElement('header', {'data-testid': 'tool-header'}, 'Status: executing query');
  const body = createMockElement('div', {'data-testid': 'tool-result'}, 'R'.repeat(1800));
  x.turns[1].children.push(header, body);
  header.parent = x.turns[1];
  body.parent = x.turns[1];

  x.api.refresh('c-head', x.turns, {});
  assert.equal(header.attrs.has(MCP_ATTR), false, 'header must stay visible');
  assert.equal(body.attrs.get(MCP_ATTR), '1', 'large body must be collapsed');
  assert.equal(x.api.audit().mcpRelieved, 1);
});

test('interactive controls, approvals, and iframes are skipped', () => {
  const x = fixture(false, 8, true);

  // 1. Output containing action button
  const btnOutput = createMockElement('div', {'data-testid': 'tool-output'}, 'B'.repeat(1500), [
    createMockElement('button', {}, 'Run query')
  ]);
  // 2. Output with approval marker
  const approvalOutput = createMockElement('div', {'data-testid': 'mcp-result'}, 'A'.repeat(1500), [
    createMockElement('div', {'data-testid': 'approval-prompt'}, 'Please authorize')
  ]);
  // 3. Output containing iframe
  const iframeOutput = createMockElement('div', {'data-testid': 'mcp-output'}, 'I'.repeat(1500), [
    createMockElement('iframe', {})
  ]);
  // 4. Output with dialog role
  const dialogOutput = createMockElement('div', {'data-testid': 'tool-output', role: 'dialog'}, 'D'.repeat(1500));

  x.turns[0].children.push(btnOutput, approvalOutput, iframeOutput, dialogOutput);
  btnOutput.parent = x.turns[0];
  approvalOutput.parent = x.turns[0];
  iframeOutput.parent = x.turns[0];
  dialogOutput.parent = x.turns[0];

  x.api.refresh('c-interact', x.turns, {running: true});
  assert.equal(btnOutput.attrs.has(MCP_ATTR), false, 'button output must not be collapsed');
  assert.equal(approvalOutput.attrs.has(MCP_ATTR), false, 'approval output must not be collapsed');
  assert.equal(iframeOutput.attrs.has(MCP_ATTR), false, 'iframe output must not be collapsed');
  assert.equal(dialogOutput.attrs.has(MCP_ATTR), false, 'dialog output must not be collapsed');
  assert.equal(x.api.audit().mcpRelieved, 0);
});

test('error alert and reasoning containers are skipped', () => {
  const x = fixture(false, 5, true);
  const errorContainer = createMockElement('div', {'data-testid': 'tool-output'}, 'E'.repeat(1500), [
    createMockElement('div', {role: 'alert'}, 'Error: connection refused')
  ]);
  const reasoningContainer = createMockElement('div', {'data-testid': 'reasoning'}, 'Thinking... ' + 'T'.repeat(2000));
  x.turns[1].children.push(errorContainer, reasoningContainer);
  errorContainer.parent = x.turns[1];
  reasoningContainer.parent = x.turns[1];

  x.api.refresh('c-err', x.turns, {});
  assert.equal(errorContainer.attrs.has(MCP_ATTR), false, 'error alert must stay visible');
  assert.equal(reasoningContainer.attrs.has(MCP_ATTR), false, 'reasoning must stay visible');
});

test('restoring after dynamic disable', () => {
  const x = fixture(true, 5, true);
  const output = createMockElement('div', {'data-testid': 'tool-output'}, 'Z'.repeat(2500));
  x.turns[2].children.push(output);
  output.parent = x.turns[2];

  x.api.refresh('c-toggle', x.turns, {});
  assert.equal(output.attrs.get(MCP_ATTR), '1');
  assert.ok(x.styles.some(s => s.id === 'optimized-mcp-output-style'));

  // Disable dynamically
  x.world.__OPTIMIZED_MCP_OUTPUT_RELIEF_ENABLED__ = false;
  x.api.refresh('c-toggle', x.turns, {});
  assert.equal(output.attrs.has(MCP_ATTR), false, 'attribute removed on disable');
  assert.ok(!x.styles.some(s => s.id === 'optimized-mcp-output-style'), 'style removed on disable');
  assert.equal(x.api.audit().mcpRelieved, 0);
  assert.equal(x.api.audit().mcpEnabled, false);
});

test('restoring after reset and destroy', () => {
  const x = fixture(true, 5, true);
  const output = createMockElement('div', {'data-testid': 'tool-output'}, 'W'.repeat(2000));
  x.turns[1].children.push(output);
  output.parent = x.turns[1];

  x.api.refresh('c-clean', x.turns, {});
  assert.equal(output.attrs.get(MCP_ATTR), '1');

  // reset() clears attributes and relief count
  x.api.reset();
  assert.equal(output.attrs.has(MCP_ATTR), false);
  assert.equal(x.api.audit().mcpRelieved, 0);

  // Re-run refresh
  x.api.refresh('c-clean', x.turns, {});
  assert.equal(output.attrs.get(MCP_ATTR), '1');

  // destroy() removes styles and unbinds global
  x.api.destroy();
  assert.equal(output.attrs.has(MCP_ATTR), false);
  assert.ok(!x.styles.some(s => s.id === 'optimized-mcp-output-style'));
  assert.equal(x.world.__CHATGPT_WEB_PC_LONG_CHAT__, undefined);
});

test('late approval in previously collapsed tool output restores native visibility', () => {
  const x = fixture(false, 5, true);
  const output = createMockElement('div', {'data-testid': 'tool-output'}, 'K'.repeat(2000));
  x.turns[2].children.push(output);
  output.parent = x.turns[2];

  x.api.refresh('c-late-mcp', x.turns, {running: true});
  assert.equal(output.attrs.get(MCP_ATTR), '1');

  // React subsequently mounts an approval button inside the tool output
  const approvalBtn = createMockElement('button', {'data-testid': 'permission-allow'}, 'Grant Access');
  output.children.push(approvalBtn);
  approvalBtn.parent = output;

  x.api.refresh('c-late-mcp', x.turns, {waiting: true});
  assert.equal(output.attrs.has(MCP_ATTR), false, 'unmarked when approval appears');
});

test('route switch cleans old conversation MCP relief', () => {
  const x = fixture(false, 5, true);
  const output1 = createMockElement('div', {'data-testid': 'tool-output'}, 'M'.repeat(2000));
  x.turns[1].children.push(output1);
  output1.parent = x.turns[1];

  x.api.refresh('c-route-1', x.turns, {});
  assert.equal(output1.attrs.get(MCP_ATTR), '1');

  const x2 = fixture(false, 5, true);
  const output2 = createMockElement('div', {'data-testid': 'tool-output'}, 'N'.repeat(2000));
  x2.turns[1].children.push(output2);
  output2.parent = x2.turns[1];

  x.api.refresh('c-route-2', x2.turns, {});
  assert.equal(output1.attrs.has(MCP_ATTR), false, 'old conversation MCP output attribute cleared');
  assert.equal(output2.attrs.get(MCP_ATTR), '1', 'new conversation MCP output attribute set');
});

test('history optimization and MCP relief operate independently', () => {
  // Case 1: History ON + MCP ON
  const xBoth = fixture(true, 30, true);
  const toolBoth = createMockElement('div', {'data-testid': 'tool-output'}, 'T'.repeat(2000));
  xBoth.turns[29].children.push(toolBoth);
  toolBoth.parent = xBoth.turns[29];

  xBoth.api.refresh('c-both', xBoth.turns, {running: false, waiting: false});
  xBoth.flush();
  // 18 history turns optimized (30 - 12), and MCP output relieved in turn 29
  assert.equal(xBoth.turns.filter(t => t.attrs.has(ATTR)).length, 18);
  assert.equal(toolBoth.attrs.get(MCP_ATTR), '1');
  assert.equal(xBoth.api.audit().optimized, 18);
  assert.equal(xBoth.api.audit().mcpRelieved, 1);

  // Case 2: History OFF + MCP ON
  const xMcpOnly = fixture(false, 30, true);
  const toolMcp = createMockElement('div', {'data-testid': 'tool-output'}, 'T'.repeat(2000));
  xMcpOnly.turns[29].children.push(toolMcp);
  toolMcp.parent = xMcpOnly.turns[29];

  xMcpOnly.api.refresh('c-mcp', xMcpOnly.turns, {running: false, waiting: false});
  xMcpOnly.flush();
  assert.equal(xMcpOnly.turns.some(t => t.attrs.has(ATTR)), false, 'no history optimization');
  assert.equal(toolMcp.attrs.get(MCP_ATTR), '1', 'MCP output still relieved');
  assert.equal(xMcpOnly.api.audit().optimized, 0);
  assert.equal(xMcpOnly.api.audit().mcpRelieved, 1);

  // Case 3: History ON + MCP OFF
  const xHistOnly = fixture(true, 30, false);
  const toolHist = createMockElement('div', {'data-testid': 'tool-output'}, 'T'.repeat(2000));
  xHistOnly.turns[29].children.push(toolHist);
  toolHist.parent = xHistOnly.turns[29];

  xHistOnly.api.refresh('c-hist', xHistOnly.turns, {running: false, waiting: false});
  xHistOnly.flush();
  assert.equal(xHistOnly.turns.filter(t => t.attrs.has(ATTR)).length, 18, 'history optimized');
  assert.equal(toolHist.attrs.has(MCP_ATTR), false, 'MCP output not relieved');
  assert.equal(xHistOnly.api.audit().optimized, 18);
  assert.equal(xHistOnly.api.audit().mcpRelieved, 0);
});

test('IOS-MCP-001: bounded discovery avoids repeat subtree scans during streaming log growth', () => {
  const x = fixture(false, 10, true);
  for (const turn of x.turns) {
    const origQSA = turn.querySelectorAll;
    turn.mcpQueries = 0;
    turn.querySelectorAll = function(sel) {
      if (sel.includes('tool-result') || sel.includes('tool-output') || sel.includes('mcp')) {
        this.mcpQueries++;
      }
      return origQSA.call(this, sel);
    };
  }

  // Active streaming turn 9 receives a tool output initially below threshold
  const output = createMockElement('div', {'data-testid': 'tool-output'}, 'A'.repeat(500));
  x.turns[9].children.push(output);
  output.parent = x.turns[9];

  // Refresh 1: initial scan of turns
  x.api.refresh('c-stream-log', x.turns, {running: true, waiting: false});
  assert.equal(output.attrs.has(MCP_ATTR), false, 'below threshold initially');
  const histQueriesPass1 = x.turns.slice(0, 9).reduce((sum, t) => sum + t.mcpQueries, 0);
  assert.equal(histQueriesPass1, 9, 'historical turns scanned once on first arrival');
  assert.equal(x.turns[9].mcpQueries, 1, 'tail turn scanned once');

  // Refresh 2: incremental text growth past 1024 threshold (child count unchanged)
  output.textContent += 'B'.repeat(1000);
  x.api.refresh('c-stream-log', x.turns, {running: true, waiting: false});
  assert.equal(output.attrs.get(MCP_ATTR), '1', 'marked once threshold exceeded');
  const histQueriesPass2 = x.turns.slice(0, 9).reduce((sum, t) => sum + t.mcpQueries, 0);
  assert.equal(histQueriesPass2, histQueriesPass1, 'zero additional scans on historical turns');
  assert.equal(x.turns[9].mcpQueries, 1, 'zero additional scans on tail turn during text growth');

  // Refresh 3: further incremental growth to 3500 chars
  output.textContent += 'C'.repeat(2000);
  x.api.refresh('c-stream-log', x.turns, {running: true, waiting: false});
  assert.equal(output.attrs.get(MCP_ATTR), '1', 'remains marked');
  const histQueriesPass3 = x.turns.slice(0, 9).reduce((sum, t) => sum + t.mcpQueries, 0);
  assert.equal(histQueriesPass3, histQueriesPass1, 'zero additional scans on historical turns across growth');
  assert.equal(x.turns[9].mcpQueries, 1, 'zero additional scans on tail turn across growth');

  // Refresh 4: generation completes
  x.api.refresh('c-stream-log', x.turns, {running: false, waiting: false});
  // Refresh 5: subsequent idle refresh causes no queries
  const totalQueriesBefore = x.turns.reduce((sum, t) => sum + t.mcpQueries, 0);
  x.api.refresh('c-stream-log', x.turns, {running: false, waiting: false});
  const totalQueriesAfter = x.turns.reduce((sum, t) => sum + t.mcpQueries, 0);
  assert.equal(totalQueriesAfter, totalQueriesBefore, 'zero queries during idle refresh of settled chat');
});

test('IOS-MCP-002: detached marked nodes lose attribute on reset and avoid wrongful hiding on reattach', () => {
  const x = fixture(false, 5, true);
  const output = createMockElement('div', {'data-testid': 'tool-output'}, 'D'.repeat(2000));
  x.turns[1].children.push(output);
  output.parent = x.turns[1];

  x.api.refresh('c-route-A', x.turns, {});
  assert.equal(output.attrs.get(MCP_ATTR), '1', 'initially marked in route A');
  assert.equal(x.api.audit().mcpRelieved, 1);

  // Detach output from DOM while still marked
  const idx = x.turns[1].children.indexOf(output);
  x.turns[1].children.splice(idx, 1);
  output.parent = null;
  output.isConnected = false;

  // Route switch cleans old conversation MCP relief
  const routeB = fixture(false, 5, true);
  const output2 = createMockElement('div', {'data-testid': 'tool-output'}, 'E'.repeat(2000));
  routeB.turns[1].children.push(output2);
  output2.parent = routeB.turns[1];

  x.api.refresh('c-route-B', routeB.turns, {});
  assert.equal(output.attrs.has(MCP_ATTR), false, 'detached node lost attribute on route reset');
  assert.equal(x.api.audit().mcpRelieved, 1, 'route B has 1 relieved output');
  assert.equal(output2.attrs.get(MCP_ATTR), '1');
  assert.ok(x.styles.some(s => s.id === 'optimized-mcp-output-style'), 'stylesheet active in route B');

  // Old detached node is reattached into route B's tree
  routeB.turns[2].children.push(output);
  output.parent = routeB.turns[2];
  output.isConnected = true;
  // Node must not retain the old attribute that would wrongly hide it under route B's shared stylesheet
  assert.equal(output.attrs.has(MCP_ATTR), false, 'reattached old node does not have stale attribute');
});

test('IOS-MCP-003: repeated approval insertion and removal maintains truthful relieved count', () => {
  const x = fixture(false, 5, true);
  const output = createMockElement('div', {'data-testid': 'tool-output'}, 'M'.repeat(2000));
  x.turns[2].children.push(output);
  output.parent = x.turns[2];

  x.api.refresh('c-controls', x.turns, {});
  assert.equal(output.attrs.get(MCP_ATTR), '1');
  assert.equal(x.api.audit().mcpRelieved, 1, 'initially relieved 1 output');

  const btn = createMockElement('button', {'data-testid': 'approval-allow'}, 'Grant Approval');

  // Cycle 1: Insert control -> unmark, decrement count
  output.children.push(btn);
  btn.parent = output;
  x.api.refresh('c-controls', x.turns, {waiting: true});
  assert.equal(output.attrs.has(MCP_ATTR), false, 'unmarked when approval button mounted');
  assert.equal(x.api.audit().mcpRelieved, 0, 'truthful count decrements to 0');

  // Cycle 1: Remove control -> re-mark, count returns to 1 (not 2)
  output.children.splice(output.children.indexOf(btn), 1);
  btn.parent = null;
  x.api.refresh('c-controls', x.turns, {});
  assert.equal(output.attrs.get(MCP_ATTR), '1', 're-marked when approval button removed');
  assert.equal(x.api.audit().mcpRelieved, 1, 'count returns to 1, does not inflate to 2');

  // Cycle 2: Insert control again
  output.children.push(btn);
  btn.parent = output;
  x.api.refresh('c-controls', x.turns, {waiting: true});
  assert.equal(output.attrs.has(MCP_ATTR), false);
  assert.equal(x.api.audit().mcpRelieved, 0);

  // Cycle 2: Remove control again
  output.children.splice(output.children.indexOf(btn), 1);
  btn.parent = null;
  x.api.refresh('c-controls', x.turns, {});
  assert.equal(output.attrs.get(MCP_ATTR), '1');
  assert.equal(x.api.audit().mcpRelieved, 1, 'count remains exactly 1, not 3');

  // Cycle 3: Insert control a third time
  output.children.push(btn);
  btn.parent = output;
  x.api.refresh('c-controls', x.turns, {waiting: true});
  assert.equal(x.api.audit().mcpRelieved, 0);

  // Cycle 3: Remove control a third time
  output.children.splice(output.children.indexOf(btn), 1);
  btn.parent = null;
  x.api.refresh('c-controls', x.turns, {});
  assert.equal(output.attrs.get(MCP_ATTR), '1');
  assert.equal(x.api.audit().mcpRelieved, 1, 'count remains truthful 1 after multiple cycles');
});

test('R43-001: nested tool output discovered and collapsed during running without direct-child count change', () => {
  const x = fixture(false, 5, true);
  // Last turn has a pre-existing wrapper div (direct-child count of turn is 1)
  const wrapper = createMockElement('div', {id: 'wrapper'});
  x.turns[4].children.push(wrapper);
  wrapper.parent = x.turns[4];

  // Refresh while running: wrapper is empty, direct-child count is 1
  x.api.refresh('c-nested', x.turns, {running: true, waiting: false});
  assert.equal(x.api.audit().mcpRelieved, 0, 'empty wrapper is not tool output');

  // React mounts a 2048-char tool output nested under the wrapper; direct children of turn stays 1
  const nestedOutput = createMockElement('div', {'data-testid': 'tool-output'}, 'X'.repeat(2048));
  wrapper.children.push(nestedOutput);
  nestedOutput.parent = wrapper;

  // Subsequent refreshes during running must discover and collapse it
  for (let i = 0; i < 5; i++) {
    x.api.refresh('c-nested', x.turns, {running: true, waiting: false});
  }
  assert.equal(nestedOutput.attrs.get(MCP_ATTR), '1', 'nested tool output marked with relief attribute while streaming');
  assert.equal(x.api.audit().mcpRelieved, 1, 'mcpRelieved audit reflects collapsed nested output');
});

test('R43-002: late idle error/status/header protected from hiding by CSS :has exclusion without JS refresh', () => {
  const x = fixture(false, 5, true);
  const output = createMockElement('div', {'data-testid': 'tool-output'}, 'L'.repeat(2000));
  x.turns[2].children.push(output);
  output.parent = x.turns[2];

  // Refresh and complete generation; output is collapsed
  x.api.refresh('c-idle-error', x.turns, {running: false, waiting: false});
  assert.equal(output.attrs.get(MCP_ATTR), '1', 'initially collapsed');
  assert.equal(x.api.audit().mcpRelieved, 1);

  // Verify stylesheet rule contains :not(:has(...)) with PRESERVE exclusions
  const mcpStyle = x.styles.find(s => s.id === 'optimized-mcp-output-style');
  assert.ok(mcpStyle, 'stylesheet injected');
  // Check that the :not(:has(...)) selector excludes role="alert", error, status, header, approval, and iframe
  assert.match(mcpStyle.textContent, /:not\(:has\([^)]*role="alert"/);
  assert.match(mcpStyle.textContent, /:not\(:has\([^)]*data-testid\*="error"/);
  assert.match(mcpStyle.textContent, /:not\(:has\([^)]*role="status"/);
  assert.match(mcpStyle.textContent, /:not\(:has\([^)]*header/);
  assert.match(mcpStyle.textContent, /:not\(:has\([^)]*approval/);
  assert.match(mcpStyle.textContent, /:not\(:has\([^)]*iframe/);

  // CSS simulation function that evaluates the stylesheet rule:
  // [data-optimized-mcp-output="1"]:not(:has(PRESERVE)) => hidden
  const isPreservedSubtree = el => el.children.some(c =>
    c.matches('button,a[href],textarea,select,iframe,[role="dialog"],[data-testid*="approval" i],[data-testid*="permission" i],[data-testid*="mcp-app" i],summary,header,[class*="header" i],[data-testid*="header" i],[data-testid*="status" i],[role="status"],[data-testid*="progress" i],[data-testid*="error" i],[role="alert"]')
    || (c.children && c.children.length && isPreservedSubtree(c))
  );
  const isCssHidden = el => {
    if (el.attrs.get(MCP_ATTR) !== '1') return false;
    return !isPreservedSubtree(el);
  };

  assert.equal(isCssHidden(output), true, 'initially hidden by CSS rule');

  // React appends a late <span role="alert">Tool error</span> inside output AFTER conversation is settled/idle
  // No JavaScript refresh is called!
  const alert = createMockElement('span', {role: 'alert'}, 'Tool error occurred');
  output.children.push(alert);
  alert.parent = output;

  // The CSS rule IMMEDIATELY unhides the output without any JS refresh
  assert.equal(isCssHidden(output), false, 'CSS :has exclusion immediately unhides output containing role=alert without JS refresh');

  // If a subsequent JS refresh happens later, JS also unmarks the attribute
  x.api.refresh('c-idle-error', x.turns, {running: false, waiting: false});
  assert.equal(output.attrs.has(MCP_ATTR), false, 'JS refresh subsequently cleans up attribute');
  assert.equal(x.api.audit().mcpRelieved, 0);
});
