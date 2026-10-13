import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
const project=await fs.readFile(path.join(root,'project.yml'),'utf8');
const optimized=project.match(/  ChatGPTWebOptimized:\r?\n([\s\S]*?)(?=\r?\n  ChatGPTWebOptimizedTests:)/)?.[1]||'';
const mirror=project.match(/  ChatGPTWeb:\r?\n([\s\S]*?)(?=\r?\n  ChatGPTWebOptimized:)/)?.[1]||'';
assert.match(optimized,/path: OptimizedApp/);
assert.match(optimized,/path: OptimizedResources/);
for(const denied of ['path: App','path: Resources\n','SafariScriptAction','SharedTab','PCCompanion'])assert(!optimized.includes(denied),'optimized target boundary: '+denied);
for(const denied of ['OptimizedApp','OptimizedResources','ChatGPTWebOptimized'])assert(!mirror.includes(denied),'mirror target boundary: '+denied);

async function files(dir){
 const result=[];
 for(const entry of await fs.readdir(dir,{withFileTypes:true})){
  const full=path.join(dir,entry.name);
  if(entry.isDirectory())result.push(...await files(full));
  else result.push(full);
 }
 return result;
}
const sourceFiles=await files(path.join(root,'OptimizedApp'));
const forbidden=[/SharedTab/,/PCCompanion/,/mobile[_-]?bridge/i,/chatgpt-pc/i,/SafariContainer/,/SFSafariViewController/,/UnifiedScriptStore/];
for(const file of sourceFiles.filter(f=>f.endsWith('.swift'))){
 const text=await fs.readFile(file,'utf8');
 for(const pattern of forbidden)assert(!pattern.test(text),`${path.relative(root,file)} imports forbidden ${pattern}`);
}
console.log(JSON.stringify({pass:true,optimizedSwiftFiles:sourceFiles.filter(f=>f.endsWith('.swift')).length,mirrorBoundary:true,safariDependency:false}));
