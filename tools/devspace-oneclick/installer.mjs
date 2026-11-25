import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import net from 'node:net';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {pipeline} from 'node:stream/promises';
import {Readable} from 'node:stream';

const VERSION='1.1.1';
const PKG='@waishnav/devspace';
const ARCHIVE='https://registry.npmjs.org/@waishnav/devspace/-/devspace-1.1.1.tgz';
const ARCHIVE_SHA='cee9f12560e1c1f7e221164a0de96a5e6b48631457377739e3193bb331d26bf066baab4735af761d1af380d5526fbfbade88de3fce7738ff57780699d6b010e1';
const CF_VERSION='2026.11.1';
const CF={
 'win32-x64':['cloudflared-windows-amd64.exe','341deda3db5ec498a0482254d6c38c0b7cf01a30c37bb5dd95d2216d08955e35'],
 'linux-x64':['cloudflared-linux-amd64','97bb3b02d23a5980fc9c15a1a270e692da1923f103f920d5b16d4931d5ab55e7'],
 'linux-arm64':['cloudflared-linux-arm64','b155cec3e48e489cfb8e5c602769fb8c771083018d8881d68b4d18a791567c5a']
};
const win=process.platform==='win32';
const self=fileURLToPath(import.meta.url);
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const say=s=>console.log('[DevSpace OneClick] '+s);
const safeError=(e)=>e instanceof Error?e.message:String(e);
function invariant(ok,msg){if(!ok)throw new Error(msg)}
function exists(p){try{return fs.existsSync(p)}catch{return false}}
function own(p){return path.resolve(p)}
function isUnder(child,parent){const rel=path.relative(own(parent),own(child));return rel!==''&&!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)}
function readJson(p){return JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''))}
function writeJson(p,o,mode=0o600){fs.mkdirSync(path.dirname(p),{recursive:true,mode:0o700}); const tmp=p+'.'+process.pid+'.tmp';fs.writeFileSync(tmp,JSON.stringify(o,null,2)+'\n',{mode});fs.renameSync(tmp,p)}
function parseArgs(argv){
 const o={};
 for(let i=0;i<argv.length;i++){
  const key=argv[i]; invariant(/^--[a-z-]+$/.test(key),'Unexpected argument');
  if(['--quick','--no-autostart','--test-only'].includes(key))o[key.slice(2)]=true;
  else{invariant(i+1<argv.length&&!argv[i+1].startsWith('--'),'Missing value for '+key);o[key.slice(2)]=argv[++i]}
 }
 return o
}
function execEnv(root,extra={}){
 const priv=path.join(root,'private','devspace');
 const tmp=path.join(root,'tmp');const cache=path.join(root,'npm-cache');
 return {...process.env,DEVSPACE_CONFIG_DIR:priv,TEMP:tmp,TMP:tmp,TMPDIR:tmp,NPM_CONFIG_CACHE:cache,...extra}
}
function run(exe,args,options={}){
 return new Promise((resolve,reject)=>{
  const ch=spawn(exe,args,{windowsHide:true,stdio:['ignore','pipe','pipe'],...options});
  let out='',err='';
  ch.stdout.on('data',b=>{out=(out+b.toString()).slice(-1000000)});
  ch.stderr.on('data',b=>{err=(err+b.toString()).slice(-100000)});
  ch.on('error',reject);
  ch.on('close',code=>resolve({code,out,err}));
 })
}
async function checked(exe,args,options={},stage='command'){
 const r=await run(exe,args,options);
 // Do not echo arbitrary command output: it might contain secrets or account paths.
 invariant(r.code===0,stage+' failed (exit '+r.code+'). See local installation logs.');
 return r.out
}
function findExe(name){
 const dirs=(process.env.PATH||'').split(path.delimiter);
 const candidates=win?[name+'.exe',name+'.cmd',name]:[name];
 for(const d of dirs){if(!d)continue;for(const c of candidates){const p=path.join(d,c);if(exists(p))return p}}
 return null
}
async function digest(p,alg='sha256'){
 const h=crypto.createHash(alg);for await(const b of fs.createReadStream(p))h.update(b);return h.digest('hex')
}
async function download(url,dest,expected,alg='sha256'){
 if(exists(dest)&&(await digest(dest,alg))===expected)return dest;
 const partial=dest+'.'+process.pid+'.part';
 fs.mkdirSync(path.dirname(dest),{recursive:true});
 for(let attempt=0;attempt<2;attempt++){
  try{
   fs.rmSync(partial,{force:true});
   const res=await fetch(url,{signal:AbortSignal.timeout(240000),redirect:'follow'});
   invariant(res.ok,'download HTTP '+res.status);
   await pipeline(Readable.fromWeb(res.body),fs.createWriteStream(partial,{flags:'wx'}));
   invariant((await digest(partial,alg))===expected,'download checksum mismatch');
   fs.renameSync(partial,dest);return dest
  }catch(e){
   fs.rmSync(partial,{force:true});
   // A pinned digest allows a different downloader without weakening integrity.
   const curl=findExe('curl');
   if(curl){
    try{
     await checked(curl,['--fail','--location','--silent','--show-error','--connect-timeout','20','--max-time','240','--output',partial,url],{},'curl download');
     invariant((await digest(partial,alg))===expected,'download checksum mismatch');
     fs.renameSync(partial,dest);return dest
    }catch{fs.rmSync(partial,{force:true})}
   }
   if(attempt===1)throw new Error('Verified download failed: '+new URL(url).hostname);
   await sleep(1000)
  }
 }
}
function validOrigin(url){
 let u;try{u=new URL(url)}catch{throw new Error('Invalid publicUrl')}
 invariant(u.protocol==='https:'&&!u.username&&!u.password&&!u.search&&!u.hash&&u.pathname==='/'&&(!u.port||u.port==='443'),'publicUrl must be an HTTPS origin (no /mcp)');
 return u.origin
}
function safeRoot(root,workspace){
 invariant(path.isAbsolute(root)&&own(root)!==path.parse(root).root,'Install root must be a dedicated absolute directory');
 invariant(path.isAbsolute(workspace)&&own(workspace)!==path.parse(workspace).root&&own(workspace)!==own(os.homedir()),'Workspace must be a narrow dedicated folder');
 invariant(!isUnder(path.join(root,'private'),workspace)&&own(workspace)!==own(root),'Workspace must not expose installation or private state');
 for(const d of ['private','program','tools','logs','state','downloads','npm-cache','tmp']){
  const protectedDir=path.join(root,d);
  invariant(own(workspace)!==own(protectedDir)&&!isUnder(workspace,protectedDir),'Workspace overlaps installer-owned files');
 }
}
function npmCli(){
 const nd=path.dirname(process.execPath);
 const candidates=[path.join(nd,'node_modules','npm','bin','npm-cli.js'),path.join(nd,'..','lib','node_modules','npm','bin','npm-cli.js'),'/usr/share/nodejs/npm/bin/npm-cli.js'];
 const np=findExe('npm');if(np){try{const p=fs.realpathSync(np);if(p.endsWith('.js'))candidates.unshift(p)}catch{}}
 for(const p of candidates)if(exists(p))return own(p);
 throw new Error('npm CLI not available alongside Node; install Node LTS with npm.')
}
function packageCli(prefix){return path.join(prefix,'node_modules','@waishnav','devspace','bin','devspace.js')}
async function validatePackage(prefix,env){
 const dir=path.dirname(path.dirname(packageCli(prefix)));
 for(const x of ['package.json','dist/cli.js','dist/unsafe-narrow.js','bin/devspace.js'])invariant(exists(path.join(dir,x)),'Incomplete DevSpace package: '+x);
 const m=readJson(path.join(dir,'package.json'));invariant(m.name===PKG&&m.version===VERSION,'DevSpace package version mismatch');
 const r=await run(process.execPath,[packageCli(prefix),'--version'],{env});
 invariant(r.code===0&&r.out.includes(VERSION),'DevSpace CLI cannot load full dependencies');
}
async function installPackage(root,env){
 const prefix=path.join(root,'program','devspace-'+VERSION);
 if(exists(prefix)){
  try{await validatePackage(prefix,env);say('Verified existing DevSpace '+VERSION);return prefix}
  catch{say('Existing program incomplete; preparing an isolated verified replacement.')}
 }
 const archive=path.join(root,'downloads','devspace-'+VERSION+'.tgz');
 await download(ARCHIVE,archive,ARCHIVE_SHA,'sha512');
 const npm=npmCli();const log=path.join(root,'logs','npm-install.log');
 let stage;
 for(const registry of ['https://registry.npmjs.org','https://registry.npmmirror.com']){
  stage=prefix+'.candidate-'+crypto.randomUUID();fs.mkdirSync(stage,{recursive:true});
  say('Installing full npm tree from '+new URL(registry).hostname);
  // Use node npm-cli.js, not Windows npm.cmd. Never touch the live prefix.
  const r=await run(process.execPath,[npm,'install','--prefix',stage,'--registry',registry,'--no-save','--omit=dev','--no-audit','--no-fund','--no-progress','--fetch-retries=1','--fetch-timeout=90000',archive],{env,cwd:stage});
  fs.appendFileSync(log,'npm registry='+new URL(registry).hostname+' exit='+r.code+'\n');
  if(r.code===0){try{await validatePackage(stage,env);break}catch{}}
  stage=null;
 }
 invariant(stage,'No complete npm dependency tree could be installed. Failed candidates retained for diagnosis.');
 const backup=prefix+'.previous-'+crypto.randomUUID();
 if(exists(prefix))fs.renameSync(prefix,backup);
 try{fs.renameSync(stage,prefix)}catch(e){if(exists(backup)&&!exists(prefix))fs.renameSync(backup,prefix);throw e}
 await validatePackage(prefix,env);
 return prefix
}
async function cfBinary(root){
 const item=CF[process.platform+'-'+process.arch];
 invariant(item,'Supported platforms: Windows x64, Linux x64/arm64');
 const exe=path.join(root,'tools',win?'cloudflared.exe':'cloudflared');
 await download('https://github.com/cloudflare/cloudflared/releases/download/'+CF_VERSION+'/'+item[0],exe,item[1]);
 if(!win)fs.chmodSync(exe,0o700);
 await checked(exe,['--version'],{},'cloudflared runtime check');return exe
}
function secureDir(dir){
 fs.mkdirSync(dir,{recursive:true,mode:0o700});
 if(!win){fs.chmodSync(dir,0o700);return}
 // Protect the local credential directory from other ordinary local users.
 const ps="$ErrorActionPreference='Stop';$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$p=$env:DEVSPACE_PRIVATE_DIR;& icacls.exe $p '/inheritance:r' '/grant:r' ('*'+$sid+':(OI)(CI)F') '*S-1-5-18:(OI)(CI)F' | Out-Null;if($LASTEXITCODE -ne 0){exit 1}";
 const r=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',ps],{windowsHide:true,env:{...process.env,DEVSPACE_PRIVATE_DIR:dir},stdio:'ignore'});
 invariant(r.status===0,'Could not restrict private credential directory ACL')
}
function profileFrom(o,root){
 const file=o.profile||process.env.DEVSPACE_PROFILE_FILE;
 if(file){
  invariant(exists(file),'Private deployment profile not found');
  const p=readJson(file);invariant(p&&typeof p==='object'&&!Array.isArray(p),'Invalid deployment profile');return p
 }
 if(exists(path.join(root,'private','deployment.json')))return readJson(path.join(root,'private','deployment.json'));
 invariant(o.quick,'A named tunnel deployment needs a private profile. Use --quick only for a temporary test.');
 return {mode:'quick'}
}
function validateProfile(p,o){
 const mode=p.mode||'named';invariant(['named','quick'].includes(mode),'Invalid tunnel mode');
 if(mode==='named'){
  p.publicUrl=validOrigin(p.publicUrl);
  invariant(typeof p.tunnelToken==='string'||typeof p.tunnelTokenFile==='string','Named tunnel token must be supplied privately');
 }else{invariant(o.quick||p.mode==='quick','Quick tunnel must be explicitly selected')}
 if(p.bark){
  invariant(typeof p.bark==='object','Invalid Bark config');
  const b=p.bark;const u=new URL(b.server);
  invariant(u.protocol==='https:'&&!u.username&&!u.password&&!u.search&&!u.hash,'Bark server must be HTTPS');
  invariant(typeof b.deviceKey==='string'&&b.deviceKey.length>=12,'Missing Bark device key');
  invariant(typeof b.encryptionKey==='string'&&[16,24,32].includes(Buffer.byteLength(b.encryptionKey,'utf8')),'Bark CBC key must be 16/24/32 UTF-8 bytes')
 }
 return {...p,mode}
}
function barkCipher(payload,key){
 const k=Buffer.from(key,'utf8');invariant([16,24,32].includes(k.length),'Invalid Bark AES key length');
 // The documented Bark CBC API accepts the actual IV string, not hex bytes.
 const iv=crypto.randomBytes(12).toString('base64url').slice(0,16);
 const c=crypto.createCipheriv('aes-'+(k.length*8)+'-cbc',k,Buffer.from(iv,'utf8'));
 const ciphertext=Buffer.concat([c.update(JSON.stringify(payload),'utf8'),c.final()]).toString('base64');
 return {ciphertext,iv}
}
async function barkPush(b,payload){
 const body=barkCipher(payload,b.encryptionKey);
 // Only routing key, ciphertext and random IV are transmitted. Never log either key.
 const endpoint=new URL(b.server);endpoint.pathname=endpoint.pathname.replace(/\/+$/,'')+'/push';
 const r=await fetch(endpoint,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{'content-type':'application/json'},body:JSON.stringify({device_key:b.deviceKey,...body})});
 invariant(r.ok,'Encrypted Bark HTTP request failed');let j;try{j=await r.json()}catch{}
 invariant(j&&j.code===200,'Bark did not acknowledge encrypted push')
}
async function notify(root,state,profile){
 if(!profile.bark){say('Bark not configured; use the public receipt. Owner key remains local.');return {address:false,owner:false}}
 const b=profile.bark;const receipt=readJson(path.join(root,'receipt.json'));
 let address=false,owner=false;
 try{
  await barkPush(b,{title:'DevSpace ready: '+receipt.name,body:receipt.mcpUrl,copy:receipt.mcpUrl,group:'DevSpace',isArchive:'0'});address=true;
  if(b.notifyOwnerKey===true){
   const auth=readJson(path.join(root,'private','devspace','auth.json'));
   invariant(typeof auth.ownerToken==='string'&&auth.ownerToken.length>=16,'Owner key not found');
   await barkPush(b,{title:'DevSpace Owner Key: '+receipt.name,body:'Long press and choose Copy. Keep private.',copy:auth.ownerToken,group:'DevSpace',isArchive:'0'});
   owner=true
  }
 }catch{say('Bark delivery not confirmed. No plaintext fallback was attempted.')}
 return {address,owner}
}
async function portBusy(port){
 return new Promise(resolve=>{const s=net.createConnection({host:'127.0.0.1',port});s.setTimeout(1000);s.once('connect',()=>{s.destroy();resolve(true)});s.once('timeout',()=>{s.destroy();resolve(false)});s.once('error',()=>resolve(false))})
}
async function freeTestPort(){
 return new Promise((resolve,reject)=>{
  const s=net.createServer();s.once('error',reject);
  s.listen(0,'127.0.0.1',()=>{const n=s.address().port;s.close(e=>e?reject(e):resolve(n))})
 })
}
function alive(pid){try{process.kill(Number(pid),0);return true}catch{return false}}
function lock(root){
 const f=path.join(root,'install.lock');
 try{fs.writeFileSync(f,String(process.pid),{flag:'wx',mode:0o600})}
 catch{throw new Error('Another installation is active or left install.lock. Inspect it locally before retrying.')}
 return ()=>{try{if(fs.readFileSync(f,'utf8')===String(process.pid))fs.unlinkSync(f)}catch{}}
}
async function config(root,state,origin){
 const env=execEnv(root);const cli=state.cli;
 const p=path.join(root,'private','devspace','config.jsonc');
 const auth=path.join(root,'private','devspace','auth.json');
 if(!exists(p)||!exists(auth)){
  invariant(!exists(p)&&!exists(auth),'Partial private configuration found; refusing to overwrite Owner credentials');
  await checked(process.execPath,[cli,'init','--yes','--public-url',origin,'--roots',state.workspace,'--json'],{env,cwd:root},'DevSpace init');
 }else{
  await checked(process.execPath,[cli,'config','set','publicBaseUrl',origin],{env,cwd:root},'DevSpace public URL update');
 }
 const parsed=JSON.parse(await checked(process.execPath,[cli,'config','get'],{env,cwd:root},'DevSpace config readback'));
 parsed.server.host='127.0.0.1';parsed.server.port=state.port;parsed.server.publicBaseUrl=origin;parsed.server.allowedHosts=[];
 parsed.workspaces.allowedRoots=[state.workspace];parsed.workspaces.worktreeRoot=path.join(root,'worktrees');
 parsed.storage.stateDir=path.join(root,'state');
 // Fresh dedicated deployment only. Existing DevSpace installations are not modified.
 parsed.subagents=undefined;
 delete parsed.subagents;
 fs.writeFileSync(p,JSON.stringify(parsed,null,2)+'\n',{mode:0o600});
 if(!win){fs.chmodSync(p,0o600);fs.chmodSync(auth,0o600)}
 const final=JSON.parse(await checked(process.execPath,[cli,'config','get'],{env,cwd:root},'DevSpace final config validation'));
 invariant(final.server.port===state.port&&final.server.publicBaseUrl===origin&&final.workspaces.allowedRoots.length===1&&own(final.workspaces.allowedRoots[0])===own(state.workspace),'Config readback mismatch')
}
async function oauthProbe(origin,localPort){
 // Local requests use the configured public Host to match OAuth metadata.
 const local=localPort?'http://127.0.0.1:'+localPort:origin;
 const headers=localPort?{Host:new URL(origin).host}:{};
 const req=await fetch(local+'/mcp',{method:'POST',redirect:'error',signal:AbortSignal.timeout(12000),headers:{...headers,'content-type':'application/json','accept':'application/json, text/event-stream'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-03-26',capabilities:{},clientInfo:{name:'oneclick-health',version:'1'}}})});
 invariant(req.status===401,'Expected unauthenticated MCP HTTP 401, got '+req.status);
 const h=req.headers.get('www-authenticate')||'';
 const match=h.match(/resource_metadata="([^"]+)"/i);
 invariant(match,'Missing OAuth resource discovery header');
 const metaUrl=new URL(match[1]);
 invariant(metaUrl.origin===origin,'OAuth metadata origin mismatch');
 const metadata=await fetch(local+metaUrl.pathname+metaUrl.search,{redirect:'error',signal:AbortSignal.timeout(12000),headers});
 invariant(metadata.ok,'OAuth resource discovery failed');
 const r=await metadata.json();
 invariant(r.resource===origin+'/mcp'&&Array.isArray(r.authorization_servers)&&r.authorization_servers.some(x=>String(x).replace(/\/$/,'')===origin),'Unexpected protected resource metadata');
 const discovery=await fetch(local+'/.well-known/oauth-authorization-server',{redirect:'error',signal:AbortSignal.timeout(12000),headers});
 invariant(discovery.ok,'OAuth authorization-server discovery failed');
 const d=await discovery.json();
 invariant(String(d.issuer).replace(/\/$/,'')===origin&&new URL(d.authorization_endpoint).origin===origin&&new URL(d.token_endpoint).origin===origin,'OAuth issuer/endpoints mismatch');
 return true
}
async function waitFor(fn,attempts=30){
 let last;
 for(let i=0;i<attempts;i++){try{return await fn()}catch(e){last=e;await sleep(2000)}}
 throw last||new Error('Health probe failed')
}
function startLogged(exe,args,root,logname,env){
 const file=path.join(root,'logs',logname);const fd=fs.openSync(file,'a',0o600);
 try{return spawn(exe,args,{cwd:root,env,windowsHide:true,stdio:['ignore',fd,fd]})}finally{fs.closeSync(fd)}
}
async function supervisor(root){
 const state=readJson(path.join(root,'private','runtime.json'));const env=execEnv(root);
 const pidfile=path.join(root,'supervisor.pid');
 let old;try{old=fs.readFileSync(pidfile,'utf8')}catch{}
 invariant(!old||!alive(old),'Deployment supervisor is already running');
 fs.writeFileSync(pidfile,String(process.pid),{mode:0o600});
 let child=null,tunnel=null,stopping=false;
 function stop(){stopping=true;try{child?.kill()}catch{}try{tunnel?.kill()}catch{}}
 process.on('SIGINT',stop);process.on('SIGTERM',stop);
 try{
  while(!stopping){
   fs.rmSync(path.join(root,'receipt.json'),{force:true});
   let origin=state.publicUrl;
   const cfArgs=['tunnel','--no-autoupdate','--protocol','http2'];
   if(state.mode==='quick'){
    const qlog=path.join(root,'logs','quick-tunnel.log');
    fs.writeFileSync(qlog,'',{mode:0o600});
    tunnel=startLogged(state.cloudflared,[...cfArgs,'--url','http://127.0.0.1:'+state.port],root,'quick-tunnel.log',env);
    const deadline=Date.now()+90000;
    while(Date.now()<deadline&&!stopping){
     const match=fs.readFileSync(qlog,'utf8').match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/i);
     if(match){origin=match[0];break}
     if(tunnel.exitCode!==null)throw new Error('Quick Tunnel creation failed (possibly rate limited). Use named tunnel.');
     await sleep(500)
    }
    invariant(origin,'Quick Tunnel did not obtain an address')
   }
   origin=validOrigin(origin);
   invariant(!(await portBusy(state.port)),'Port already occupied; no unrelated service was stopped');
   await config(root,state,origin);
   child=startLogged(process.execPath,[state.cli,'serve'],root,'devspace.log',env);
   child.on('error',()=>{});
   await waitFor(()=>oauthProbe(origin,state.port),20);
   if(state.mode==='named'){
    tunnel=startLogged(state.cloudflared,[...cfArgs,'run','--token-file',path.join(root,'private','tunnel-token')],root,'cloudflared.log',env);
   }
   tunnel.on('error',()=>{});
   // Readiness requires actual public OAuth discovery, not just a local port.
   await waitFor(()=>oauthProbe(origin),35);
   writeJson(path.join(root,'receipt.json'),{status:'ready',name:state.name,mode:state.mode,mcpUrl:origin+'/mcp',auth:'OAuth',workspace:state.workspace,readyAt:new Date().toISOString()});
   say('Ready: '+origin+'/mcp');
   await new Promise(resolve=>{const done=()=>resolve();child.once('exit',done);tunnel.once('exit',done);if(child.exitCode!==null||tunnel.exitCode!==null)done()});
   if(stopping)break;
   throw new Error('A managed service exited; startup supervisor will report failure.');
  }
 }finally{
  stop();fs.rmSync(path.join(root,'receipt.json'),{force:true});
  try{if(fs.readFileSync(pidfile,'utf8')===String(process.pid))fs.unlinkSync(pidfile)}catch{}
 }
}
async function registerAndStart(root,noAutostart){
 const script=path.join(root,'installer.mjs');
 const args=[script,'supervise','--root',root];
 const env=execEnv(root);
 if(noAutostart){
  const fd=fs.openSync(path.join(root,'logs','supervisor.log'),'a',0o600);
  try{const p=spawn(process.execPath,args,{cwd:root,env,windowsHide:true,detached:true,stdio:['ignore',fd,fd]});p.unref()}finally{fs.closeSync(fd)}
  return 'manual'
 }
 if(win){
  // User-logon startup, not SYSTEM. Avoid password-bearing service accounts.
  const psfile=path.join(root,'start-hidden.ps1');
  const quote=x=>"'"+x.replaceAll("'","''")+"'";
  const cmd="$ErrorActionPreference='Stop';$env:PATH="+quote(process.env.PATH||'')+";Start-Process -WindowStyle Hidden -FilePath "+quote(process.execPath)+" -ArgumentList @("+[quote('"'+script+'"'),quote('supervise'),quote('--root'),quote('"'+root+'"')].join(',')+") -WorkingDirectory "+quote(root)+" -RedirectStandardOutput "+quote(path.join(root,'logs','supervisor-out.log'))+" -RedirectStandardError "+quote(path.join(root,'logs','supervisor-err.log'));
  fs.writeFileSync(psfile,cmd+'\r\n');
  const register="$ErrorActionPreference='Stop';$p=$env:DEVSPACE_START_SCRIPT;$key='HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run';New-Item -Path $key -Force | Out-Null;$v='powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"'+$p+'\"';New-ItemProperty -Path $key -Name $env:DEVSPACE_RUN_NAME -Value $v -PropertyType String -Force | Out-Null; & $p";
  const runName='DevSpaceOneClick-'+crypto.createHash('sha256').update(root.toLowerCase()).digest('hex').slice(0,10);
  await checked('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command',register],{env:{...env,DEVSPACE_START_SCRIPT:psfile,DEVSPACE_RUN_NAME:runName}},'Windows user-logon startup registration');
  return 'windows-user-logon'
 }
 // Prefer the user service; if unavailable, use a dedicated system service
 // running as this non-root account only when sudo -n is available.
 const unitName='devspace-oneclick-'+crypto.createHash('sha256').update(root).digest('hex').slice(0,10)+'.service';
 const userUnit=await run('systemctl',['--user','show-environment'],{env});
 const q=x=>'"'+String(x).replaceAll('\\','\\\\').replaceAll('"','\\"').replaceAll('%','%%')+'"';
 const unit='[Unit]\nDescription=DevSpace OneClick (user-owned)\nAfter=network-online.target\n[Service]\nType=simple\nWorkingDirectory='+q(root)+'\nEnvironment='+q('PATH='+process.env.PATH)+'\nExecStart='+[process.execPath,...args].map(q).join(' ')+'\nRestart=on-failure\nRestartSec=5\n[Install]\nWantedBy=default.target\n';
 if(userUnit.code===0){
  const d=path.join(os.homedir(),'.config','systemd','user');fs.mkdirSync(d,{recursive:true});
  const f=path.join(d,unitName);
  invariant(!exists(f)||fs.readFileSync(f,'utf8').includes('DevSpace OneClick (user-owned)'),'Existing unrelated service has this name');
  fs.writeFileSync(f,unit);
  await checked('systemctl',['--user','daemon-reload'],{env},'systemd user reload');
  await checked('systemctl',['--user','enable','--now',unitName],{env},'systemd user start');
  const linger=await run('loginctl',['show-user',os.userInfo().username,'-p','Linger','--value']).catch(()=>({code:1,out:''}));
  return linger.code===0&&linger.out.trim()==='yes'?'linux-user-boot':'linux-user-session'
 }
 const sudo=findExe('sudo');
 invariant(sudo,'No user systemd or sudo available. Use --no-autostart for a manual session.');
 invariant(process.getuid()!==0,'Run installer as a non-root target user');
 const f=path.join(root,'devspace-oneclick.service');
 const systemUnit=unit.replace('[Service]\n','[Service]\nUser='+os.userInfo().username+'\nGroup='+process.getgid()+'\n').replace('WantedBy=default.target','WantedBy=multi-user.target');
 fs.writeFileSync(f,systemUnit);
 invariant((await run(sudo,['-n','true'])).code===0,'System startup needs passwordless sudo or user systemd. Use --no-autostart or enable user services.');
 const dst='/etc/systemd/system/'+unitName;
 if(exists(dst))invariant(fs.readFileSync(dst,'utf8').includes('DevSpace OneClick (user-owned)'),'Existing unrelated service has this name');
 await checked(sudo,['-n','install','-m','0644',f,dst],{},'install dedicated system unit');
 await checked(sudo,['-n','systemctl','daemon-reload'],{},'systemd reload');
 await checked(sudo,['-n','systemctl','enable','--now',unitName],{},'systemd start');
 return 'linux-system-boot'
}
async function deploy(o){
 const root=own(o.root||'');invariant(o.root,'--root is required from the platform bootstrap');
 const workspace=own(o.workspace||path.join(root,'workspace'));
 safeRoot(root,workspace);
 const privateDir=path.join(root,'private');
 fs.mkdirSync(root,{recursive:true});for(const d of ['logs','tmp','npm-cache','downloads','tools','program'])fs.mkdirSync(path.join(root,d),{recursive:true});
 const release=lock(root);
 try{
  secureDir(privateDir);
  const p=o['test-only']?{mode:'quick'}:validateProfile(profileFrom(o,root),o);
  const stored=path.join(privateDir,'deployment.json');
  // Never overwrite a live deployment profile with another host or token.
  if(exists(stored)){
   const previous=readJson(stored);
   invariant(previous.mode===p.mode&&(p.mode!=='named'||previous.publicUrl===p.publicUrl),'Existing deployment targets a different tunnel; use a new dedicated root')
  }
  if(p.mode==='named'){
   const token=(p.tunnelTokenFile?fs.readFileSync(p.tunnelTokenFile,'utf8'):p.tunnelToken).trim();
   invariant(token.length>=32,'Invalid named connector token');
   const tokenPath=path.join(privateDir,'tunnel-token');
   fs.writeFileSync(tokenPath,token+'\n',{mode:0o600});delete p.tunnelToken; p.tunnelTokenFile=tokenPath;
  }
  writeJson(stored,p);
  fs.mkdirSync(workspace,{recursive:true});
  const realWorkspace=fs.realpathSync(workspace), realRoot=fs.realpathSync(root);
  safeRoot(realRoot,realWorkspace);
  const port=Number(o['test-only']?await freeTestPort():(p.port||7676));invariant(Number.isInteger(port)&&port>=1024&&port<=65535,'Invalid local port');
  const env=execEnv(root);
  // Only one dedicated supervisor; repeated deployment is a health check.
  const pidfile=path.join(root,'supervisor.pid');
  const pid=exists(pidfile)?fs.readFileSync(pidfile,'utf8'):'';
  if(pid&&alive(pid)){
   const receipt=await waitFor(async()=>{const r=readJson(path.join(root,'receipt.json'));await oauthProbe(new URL(r.mcpUrl).origin);return r},10);
   say('Existing deployment is healthy: '+receipt.mcpUrl);return
  }
  invariant(!(await portBusy(port)),'Local port is occupied by another service. Choose another configured port; existing service unchanged.');
  if(!exists(path.join(root,'program','devspace-'+VERSION))){
   const disk=fs.statfsSync(root,{bigint:true});
   invariant(disk.bavail*disk.bsize>=3n*1024n*1024n*1024n,'Installation volume needs at least 3 GiB free; choose another install root.');
  }
  say('Verified disk root and narrow workspace');
  const prefix=await installPackage(root,env);
  const cloudflared=o['test-only']?'':await cfBinary(root);
  const state={mode:p.mode,publicUrl:p.publicUrl||'',name:String(p.name||os.hostname()),workspace,port,cli:packageCli(prefix),cloudflared};
  writeJson(path.join(privateDir,'runtime.json'),state);
  if(own(self)!==own(path.join(root,'installer.mjs')))fs.copyFileSync(self,path.join(root,'installer.mjs'));
  if(o['test-only']){
   // Real isolated loopback server test; no public tunnel, push, or autostart.
   const fake='https://devspace-test.example.invalid';await config(root,state,fake);
   const proc=startLogged(process.execPath,[state.cli,'serve'],root,'devspace-test.log',env);
   try{await waitFor(()=>oauthProbe(fake,state.port),15);say('TEST_ONLY_OK (complete CLI, config, loopback MCP and OAuth)')}
   finally{try{proc.kill()}catch{}}
   return
  }
  const startup=await registerAndStart(root,o['no-autostart']);
  const receipt=await waitFor(async()=>{const r=readJson(path.join(root,'receipt.json'));await oauthProbe(new URL(r.mcpUrl).origin);return r},70);
  const result=await notify(root,state,p);
  const out={...receipt,startup,notifications:result};
  writeJson(path.join(root,'receipt.json'),out);
  say('READY '+receipt.mcpUrl);say('Owner key stored privately; never printed.');
  say('Startup: '+startup);say('Receipt: '+path.join(root,'receipt.json'));
 }finally{release()}
}
export {barkCipher,validOrigin,safeRoot,oauthProbe,parseArgs,validateProfile,validatePackage};
if(process.argv[1]&&own(process.argv[1])===own(self)){
 const [action,...args]=process.argv.slice(2);const o=parseArgs(args);
 try{
  if(action==='deploy')await deploy(o);
  else if(action==='supervise')await supervisor(own(o.root));
  else throw new Error('Usage: installer.mjs deploy|supervise --root PATH [--profile PATH | --quick]');
 }catch(e){console.error('[DevSpace OneClick] FAILED: '+safeError(e));process.exitCode=1}
}

