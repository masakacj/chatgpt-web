import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';

const code = readFileSync(new URL('../../OptimizedResources/Observation/pc-long-chat-adapter.js', import.meta.url), 'utf8');
const ATTR = 'data-optimized-pc-history';
function fixture(enabled = true, count = 30) {
  const idle = [], styles = [];
  const turns = Array.from({length:count}, (_,i)=>({
    index:i,isConnected:true, attrs:new Map(),parentElement:{closest:()=>null},
    setAttribute(k,v){this.attrs.set(k,v)},removeAttribute(k){this.attrs.delete(k)},
    querySelector:()=>null
  }));
  const doc={
    hidden:false, head:{appendChild:x=>styles.push(x)},
    documentElement:{appendChild:x=>styles.push(x)},
    createElement:tag=>({tag,id:null,textContent:'',remove(){const i=styles.indexOf(this);if(i>=0)styles.splice(i,1)}}),
    getElementById:id=>styles.find(x=>x.id===id)||null,
    querySelectorAll:sel=>sel==='['+ATTR+']'?turns.filter(t=>t.attrs.has(ATTR)):[]
  };
  const win={}; win.top=win; const location={origin:'https://chatgpt.com'};
  const world={window:win,top:win,location,document:doc,
    __OPTIMIZED_PC_HISTORY_ENABLED__:enabled,
    requestIdleCallback:fn=>idle.push(fn),
    setTimeout:fn=>idle.push(fn),Date};
  runInNewContext(code,world);
  const flush=()=>{let i=0;while(idle.length && i++<50)idle.shift()();};
  return {api:world.__CHATGPT_WEB_PC_LONG_CHAT__, turns, flush,
    flushOne:()=>idle.shift()?.(), doc, styles};
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
  assert.equal(x.turns[5].attrs.has(ATTR),false);
  assert.equal(x.turns[4].attrs.has(ATTR),true);
});
