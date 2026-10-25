#!/usr/bin/env node
// Read-only on-demand performance probe. Set OPTIMIZER_PAIRING_CODE in the trusted host environment.
// Never pass the private key in argv or print it to logs.
const pair = process.env.OPTIMIZER_PAIRING_CODE || '';
const [room, key, extra] = pair.split(':');
if (extra || !/^ios_[A-Za-z0-9_-]{24,60}$/.test(room || '') ||
    !/^[A-Za-z0-9_-]{32,128}$/.test(key || '')) {
  console.error('Set OPTIMIZER_PAIRING_CODE=<room>:<secret> from the app diagnostics screen.');
  process.exitCode=2;
} else {
  const base = 'https://chatgpt-web-telemetry.masakacj.workers.dev/v1/live/' + room;
  const headers = {'X-Optimizer-Debug-Key':key,'Content-Type':'application/json'};
  async function api(action,method='GET',body) {
    const res=await fetch(base+'/'+action,{method,headers,body:body?JSON.stringify(body):undefined,
      signal:AbortSignal.timeout(7500)});
    const data=await res.json();
    if (!res.ok && res.status!==202) throw Error('HTTP '+res.status+' '+(data.error||'failed'));
    return data;
  }
  try {
    const cmd=process.argv[2] || 'snapshot';
    if (cmd==='events') {
      const data=await api('events');
      console.log(JSON.stringify({roomSuffix:room.slice(-6),events:data.events},null,2));
    } else if (cmd==='snapshot') {
      const requested=await api('request','POST',{kind:'snapshot'});
      let result;
      const deadline=Date.now()+30000;
      while (Date.now()<deadline) {
        const data=await api('result?id='+encodeURIComponent(requested.id));
        if (data.status==='complete') {result=data.measurement;break;}
        await new Promise(resolve=>setTimeout(resolve,750));
      }
      if (!result) throw Error('No phone response within 30s: enable live debug and keep app foreground');
      console.log(JSON.stringify({roomSuffix:room.slice(-6),sample:result},null,2));
    } else throw Error('Supported commands: snapshot, events');
  } catch(e) {
    console.error(String(e.message||e));
    process.exitCode=1;
  }
}
