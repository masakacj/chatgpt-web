// R4: repair only the stale bash.command argument description.
// No change to executors, authentication, allowed roots, or the v2 tool policy.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const OLD = 'Must not create or modify project files; use ${toolNames.edit} or ${toolNames.write} for file changes.';
const NEW = 'Prefer ${toolNames.edit} or ${toolNames.write} for ordinary project file edits; shell-based changes are permitted for user-authorized deployments, service maintenance, or system-owned configuration, with backups and verification.';
const TAG = 'DevSpace authorized maintenance policy v2';
const KEY = 'bashCommandParameterV4';
const SHA = x => crypto.createHash('sha256').update(x).digest('hex');
function fail(message) { throw new Error(message); }
function locate() {
  const dirs = [];
  if (process.env.DEVSPACE_PACKAGE_DIR) dirs.push(process.env.DEVSPACE_PACKAGE_DIR);
  dirs.push(path.join(path.dirname(process.execPath), 'node_modules', '@waishnav', 'devspace'));
  if (process.platform === 'win32') {
    if (process.env.APPDATA) dirs.push(path.join(process.env.APPDATA,'npm','node_modules','@waishnav','devspace'));
  } else {
    dirs.push('/usr/lib/node_modules/@waishnav/devspace', '/usr/local/lib/node_modules/@waishnav/devspace');
  }
  for (const dir of dirs) {
    const pkg = path.join(dir, 'package.json');
    const target = path.join(dir, 'dist', 'server.js');
    if (!fs.existsSync(pkg) || !fs.existsSync(target)) continue;
    let info;
    try { info = JSON.parse(fs.readFileSync(pkg, 'utf8')); } catch { continue; }
    if (info.name !== '@waishnav/devspace') continue;
    if (!['1.0.7','1.0.8'].includes(info.version)) fail('Unsupported DevSpace version: ' + info.version);
    return {target, version:info.version};
  }
  fail('Installed DevSpace 1.0.7/1.0.8 was not found');
}
function dataPaths() {
  const dir = process.env.DEVSPACE_TOOL_POLICY_STATE_DIR ||
    (process.platform === 'win32' ? path.join(process.env.ProgramData || 'C:\\ProgramData','DevSpaceToolPolicy') : '/var/backups/devspace-tool-policy');
  return {manifest: path.join(dir,'manifest.json')};
}
function count(text,needle) { return text.split(needle).length-1; }
function atomic(file,bytes,mode) {
  const tmp = file + '.r4-' + process.pid + '.tmp';
  try {
    fs.writeFileSync(tmp, bytes, {flag:'wx',mode});
    fs.chmodSync(tmp,mode);
    fs.renameSync(tmp,file);
  } finally { if (fs.existsSync(tmp)) fs.unlinkSync(tmp); }
}
function state() {
  const found=locate();
  const bytes=fs.readFileSync(found.target);
  const text=bytes.toString('utf8');
  const oldCount=count(text,OLD), newCount=count(text,NEW);
  const {manifest}=dataPaths();
  const hasManifest=fs.existsSync(manifest);
  const info=hasManifest?JSON.parse(fs.readFileSync(manifest,'utf8')):null;
  return {...found, bytes, text, hash:SHA(bytes), oldCount,newCount, manifest, info};
}
function verify(s) {
  if (s.oldCount+s.newCount!==1) fail('Unexpected bash.command source shape; refusing change');
  if (!s.text.includes(TAG)) fail('DevSpace v2 base policy missing; install the verified base policy first');
  if (!s.info || s.info.target!==s.target || s.info.afterSha256!==s.hash)
    fail('Base-policy manifest missing or SHA-256 mismatch; refusing change');
}
function metadata(s) {
  return {ok:true, version:s.version, target:s.target, sourceSHA256:s.hash,
    parameterDescription:s.newCount===1?'corrected':s.oldCount===1?'legacy':'unknown',
    compatible:s.oldCount+s.newCount===1, basePolicyInstalled:s.text.includes(TAG),
    manifestMatches:Boolean(s.info && s.info.afterSha256===s.hash && s.info.target===s.target)};
}
function change(operation) {
  const s=state(); verify(s);
  const isApply=operation==='apply';
  if (isApply && s.newCount===1) return {...metadata(s),alreadyApplied:true};
  if (!isApply && s.oldCount===1) return {...metadata(s),alreadyRolledBack:true};
  const extension=s.info[KEY];
  if (!isApply && (!extension || extension.afterSha256!==s.hash))
    fail('No matching R4 correction record; refusing rollback');
  if (isApply && extension) fail('Existing R4 record conflicts with the legacy source');
  const next=s.text.replace(isApply?OLD:NEW,isApply?NEW:OLD);
  if (count(next,isApply?NEW:OLD)!==1) fail('Replacement verification failed');
  const nextBytes=Buffer.from(next,'utf8'), nextSha=SHA(nextBytes);
  if (!isApply && nextSha!==extension.beforeSha256) fail('Rollback source checksum mismatch');
  const syntax=spawnSync(process.execPath,['--input-type=module','--check'],
    {input:nextBytes,encoding:'utf8',timeout:10000});
  if (syntax.status!==0) fail('Generated server.js failed node syntax check: '+String(syntax.stderr).slice(0,300));
  const updated={...s.info,afterSha256:nextSha};
  if (isApply) updated[KEY]={beforeSha256:s.hash,afterSha256:nextSha,updatedAt:new Date().toISOString()};
  else delete updated[KEY];
  const originalManifest=Buffer.from(JSON.stringify(s.info,null,2)+'\n');
  const nextManifest=Buffer.from(JSON.stringify(updated,null,2)+'\n');
  if (SHA(fs.readFileSync(s.target))!==s.hash) fail('Target changed during preflight');
  const sourceMode=fs.statSync(s.target).mode&0o777;
  const manifestMode=fs.statSync(s.manifest).mode&0o777;
  try {
    atomic(s.target,nextBytes,sourceMode);
    atomic(s.manifest,nextManifest,manifestMode);
    if (SHA(fs.readFileSync(s.target))!==nextSha) fail('Post-write source checksum mismatch');
  } catch(e) {
    // Only undo files that still have our exact bytes; never overwrite concurrent updates.
    if (SHA(fs.readFileSync(s.target))===nextSha) atomic(s.target,s.bytes,sourceMode);
    if (SHA(fs.readFileSync(s.manifest))===SHA(nextManifest)) atomic(s.manifest,originalManifest,manifestMode);
    throw e;
  }
  return {ok:true, action:operation, version:s.version, target:s.target,
    beforeSHA256:s.hash, afterSHA256:nextSha, manifestUpdated:true, authAndExecutorUnchanged:true,
    restartRequired:true, refreshChatGPTConnectorTools:true};
}
const action=process.argv[2]||'check';
try {
  if (action==='check'||action==='status') console.log(JSON.stringify(metadata(state())));
  else if (action==='apply'||action==='rollback') console.log(JSON.stringify(change(action)));
  else fail('Usage: node fix-bash-parameter.mjs check|status|apply|rollback');
} catch(e) { console.error('DEVSPACE_R4_ERROR: '+e.message); process.exitCode=1; }
