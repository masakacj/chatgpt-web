// Transient, opt-in live diagnostic transport; no D1, transcript or request payloads.
const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status, headers: {'content-type':'application/json; charset=utf-8', 'cache-control':'no-store'}
});
const validRoom = s => /^[A-Za-z0-9_-]{20,64}$/.test(s);
const validSecret = s => /^[A-Za-z0-9_-]{32,128}$/.test(s);
const now = () => Date.now();
const allowedEvent = new Set(['nav_start','nav_finish','nav_error','snapshot','memory_warning','web_terminated']);
const numberFields = ['turns','domNodes','imageNodes','navMs','loadMs','progress','lastTurnVisible','webLoading','resourceRuleCount','resourceGateEnabled','safeMode','webviewAttached','observerMs'];
const metric = input => {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  if (!allowedEvent.has(input.kind)) return null;
  const safe = {kind: input.kind, at: now()};
  for (const key of numberFields) {
    if (typeof input[key] === 'number' && Number.isFinite(input[key]))
      safe[key] = Math.max(0, Math.min(10000000, input[key]));
  }
  return safe;
};
async function digest(value) {
  const bytes = new TextEncoder().encode(value);
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
    x => x.toString(16).padStart(2,'0')).join('');
}
export class LiveDebugRoom {
  constructor(state) {
    this.state = state;
    this.secretHash = null;
    this.events = [];
    this.queue = [];
    this.results = new Map();
    this.lastRequestedAt = 0;
  }
  async fetch(request) {
    const url = new URL(request.url);
    const key = request.headers.get('x-optimizer-debug-key') || '';
    if (!validSecret(key)) return json({ok:false,error:'unauthorized'},401);
    const receivedHash = await digest(key);
    // First authenticated caller binds this opaque, unguessable room.
    if (this.secretHash === null) this.secretHash = receivedHash;
    if (this.secretHash !== receivedHash) return json({ok:false,error:'unauthorized'},401);
    const time = now();
    this.events = this.events.filter(e => time - e.at < 600000).slice(-79);
    this.queue = this.queue.filter(e => time - e.at < 60000);
    for (const [id, value] of this.results) if (time - value.at > 600000) this.results.delete(id);
    if (request.method === 'GET' && url.pathname === '/events')
      return json({ok:true,events:this.events.slice(-80)});
    if (request.method === 'GET' && url.pathname === '/poll')
      return json({ok:true,requests:this.queue.splice(0,4).map(({id,kind})=>({id,kind}))});
    if (request.method === 'GET' && url.pathname === '/result') {
      const id = url.searchParams.get('id') || '';
      const value = this.results.get(id);
      if (!value) return json({ok:false,error:'expired_or_unknown'},404);
      return json({ok:true,id,status:value.status,measurement:value.measurement||null},value.status==='pending'?202:200);
    }
    if (request.method === 'POST') {
      const raw = await request.text();
      if (raw.length > 8192) return json({ok:false,error:'too_large'},413);
      let body; try { body=JSON.parse(raw); } catch {return json({ok:false,error:'bad_json'},400);}
      if (url.pathname === '/events') {
        const events = Array.isArray(body.events) ? body.events.slice(0,20).map(metric).filter(Boolean) : [];
        if (!events.length) return json({ok:false,error:'bad_events'},400);
        this.events.push(...events); this.events=this.events.slice(-80);
        return json({ok:true,accepted:events.length});
      }
      if (url.pathname === '/request') {
        if (body.kind !== 'snapshot') return json({ok:false,error:'unsupported_request'},400);
        // Never queue a burst of costly full-DOM probes on a long conversation.
        if (time - this.lastRequestedAt < 2500 || this.queue.length ||
            [...this.results.values()].some(x => x.status==='pending' && time-x.at < 30000))
          return json({ok:false,error:'busy'},429);
        this.lastRequestedAt = time;
        const id = crypto.randomUUID();
        this.queue.push({id,kind:'snapshot',at:time});
        this.results.set(id,{status:'pending',at:time});
        return json({ok:true,id},202);
      }
      if (url.pathname === '/response') {
        const id = body.id;
        const current = this.results.get(id);
        if (!current || current.status !== 'pending') return json({ok:false,error:'expired_or_unknown'},404);
        const sample=metric({...body.measurement,kind:'snapshot'});
        if (!sample) return json({ok:false,error:'bad_measurement'},400);
        this.results.set(id,{status:'complete',at:time,measurement:sample});
        this.events.push(sample); this.events=this.events.slice(-80);
        return json({ok:true,id});
      }
    }
    return json({ok:false,error:'not_found'},404);
  }
}
export async function handleLiveDebug(request, env, pathname) {
  const parts = pathname.split('/');
  if (parts.length !== 5 || parts[1] !== 'v1' || parts[2] !== 'live' ||
      !['events','poll','request','result','response'].includes(parts[4]))
    return json({ok:false,error:'not_found'},404);
  const match = [null, parts[3], parts[4]];
  if (!env.LIVE_DEBUG) return json({ok:false,error:'not_configured'},503);
  if (request.method==='OPTIONS') return json({ok:false,error:'forbidden'},403);
  if (!validRoom(match[1])) return json({ok:false,error:'bad_room'},400);
  // DO is keyed by a random room ID. Never log the pairing key or put it in URLs.
  const stub=env.LIVE_DEBUG.get(env.LIVE_DEBUG.idFromName(match[1]));
  return stub.fetch(new Request('https://live.internal/'+match[2]+new URL(request.url).search,request));
}
