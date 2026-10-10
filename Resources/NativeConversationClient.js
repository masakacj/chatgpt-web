// App-bundled WKContentWorld module, not a downloadable userscript.
(() => {
  'use strict';
  const api=window.webkit?.messageHandlers?.nativeConversation;
  if(window!==window.top || location.origin!=='https://chatgpt.com' || !api) return;
  if(globalThis.__IOS_NATIVE_RESILIENCE__) return;
  const VERSION='1.0.0',ATTR='data-native-chat-status';
  const records=new Map(), links=new Map(), timers=new Set();
  let current=null,priorKey=null,lastKey=null,doc=null,ready=false,destroyed=false;
  let sidebar=null,sideObserver=null,sideTimer=0,turnObserver=null,turnList=null,stateNode=null,eventTimer=0;
  let activeTimer=0,submitUntil=0,routeSerial=0,bootAttempts=0;
  let checks=0;
  const idOf=(href=location.href)=>{try{const u=new URL(href,location.href);return u.origin===location.origin?u.pathname.match(/(?:^|\/)c\/([A-Za-z0-9_-]{12,80})(?:\/|$)/)?.[1]||null:null}catch{return null}};
  const later=(fn,ms)=>{const t=setTimeout(()=>{timers.delete(t);if(!destroyed)fn()},ms);timers.add(t);return t};
  const call=async(type,data={})=>{try{return await api.postMessage({type,document:doc,...data})}catch{return null}};
  const visible=n=>n instanceof HTMLElement&&!n.closest('[hidden],[aria-hidden="true"]')&&n.getClientRects().length>0;
  function label(rec){if(!rec)return null;return ['running','waiting'].includes(rec.status)&&Date.now()-Math.max(rec.at||0,rec.verifiedAt||0)>90000?'uncertain':rec.status}
  function paint(id){for(const node of links.get(id)||[]){if(!node.isConnected)continue;const s=label(records.get(id));if(s)node.setAttribute(ATTR,s);else node.removeAttribute(ATTR)}}
  function reconcile(){
    if(!sidebar?.isConnected)return;links.clear();
    for(const a of sidebar.querySelectorAll('a[href*="/c/"]')){const id=idOf(a.href);if(!id)continue;if(!links.has(id))links.set(id,new Set());links.get(id).add(a)}
    for(const id of links.keys())paint(id);
  }
  function attachSidebar(){
    const next=[...document.querySelectorAll('nav,aside,[data-testid="sidebar"]')].find(n=>n.querySelector('a[href*="/c/"]'));
    if(!next)return;
    if(sidebar!==next||!sideObserver){
      sideObserver?.disconnect();sidebar=next;
      sideObserver=new MutationObserver(list=>{
        const relevant=list.some(m=>m.type==='attributes'||[...m.addedNodes,...m.removedNodes].some(n=>n.nodeType===1&&(n.matches?.('a[href*="/c/"]')||n.querySelector?.('a[href*="/c/"]'))));
        if(relevant&&!sideTimer)sideTimer=later(()=>{sideTimer=0;reconcile()},120);
      });
      sideObserver.observe(sidebar,{childList:true,subtree:true,attributes:true,attributeFilter:['href','data-conversation-id']});
    }reconcile();
  }
  function latest(){
    const root=document.querySelector('main [class*="transcriptContent"]')||document.querySelector('main');
    const turns=root?.querySelectorAll('[data-turn-key],[data-testid^="conversation-turn-"]')||[];
    const last=turns[turns.length-1]||null;
    const nodes=last?.querySelectorAll('[data-talvt-turn-state]')||[];
    const node=last?.hasAttribute('data-talvt-turn-state')?last:nodes[nodes.length-1]||null;
    return {root,last,node,key:last?.getAttribute('data-turn-key')||last?.getAttribute('data-testid')||null};
  }
  function bindState(){
    const {root,last,node}=latest();const list=last?.parentElement||root;if(!list)return;
    if(turnObserver&&turnList===list&&stateNode===node)return;
    turnObserver?.disconnect();turnList=list;stateNode=node;
    if(!turnObserver)turnObserver=new MutationObserver(()=>{if(!eventTimer)eventTimer=later(()=>{eventTimer=0;bindState();check()},180)});
    turnObserver.observe(list,{childList:true,subtree:false});
    if(node&&node!==list)turnObserver.observe(node,{attributes:true,attributeFilter:['data-talvt-turn-state'],subtree:false});
  }
  function snapshot(){
    const {last,node,key}=latest(),raw=node?.getAttribute('data-talvt-turn-state');
    const currentTurn=!(priorKey&&key===priorKey);
    if(currentTurn&&key){priorKey=null;lastKey=key}
    const roots=last?.querySelectorAll('[class*="DilResponseRoot"],[data-dil-message-id],[class*="MarkdownRoot"],[data-message-author-role="assistant"]')||[];
    const hasAnswer=[...roots].some(n=>(n.textContent||'').trim().length>0);
    const running=['running','in_progress','streaming'].includes(raw);
    const waiting=['waiting_user','waiting_for_user'].includes(raw)||Boolean(last&&[...last.querySelectorAll('[data-testid*="approval" i] button,[data-testid*="permission" i] button')].some(visible));
    const hasDraft=[...document.querySelectorAll('#prompt-textarea,main textarea,main [contenteditable="true"]')].some(n=>(n.value||n.textContent||'').trim().length>0);
    // Return only a UI flag, never arbitrary alert text, answer text or URLs.
    const error=[...document.querySelectorAll('main [data-testid*="conversation-error" i],main [data-testid*="error-boundary" i]')].find(n=>visible(n)&&!n.closest('[data-turn-key],[data-testid^="conversation-turn-"]'));
    return {id:current,kind:'native',turnKey:key,currentTurn,
      nativeState:waiting?'waiting':running?'running':['complete','completed'].includes(raw)?'complete':null,
      answerReady:hasAnswer,hasAnswer,running,waiting,hasDraft,loadError:Boolean(error),
      canRetry:false,visible:!document.hidden,recoveryCanceled:submitUntil>Date.now()};
  }
  async function check(){
    if(!ready||!current||destroyed)return;
    checks++;bindState();const serial=routeSerial,id=current,value=snapshot();
    const reply=await call('observe',{observation:value});
    if(serial!==routeSerial||current!==id)return;
    if(reply?.record?.status){records.set(id,reply.record);paint(id)}
    if((value.running&&value.currentTurn)||submitUntil>Date.now()){
      if(!activeTimer)activeTimer=later(()=>{activeTimer=0;check()},document.hidden?6000:2500);
    }
  }
  function route(force=false){
    const id=idOf();if(id===current&&!force){attachSidebar();return}
    if(id!==current){priorKey=current?lastKey:null;current=id;routeSerial++;submitUntil=0;
      clearTimeout(activeTimer);timers.delete(activeTimer);activeTimer=0;
      turnObserver?.disconnect();turnList=null;stateNode=null}
    const serial=routeSerial;
    for(const ms of [0,450,1600,4500,10000,20000,45000,65000])later(()=>{if(serial===routeSerial){attachSidebar();check()}},ms);
  }
  async function boot(){
    if(ready||bootAttempts>=5)return;bootAttempts++;
    doc=document.documentElement?.getAttribute('data-native-conversation-document');
    if(!doc){later(boot,300);return}
    const reply=await call('boot');if(!reply?.ok){later(boot,1000);return}
    for(const [id,rec]of Object.entries(reply.states||{}))records.set(id,rec);
    const items=[];
    try{
      const old=JSON.parse(localStorage.getItem('cgpt-safari-conversation-state-v1')||'{}');
      for(const [id,v]of Object.entries(old).slice(0,300)){
        if(!v)continue;const status=({completed_read:'completed',completed_unread:'completed',waiting_user:'waiting',settling:'uncertain'})[v.status]||v.status;
        items.push({id,record:{status,at:Number(v.at||v.updatedAt)||0}});
      }
    }catch{}
    if(items.length){const migrated=await call('import',{items});for(const[id,rec]of Object.entries(migrated?.states||{}))records.set(id,rec)}
    // Do not delete legacy/site storage. Native persistence is now authoritative.
    ready=true;route(true);
  }
  async function wake(){
    if(!ready){boot();return}
    route();const reply=await call('refresh');
    for(const[id,rec]of Object.entries(reply?.states||{}))records.set(id,rec);
    attachSidebar();check();
  }
  function submit(){
    if(!current)return;submitUntil=Date.now()+30000;
    const submittedID=current;
    call('observe',{observation:{...snapshot(),kind:'submit'}}).then(r=>{if(r?.record?.status){records.set(submittedID,r.record);paint(submittedID)}});
    if(!activeTimer)activeTimer=later(()=>{activeTimer=0;check()},1800);
  }
  function clicked(e){
    const el=e.target instanceof Element?e.target:null;if(!el)return;
    const b=el.closest('button');
    if(b&&!b.disabled&&b.matches('[data-testid="send-button"],button[aria-label="Send prompt"],button[aria-label="发送消息"]'))submit();
    if(el.closest('a[href*="/c/"],button[aria-label*="sidebar" i],button[aria-label*="侧边栏"]'))for(const ms of [0,200,900,2500])later(()=>route(),ms);
  }
  function submitted(e){if(e.target instanceof HTMLFormElement&&e.target.querySelector('#prompt-textarea,textarea,[contenteditable="true"]'))submit()}
  const style=document.createElement('style');style.id='native-conversation-status-style';
  style.textContent=`a[${ATTR}]::after{font:10px/1.5 system-ui;opacity:.72;margin-left:5px;pointer-events:none;white-space:nowrap}a[${ATTR}="running"]::after{content:"进行中"}a[${ATTR}="completed"]::after{content:"已完成"}a[${ATTR}="waiting"]::after{content:"等待操作"}a[${ATTR}="uncertain"]::after{content:"待同步"}a[${ATTR}="stopped"]::after{content:"已停止"}`;
  document.head.appendChild(style);
  document.documentElement.setAttribute('data-native-parity-version',VERSION);
  document.addEventListener('click',clicked,true);document.addEventListener('submit',submitted,true);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)wake()});
  window.addEventListener('popstate',()=>route());
  globalThis.__IOS_NATIVE_RESILIENCE__={version:VERSION,wake,audit:()=>({ready,currentState:label(records.get(current)),checks,sidebarChats:links.size,nativeStateWatch:Boolean(turnList?.isConnected),storage:'native'})};
  boot();
})();
