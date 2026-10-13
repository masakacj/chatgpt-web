import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../Contracts/ConversationManager/v2/',import.meta.url));
const manifest=JSON.parse(await fs.readFile(path.join(root,'manifest.json'),'utf8'));
assert.equal(manifest.cmProtocol,2);assert.equal(manifest.cmVersion,'0.2.2');
for(const [name,expected] of Object.entries(manifest.files)){
 const source=(await fs.readFile(path.join(root,name),'utf8')).replace(/\r\n/g,'\n');
 const hash=crypto.createHash('sha256').update(source,'utf8').digest('hex');
 assert.equal(hash,expected,'contract hash mismatch: '+name);
}
const reducer=JSON.parse(await fs.readFile(path.join(root,'reducer-cases.json'),'utf8'));
assert(reducer.cases.length>=10);assert(reducer.cases.every(x=>x.events.length===x.decisions.length));
console.log(JSON.stringify({pass:true,protocol:manifest.cmProtocol,version:manifest.cmVersion,reducerCases:reducer.cases.length,files:Object.keys(manifest.files).length}));
