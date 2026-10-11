import fs from 'node:fs';
import assert from 'node:assert/strict';
const change=(p,fn)=>{const old=fs.readFileSync(p,'utf8');const next=fn(old);if(next!==old)fs.writeFileSync(p,next)};
const one=(s,a,b)=>{assert.equal(s.split(a).length-1,1,'unique patch '+a.slice(0,80));return s.replace(a,b)};
change('App/PCCompanionView.swift',s=>{
 if(s.includes('func loadLibrary() async'))return s;
 s=one(s,'    @Published var tabs: [PCRemoteTab] = []','    @Published var tabs: [PCRemoteTab] = []\n    @Published var library: PCSidebarLibrary?\n    @Published var libraryLoading = false');
 s=one(s,'snapshot?.status != "running" && snapshot?.status != "waiting" && snapshot?.composing != true','snapshot?.status != "running" && snapshot?.status != "waiting" && snapshot?.status != "loading" && snapshot?.composing != true');
 s=one(s,'    func loadTabs() async {',`    func loadLibrary() async {
        guard !libraryLoading, !working else { return }
        libraryLoading = true; defer { libraryLoading = false }
        do {
            let c = try config()
            if let active = connection, active.identity != c.identity { throw PCCompanionError(code: "connection_changed", status: 409) }
            let path = selected.map { "/v1/library?tabId=\\($0.tabId)" } ?? "/v1/library"
            let value: PCSidebarLibrary = try await request(path, using: c)
            guard value.projects.count <= 150, value.chats.count <= 600 else { throw PCCompanionError(code: "schema_invalid", status: 409) }
            library = value; tabs = value.tabs
        } catch { self.error = error.localizedDescription }
    }
    func expandProject(_ id: String, more: Bool) async {
        guard !libraryLoading, !working, let source = library?.sourceTabId else { return }
        libraryLoading = true; defer { libraryLoading = false }
        do {
            let c = try config()
            let value: PCSidebarLibrary = try await request("/v1/library/actions", using: c, method: "POST", body: [
                "commandId": UUID().uuidString, "action": "project", "tabId": source, "projectId": id, "more": more])
            library = value; tabs = value.tabs
        } catch { self.error = error.localizedDescription }
    }
    func openConversation(_ item: PCSidebarChat) async {
        guard !working, !libraryLoading else { return }
        guard !hasPending else { error = "请先核对发送回执，再切换会话。"; return }
        guard draft.canSelect(item.id) else { error = PCCompanionError(code: "other_draft", status: 409).localizedDescription; return }
        if let tab = tabs.first(where: { $0.conversationId == item.id }) { await connect(tab); return }
        guard let source = library?.sourceTabId else { return }
        working = true; error = nil
        do {
            let c = try config()
            await disconnect(clearSelection: false)
            let epoch = generation
            let opened: PCSidebarOpened = try await request("/v1/library/actions", using: c, method: "POST", body: [
                "commandId": UUID().uuidString, "action": "open", "tabId": source, "conversationId": item.id])
            try current(epoch)
            guard opened.ok, opened.tab.conversationId == item.id else { throw PCCompanionError(code: "pc_route_changed", status: 409) }
            working = false
            await connect(opened.tab)
        } catch { working = false; self.error = error.localizedDescription }
    }
    func loadTabs() async {`);
 s=one(s,'            pending = nil; error = receipt.result?.error ?? "发送未执行"; status = "请核对 PC 后再操作"',`            pending = nil
            defaults.removeObject(forKey: "PCCompanion.pendingSend")
            error = PCCompanionError(code: receipt.result?.error ?? "not_sent", status: 409).localizedDescription
            status = "确定未发送 · 草稿已保留"`);
 s=one(s,'    @State private var settings = false','    @State private var settings = false\n    @State private var sidebar = false');
 s=one(s,'                 ToolbarItem(placement: .topBarTrailing) { Button("连接") { settings = true } }',`                 ToolbarItem(placement: .topBarTrailing) { Button("对话") { sidebar = true }.accessibilityIdentifier("pc.remote.sidebar") }
                 ToolbarItem(placement: .topBarTrailing) { Button("连接") { settings = true } }`);
 s=one(s,'             .sheet(isPresented: $settings) { configuration }','             .sheet(isPresented: $settings) { configuration }\n             .sheet(isPresented: $sidebar) { PCSidebarView(model: model) }');
 return s;
});
change('App/PCCompanionPolicy.swift',s=>{
 if(s.includes('"send_unavailable":'))return s;
 return one(s,'            "draft_conflict":',`            "not_sent": "消息没有发送，草稿仍保留在两端。",
            "send_unavailable": "PC 发送按钮尚未可用，本次未发送；草稿已保留。请确认页面加载完成后再操作。",
            "draft_or_state_changed": "PC 输入或生成状态已变化，本次未发送。",
            "pc_draft_blocks_navigation": "PC 输入框还有未发送文字，已阻止切换；请先处理该草稿。",
            "pc_approval_blocks_navigation": "PC 当前有待确认的工具操作，请先处理后再切换。",
            "sidebar_refresh_required": "列表已过期，请刷新项目与对话列表。",
            "sidebar_unavailable": "PC 侧栏尚未显示，请展开后刷新。",
            "conversation_not_visible": "对话不在当前已加载列表中，请刷新或展开项目。",
            "project_not_visible": "项目不在当前 PC 侧栏中，请刷新列表。",
            "navigation_not_confirmed": "尚未确认 PC 已完成切换，请刷新列表后核对。",
            "conversation_loading": "PC 正在加载对话，本次未发送。",
            "draft_conflict":`);
});
for(const p of ['package.json','project.yml','safari/chatgpt-safari.user.js'])change(p,s=>s.replaceAll('0.5.0','0.5.1'));
console.log('Integrated native 0.5.1 sidebar and precise not-sent receipt; reader unchanged');
