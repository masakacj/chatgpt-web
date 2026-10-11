import fs from 'node:fs';
import assert from 'node:assert/strict';
const p='App/PCCompanionView.swift';let s=fs.readFileSync(p,'utf8');
if(!s.includes('pc.fixture.counters')){
 const a='            snapshot = Self.offlineSnapshot; status = "本地快照 · 尚未连接 PC"; restored = true; return';
 assert.equal(s.split(a).length-1,1);
 s=s.replace(a,'            pairingKey = String(repeating: "T", count: 43)\n'+a);
 const b='                if let snapshot = model.snapshot {\n                    ScrollViewReader';
 assert.equal(s.split(b).length-1,1);
 s=s.replace(b,`                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--pc-companion-network-fixture") {
                    Text(PCCompanionTestProtocol.counters).font(.caption2).accessibilityIdentifier("pc.fixture.counters")
                }
                #endif
`+b);
 fs.writeFileSync(p,s);
}
console.log('Debug-only companion UI fixture counters ready; no real pairing or PC requests');
