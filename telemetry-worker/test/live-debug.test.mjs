import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LiveDebugRoom, handleLiveDebug } from '../src/live-debug.js';

const room = 'ios_' + 'a'.repeat(32);
const key = 'b'.repeat(64);
function env() {
  const live = new LiveDebugRoom({});
  return {LIVE_DEBUG: {idFromName: name => name,
    get: name => ({fetch: req => {
      assert.equal(name, room);
      return live.fetch(req);
    }})}};
}
async function req(envValue, action, method='GET', value, secret=key) {
  const url='https://live.test/v1/live/'+room+'/'+action;
  const init = {method,headers:{'x-optimizer-debug-key':secret}};
  if (value) init.body=JSON.stringify(value);
  const result=await handleLiveDebug(new Request(url, init),envValue,new URL(url).pathname);
  return {status:result.status,body:await result.json()};
}
test('one-time read-only snapshot request round trips without D1',async () => {
  const e=env();
  const requested=await req(e,'request','POST',{kind:'snapshot'});
  assert.equal(requested.status,202);
  const polled=await req(e,'poll');
  assert.equal(polled.body.requests[0].id,requested.body.id);
  const resultUrl='https://live.test/v1/live/'+room+'/result?id='+requested.body.id;
  const pending=await handleLiveDebug(new Request(resultUrl,{headers:{'x-optimizer-debug-key':key}}),e,new URL(resultUrl).pathname);
  assert.equal(pending.status,202);
  assert.equal((await req(e,'response','POST',{id:requested.body.id,measurement:{
    kind:'snapshot',turns:42,domNodes:2345,url:'SENSITIVE',chatText:'secret'
  }})).status,200);
  const completed=await handleLiveDebug(new Request(resultUrl,{headers:{'x-optimizer-debug-key':key}}),e,new URL(resultUrl).pathname);
  const data=await completed.json();
  assert.equal(data.status,'complete');
  assert.equal(data.measurement.turns,42);
  assert.equal(data.measurement.chatText,undefined);
  assert.equal(data.measurement.url,undefined);
  assert.equal((await req(e,'events')).body.events.length,1);
});
test('live probe prevents overlapping scans of huge DOM',async()=>{
  const e=env();
  const first=await req(e,'request','POST',{kind:'snapshot'});
  assert.equal(first.status,202);
  const second=await req(e,'request','POST',{kind:'snapshot'});
  assert.equal(second.status,429);
  assert.equal(second.body.error,'busy');
});
test('wrong key refused, arbitrary commands rejected, payload sanitized',async()=>{
  const e=env();
  assert.equal((await req(e,'events','POST',{events:[{kind:'nav_finish',navMs:150}]})).status,200);
  assert.equal((await req(e,'events','GET',undefined,'c'.repeat(64))).status,401);
  assert.equal((await req(e,'request','POST',{kind:'execute_js',source:'alert(1)'})).status,400);
  assert.equal((await req(e,'events','POST',{events:[{kind:'snapshot',turns:2,html:'private'}]})).status,200);
  const events=(await req(e,'events')).body.events;
  assert.equal(events[1].html,undefined);
});
