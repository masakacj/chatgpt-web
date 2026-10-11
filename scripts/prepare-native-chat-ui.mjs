import fs from 'node:fs';
import assert from 'node:assert/strict';
const path='App/PCCompanionView.swift';let s=fs.readFileSync(path,'utf8');
const one=(a,b)=>{assert.equal(s.split(a).length-1,1,'unique reader integration '+a.slice(0,100));s=s.replace(a,b)};
if(!s.includes('func performInteraction(')){
 one('    let canSend: Bool; let composing: Bool; let unsupportedTools: Bool; let historyPartial: Bool',`    let canSend: Bool; let composing: Bool; let unsupportedTools: Bool; let historyPartial: Bool
    var responsePhase: String? = nil
    var interactions: [PCInteractionCard]? = nil
    var historyCursor: String? = nil
    var hasOlder: Bool? = nil`);
 one('    @Published var libraryLoading = false',`    @Published var libraryLoading = false
    @Published var olderMessages: [PCRemoteMessage] = []
    @Published var historyLoading = false
    @Published var historyReachedStart = false
    @Published var historyCursor: String?
    @Published private var pendingInteraction: PCInteractionPending?
    private var historyDocument: String?
    var hasPendingInteraction: Bool { pendingInteraction != nil }
    var displayMessages: [PCRemoteMessage] {
        let recent = snapshot?.messages ?? []
        let ids = Set(recent.map(\\.id))
        return olderMessages.filter { !ids.contains($0.id) } + recent
    }
    var isThinking: Bool {
        guard online, let snapshot, (snapshot.interactions ?? []).isEmpty else { return false }
        return snapshot.responsePhase == "thinking" || (snapshot.responsePhase == nil && snapshot.status == "running" && snapshot.messages.last?.role != "assistant")
    }
    var canLoadHistory: Bool {
        !historyReachedStart && (historyCursor ?? snapshot?.historyCursor) != nil && olderMessages.count < 300
    }`);
 one('online && !working && !reconnecting && !hasPending && snapshot != nil','online && !working && !reconnecting && !hasPending && !hasPendingInteraction && snapshot != nil');
 one('        if let data = defaults.data(forKey: "PCCompanion.lastTab") { selected = try? JSONDecoder().decode(PCRemoteTab.self, from: data) }',`        if let data = defaults.data(forKey: "PCCompanion.lastTab") { selected = try? JSONDecoder().decode(PCRemoteTab.self, from: data) }
        if let data = read("history.json"), let history = try? JSONDecoder().decode(PCSavedHistory.self, from: data), history.conversation == snapshot?.conversationId, history.document == snapshot?.documentId {
            olderMessages = Array(history.messages.prefix(300)); historyCursor = history.cursor; historyReachedStart = !history.hasMore; historyDocument = history.document
        }
        if let data = read("interaction.json") { pendingInteraction = try? JSONDecoder().decode(PCInteractionPending.self, from: data) }`);
 one('        snapshot = fresh; capturedAt = value.capturedAt',`        if historyDocument != fresh.documentId || snapshot?.conversationId != fresh.conversationId {
            olderMessages = []; historyCursor = nil; historyReachedStart = fresh.hasOlder == false; historyDocument = fresh.documentId
        }
        snapshot = fresh; capturedAt = value.capturedAt`);
 one('    func loadLibrary() async {',`    func loadHistory() async {
        guard online, !historyLoading, let c = connection, let id = sessionID, let snap = snapshot,
              let cursor = historyCursor ?? snap.historyCursor, !historyReachedStart else { return }
        historyLoading = true; defer { historyLoading = false }
        let epoch = generation
        do {
            var components = URLComponents(); components.queryItems = [URLQueryItem(name: "before", value: cursor), URLQueryItem(name: "documentId", value: snap.documentId)]
            let page: PCHistoryPage = try await request("/v1/sessions/\\(id)/history?\\(components.percentEncodedQuery ?? \"\")", using: c)
            try current(epoch)
            guard page.schema == 1, page.documentId == snap.documentId, page.conversationId == snap.conversationId,
                  page.messages.count <= 24, Set(page.messages.map(\\.id)).count == page.messages.count else { throw PCCompanionError(code: "schema_invalid", status: 409) }
            let known = Set(displayMessages.map(\\.id))
            olderMessages = Array((page.messages.filter { !known.contains($0.id) } + olderMessages).suffix(300))
            historyCursor = page.cursor; historyReachedStart = !page.hasMore || page.cursor == cursor
            write(PCSavedHistory(conversation: snap.conversationId, document: snap.documentId, messages: olderMessages, cursor: page.cursor, hasMore: !historyReachedStart), to: "history.json")
        } catch { self.error = error.localizedDescription }
    }
    func performInteraction(_ selection: PCInteractionSelection) async {
        guard online, !working, !hasPending, !hasPendingInteraction, let c = connection, let id = sessionID, let snap = snapshot,
              snap.documentId == selection.document,
              (snap.interactions ?? []).flatMap({ $0.buttons }).contains(where: { $0.id == selection.button.id && $0.revision == selection.button.revision && !$0.disabled }) else { error = "操作已变化，请查看当前对话。"; return }
        working = true; defer { working = false }
        let command = PCInteractionPending(id: UUID().uuidString, server: c.identity, conversation: snap.conversationId)
        pendingInteraction = command
        guard write(command, to: "interaction.json") else { pendingInteraction = nil; return }
        do {
            let receipt: PCReceipt = try await request("/v1/sessions/\\(id)/commands", using: c, method: "POST", body: [
                "commandId": command.id, "action": "interact", "documentId": snap.documentId,
                "interactionId": selection.button.id, "interactionRevision": selection.button.revision, "confirmed": true])
            resolveInteraction(receipt, using: c)
        } catch { self.error = "操作结果待确认，请核对回执；不会自动重复点击。" }
    }
    private func resolveInteraction(_ receipt: PCReceipt, using c: PCConnection) {
        guard let pendingInteraction, pendingInteraction.id == receipt.commandId, pendingInteraction.server == c.identity else { return }
        if receipt.state == "done", receipt.result?.status == "interaction_clicked" {
            self.pendingInteraction = nil; error = nil; status = "已点击，等待 PC 继续"
        } else if receipt.state == "failed" {
            self.pendingInteraction = nil; error = "操作已变化或不可用，没有点击。请查看当前对话。"
        } else { error = "操作回执仍待确认，不会重复点击。" }
        if self.pendingInteraction == nil { write([String: String](), to: "interaction.json") }
    }
    func checkInteractionReceipt() async {
        guard !working, let pendingInteraction else { return }
        working = true; defer { working = false }
        do {
            let c = try config(); guard c.identity == pendingInteraction.server else { throw PCCompanionError(code: "connection_changed", status: 409) }
            let receipt: PCReceipt = try await request("/v1/commands/\\(pendingInteraction.id)", using: c)
            resolveInteraction(receipt, using: c)
        } catch { self.error = error.localizedDescription }
    }
    func loadLibrary() async {`);
 one('    func connect(_ tab: PCRemoteTab) async {\n        guard !working else { return }','    func connect(_ tab: PCRemoteTab) async {\n        guard !working, !hasPendingInteraction else { return }');
 one('    func openConversation(_ item: PCSidebarChat) async {\n        guard !working, !libraryLoading else { return }','    func openConversation(_ item: PCSidebarChat) async {\n        guard !working, !libraryLoading, !hasPendingInteraction else { return }');
 const start=s.indexOf('struct PCCompanionView: View {');
 const config=s.indexOf('    private var configuration: some View {',start);
 assert.ok(start>0&&config>start);
 s=s.slice(0,start)+`struct PCCompanionView: View {
    @StateObject private var model = PCCompanionModel()
    @State private var settings = false
    @Environment(\\.scenePhase) private var scenePhase
    let returnToWeb: () -> Void
    var body: some View {
        NativeConversationScreen(model: model, openSettings: { settings = true }, returnToWeb: returnToWeb)
            .sheet(isPresented: $settings) { configuration }
            .task { await model.resume(); if model.pairingKey.isEmpty { settings = true } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.resume() } } else if phase == .background { model.pause() } }
            .onDisappear { model.pause() }
    }
`+s.slice(config);
 fs.writeFileSync(path,s);
}
for(const p of ['package.json','project.yml','safari/chatgpt-safari.user.js']){
 const old=fs.readFileSync(p,'utf8');fs.writeFileSync(p,old.replaceAll('0.5.1','0.6.0'));
}
console.log('Native chat0.6.0: optional protocol fields, bounded history, once-only interaction and new screen');
