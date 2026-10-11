import fs from 'node:fs';
import assert from 'node:assert/strict';
const path='App/PCCompanionView.swift';let s=fs.readFileSync(path,'utf8');
const one=(a,b)=>{assert.equal(s.split(a).length-1,1,'unique patch '+a.slice(0,80));s=s.replace(a,b)};
if(!s.includes('private var draftOwner:')){
 one('    private var baseDraftHash: String?',`    private var baseDraftHash: String? = UserDefaults.standard.string(forKey:"PCCompanion.draftBase")
    private var draftOwner: String? = UserDefaults.standard.string(forKey:"PCCompanion.draftOwner")`);
 one('    func connect(_ tab:PCRemoteTab) async {\n        guard !working else{return};await disconnect();working=true;defer{working=false};error=nil',`    func connect(_ tab:PCRemoteTab) async {
        guard !working else{return}
        if localDirty, !text.isEmpty, let draftOwner, draftOwner != tab.conversationId {
            error="另一会话还有本地草稿，请先保存或清空；不会将它写入当前会话";return
        }
        await disconnect();working=true;defer{working=false};error=nil`);
 one('        text=value;localDirty=true\n        UserDefaults.standard.set(value,forKey:"PCCompanion.localDraft")',`        text=value;localDirty=true
        if let id=snapshot?.conversationId {draftOwner=id}
        UserDefaults.standard.set(draftOwner,forKey:"PCCompanion.draftOwner")
        UserDefaults.standard.set(baseDraftHash,forKey:"PCCompanion.draftBase")
        UserDefaults.standard.set(value,forKey:"PCCompanion.localDraft")`);
 one('        baseDraftHash=hash\n        if text==value {localDirty=false}',`        baseDraftHash=hash
        UserDefaults.standard.set(hash,forKey:"PCCompanion.draftBase")
        if text==value {localDirty=false}`);
 one('            text="";localDirty=false;baseDraftHash=nil',`            text="";localDirty=false;baseDraftHash=nil;draftOwner=nil
            UserDefaults.standard.removeObject(forKey:"PCCompanion.draftBase")
            UserDefaults.standard.removeObject(forKey:"PCCompanion.draftOwner")`);
 one('.disabled(!model.online||model.working||model.pendingSend != nil||model.text.isEmpty||model.snapshot?.canSend==false)',`.disabled(!model.online||model.working||model.pendingSend != nil||model.text.isEmpty||model.snapshot==nil||model.snapshot?.status=="running"||model.snapshot?.status=="waiting")`);
}
if(!s.includes('fixtureEnabled')){
 one('    init() {\n        if let u=cacheURL',`    init() {
        let fixtureEnabled=ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--pc-companion-fixture")
        if fixtureEnabled {
            snapshot=PCRemoteSnapshot(schema:1,documentId:"fixture",conversationId:"11111111-1111-4111-8111-111111111111",title:"PC 原生同步验收",messages:[PCRemoteMessage(id:"m1",role:"assistant",text:"已从 PC 同步的最新答案。手机原生界面无需加载完整网页。",blocks:[PCRemoteBlock(kind:"text",text:"已从 PC 同步的最新答案。")],links:[],truncated:false)],status:"completed",draft:"",draftHash:"fixture",canSend:false,composing:false,unsupportedTools:true,historyPartial:true)
            status="本地快照 · 尚未连接 PC";return
        }
        if let u=cacheURL`);
 one('    @State private var settings=true','    @State private var settings = !ProcessInfo.processInfo.arguments.contains("--pc-companion-fixture")');
}
fs.writeFileSync(path,s);
const root='App/PCCompanionRootView.swift';let r=fs.readFileSync(root,'utf8');
if(!r.includes('let fixture ='))r=r.replace('            if remote {','            let fixture = ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--pc-companion-fixture")\n            if remote || fixture {');
fs.writeFileSync(root,r);
console.log('PC companion draft ownership, send gating and isolated offline fixture aligned');
