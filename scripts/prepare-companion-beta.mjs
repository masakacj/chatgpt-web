import fs from 'node:fs';
import assert from 'node:assert/strict';
const change=(p,fn)=>{const s=fs.readFileSync(p,'utf8');const n=fn(s);if(s!==n)fs.writeFileSync(p,n)};
const one=(s,a,b)=>{assert.equal(s.split(a).length-1,1,'unique native patch: '+a.slice(0,90));return s.replace(a,b)};
change('App/PCCompanionView.swift',s=>{
 if(!s.includes('// companion-beta-safe-storage')){
 s=one(s,'    private var foreground = true','    private var foreground = true\n    private var writing = false // companion-beta-safe-storage');
 s=one(s,`        #if DEBUG
        fixture = args.contains("--ui-testing") && args.contains("--pc-companion-fixture")
        networkFixture = args.contains("--ui-testing") && args.contains("--pc-companion-network-fixture")
        #endif
        defaults = fixture || networkFixture ? UserDefaults(suiteName: "PCCompanion.UITests")! : .standard`,
 `        #if DEBUG
        let offlineTest = args.contains("--ui-testing") && args.contains("--pc-companion-fixture")
        let networkTest = args.contains("--ui-testing") && args.contains("--pc-companion-network-fixture")
        #else
        let offlineTest = false; let networkTest = false
        #endif
        defaults = offlineTest || networkTest ? UserDefaults(suiteName: "PCCompanion.UITests")! : .standard
        fixture = offlineTest; networkFixture = networkTest`);
 s=one(s,'    private func write<T: Encodable>(_ value: T, to file: String) {\n        guard let folder, let data = try? JSONEncoder().encode(value) else { return }',
 '    @discardableResult\n    private func write<T: Encodable>(_ value: T, to file: String) -> Bool {\n        guard let folder, let data = try? JSONEncoder().encode(value) else { return false }');
 s=one(s,'            try data.write(to: folder.appendingPathComponent(file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])\n        } catch { self.error = "本地保存失败，请保留当前草稿后重试。" }',
 '            try data.write(to: folder.appendingPathComponent(file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])\n            return true\n        } catch { self.error = "本地保存失败，请保留当前草稿后重试。"; return false }');
 s=one(s,'    private func saveDraft() { write(PCSavedDraft(draft: draft, pending: pending), to: "draft.json") }',
 '    @discardableResult\n    private func saveDraft() -> Bool { write(PCSavedDraft(draft: draft, pending: pending), to: "draft.json") }');
 s=one(s,'blocked: working || hasPending','blocked: writing || hasPending');
 s=one(s,'        guard canWrite, let c = connection else { return }; working = true; defer { working = false }; error = nil',
 '        guard canWrite, let c = connection else { return }; working = true; writing = true; defer { working = false; writing = false }; error = nil');
 s=one(s,'        working = true; defer { working = false }; error = nil; let epoch = generation',
 '        working = true; writing = true; defer { working = false; writing = false }; error = nil; let epoch = generation');
 s=one(s,'            pending = command; saveDraft() // Persist before the single Send request.',
 `            pending = command
            guard saveDraft() else {
                pending = nil
                throw PCCompanionError(code: "local_receipt_storage_failed", status: 0)
            } // Never send if the durable local reservation could not be saved.`);
 s=one(s,'guard !working, !reconnecting, !online, !fixture, !networkFixture || selected != nil else { return }',
 'guard !working, !reconnecting, !online, !fixture, (!networkFixture || selected != nil) else { return }');
 }
 if(!s.includes('// Keep command errors')){
 s=one(s,'try current(epoch); try apply(value); online = true; reconnecting = false; failures = 0; error = nil',
 'try current(epoch); try apply(value); online = true; reconnecting = false; failures = 0\n                // Keep command errors visible: successful reading does not resolve a draft conflict.');
 s=one(s,'        guard draft.canSelect(tab.conversationId) else',
 `        if let pending, pending.conversation != tab.conversationId {
            error = "请先核对当前消息的发送回执，再切换会话。"; return
        }
        if draft.text.isEmpty && draft.owner != tab.conversationId {
            draft = PCDraftBuffer(); saveDraft()
        }
        guard draft.canSelect(tab.conversationId) else`);
 s=one(s,'            draft.sent(text: command.text, editedAt: command.revision); pending = nil',
 '            draft.sent(text: command.text, editedAt: command.revision); pending = nil; error = nil');
 }
 return s;
});
change('App/PCCompanionPolicy.swift',s=>{
 if(!s.includes('// First pairing'))s=one(s,'        guard !localEdits else { return }\n        text = remote; baseHash = hash; owner = conversation',
 `        // First pairing may keep locally typed text only against a confirmed
        // empty PC editor; a preexisting PC draft must not be silently replaced.
        if localEdits && owner == nil && baseHash == nil && remote.isEmpty {
            owner = conversation; baseHash = hash
        }
        guard !localEdits else { return }
        text = remote; baseHash = hash; owner = conversation`);
 return s.replace('!hasLocalDraft || owner == nil || owner == conversation','text.isEmpty || owner == nil || owner == conversation');
});
change('App/PCCompanionRootView.swift',s=>{
 if(s.includes('--pc-companion-network-fixture'))return s;
 return one(s,'ProcessInfo.processInfo.arguments.contains("--pc-companion-fixture")',
 '(ProcessInfo.processInfo.arguments.contains("--pc-companion-fixture") || ProcessInfo.processInfo.arguments.contains("--pc-companion-network-fixture"))');
});
for(const p of ['package.json','project.yml','safari/chatgpt-safari.user.js'])change(p,s=>{
 if(p==='package.json')return s.replace('"version": "0.4.44"','"version": "0.5.0"');
 if(p==='project.yml')return s.replaceAll('MARKETING_VERSION: 0.4.44','MARKETING_VERSION: 0.5.0');
 return s.replace('// @version      0.4.44','// @version      0.5.0').replace("  const VERSION = '0.4.44';","  const VERSION = '0.5.0';");
});
console.log('Companion beta 0.5.0: native draft protection, current root, version alignment');
