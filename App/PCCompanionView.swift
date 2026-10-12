import SwiftUI
import Security
import CryptoKit

// Optional semantic fields keep older 0.7.0 messages decodable. Every field
// comes from elements already rendered in the bound PC ChatGPT page.
struct PCRemoteBlock: Codable {
    let kind: String
    let text: String
    var rows: [[String]]? = nil
    var url: String? = nil
}
struct PCRemoteLink: Codable {
    let title: String
    let url: String
    // Server-generated, document-scoped reference to a visible PC anchor.
    // Older peers omit these fields and remain decodable (PC-only fallback).
    var interactionId: String? = nil
    var interactionRevision: String? = nil
}
struct PCRemoteMessage: Codable, Identifiable {
    let id: String; let role: String; let text: String
    let blocks: [PCRemoteBlock]; let links: [PCRemoteLink]; let truncated: Bool
}
struct PCRemoteSnapshot: Codable {
    let schema: Int; let documentId: String; let conversationId: String; let title: String
    let messages: [PCRemoteMessage]; let status: String; let draft: String; let draftHash: String
    let canSend: Bool; let composing: Bool; let unsupportedTools: Bool; let historyPartial: Bool
    var responsePhase: String? = nil
    var interactions: [PCInteractionCard]? = nil
    var historyCursor: String? = nil
    var hasOlder: Bool? = nil
}
struct PCRemoteTab: Codable, Identifiable {
    let tabId: Int; let title: String; let conversationId: String; let active: Bool
    var id: Int { tabId }
}
struct PCRemoteEnvelope: Codable {
    let ok: Bool; let sessionId: String; let revision: Int; let capturedAt: Double
    let routeChanged: Bool; let snapshot: PCRemoteSnapshot?
}
private struct PCTabs: Decodable { let tabs: [PCRemoteTab] }
private struct PCOK: Decodable { let ok: Bool }
private struct PCResult: Codable { let status: String?; let draftHash: String?; let documentId: String?; let error: String? }
private struct PCReceipt: Decodable { let ok: Bool; let commandId: String; let state: String; let result: PCResult? }
private struct PCFailure: Decodable { let error: String }
private struct PCSavedView: Codable { let snapshot: PCRemoteSnapshot; let capturedAt: Double; var server: String? }
private struct PCPending: Codable {
    let id: String; let text: String; let revision: Int; let conversation: String; let server: String
}
private struct PCSavedDraft: Codable { var draft: PCDraftBuffer; var pending: PCPending? }
private struct PCConnection {
    let origin: URL; let token: String
    var identity: String { PCCompanionPolicy.hash(origin.absoluteString + "|" + token) }
}

private enum PCPairingKeychain {
    static let service = "ChatGPTWeb.PCCompanion.v1"
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service, kSecAttrAccount as String: "pairing"]
    static func load() -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let data = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(query as CFDictionary, data as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = Data(token.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw PCCompanionError(code: "keychain_unavailable", status: 0) }
    }
}
private final class PCNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class PCCompanionModel: ObservableObject {
    @Published var endpoint = UserDefaults.standard.string(forKey: "PCCompanion.endpoint") ?? PCCompanionPolicy.defaultEndpoint
    @Published var pairingKey = PCPairingKeychain.load()
    @Published var tabs: [PCRemoteTab] = []
    @Published var library: PCSidebarLibrary?
    @Published var libraryLoading = false
    @Published var olderMessages: [PCRemoteMessage] = []
    @Published var historyLoading = false
    @Published var historyReachedStart = false
    @Published var historyCursor: String?
    @Published private var pendingInteraction: PCInteractionPending?
    private var historyDocument: String?
    var hasPendingInteraction: Bool { pendingInteraction != nil }
    var displayMessages: [PCRemoteMessage] {
        let recent = snapshot?.messages ?? []
        let ids = Set(recent.map(\.id))
        return olderMessages.filter { !ids.contains($0.id) } + recent
    }
    var isThinking: Bool {
        guard online, let snapshot, (snapshot.interactions ?? []).isEmpty else { return false }
        return snapshot.responsePhase == "thinking" || (snapshot.responsePhase == nil && snapshot.status == "running" && snapshot.messages.last?.role != "assistant")
    }
    var canLoadHistory: Bool {
        !historyReachedStart && (historyCursor ?? snapshot?.historyCursor) != nil && olderMessages.count < 300
    }
    @Published var snapshot: PCRemoteSnapshot?
    @Published var draft = PCDraftBuffer()
    @Published var status = "未连接 PC"
    @Published var online = false
    @Published var working = false
    @Published var error: String?
    @Published var capturedAt: Double = 0
    @Published private var pending: PCPending?
    @Published var reconnecting = false
    @Published var restored = false
    private var connection: PCConnection?
    private var selected: PCRemoteTab?
    private var sessionID: String?
    private var revision = -1
    private var generation = 0
    private var foreground = true
    private var writing = false // companion-beta-safe-storage
    private var pollTask: Task<Void, Never>?
    private var cacheTask: Task<Void, Never>?
    private let redirect = PCNoRedirect()
    private let defaults: UserDefaults
    private var fixture = false
    private var networkFixture = false
    private lazy var transport: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30; c.timeoutIntervalForResource = 35
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpShouldSetCookies = false; c.httpCookieStorage = nil; c.urlCache = nil
        c.waitsForConnectivity = false // No queued offline Send on network return.
        #if DEBUG
        if networkFixture { c.protocolClasses = [PCCompanionTestProtocol.self] }
        #endif
        return URLSession(configuration: c, delegate: redirect, delegateQueue: nil)
    }()
    var hasPending: Bool { pending != nil }
    var canWrite: Bool {
        online && !working && !reconnecting && !hasPending && !hasPendingInteraction && snapshot != nil &&
        snapshot?.status != "running" && snapshot?.status != "waiting" && snapshot?.status != "loading" && snapshot?.composing != true
    }
    var connectionChanged: Bool {
        guard let connection else { return false }
        return (try? PCCompanionPolicy.origin(endpoint)) != connection.origin || pairingKey != connection.token
    }
    private var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fixture || networkFixture ? "PCCompanionTest" : "PCCompanion", isDirectory: true)
    }
    init() {
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        let offlineTest = args.contains("--ui-testing") && args.contains("--pc-companion-fixture")
        let networkTest = args.contains("--ui-testing") && args.contains("--pc-companion-network-fixture")
        #else
        let offlineTest = false; let networkTest = false
        #endif
        defaults = offlineTest || networkTest ? UserDefaults(suiteName: "PCCompanion.UITests")! : .standard
        fixture = offlineTest; networkFixture = networkTest
        if fixture {
            pairingKey = String(repeating: "T", count: 43)
            snapshot = Self.offlineSnapshot; status = "本地快照 · 尚未连接 PC"; restored = true; return
        }
        if networkFixture {
            #if DEBUG
            PCCompanionTestProtocol.reset()
            #endif
            endpoint = "https://pc-companion.invalid"; pairingKey = String(repeating: "T", count: 43)
            restored = true; return
        }
        if let data = read("latest.json"), let view = try? JSONDecoder().decode(PCSavedView.self, from: data) {
            snapshot = view.snapshot; capturedAt = view.capturedAt; status = "本地快照 · 尚未连接 PC"
        }
        if let data = read("draft.json"), let saved = try? JSONDecoder().decode(PCSavedDraft.self, from: data) {
            draft = saved.draft; pending = saved.pending
        } else {
            draft.text = defaults.string(forKey: "PCCompanion.localDraft") ?? ""
            draft.owner = defaults.string(forKey: "PCCompanion.draftOwner") ?? snapshot?.conversationId
            draft.baseHash = defaults.string(forKey: "PCCompanion.draftBase")
            draft.localEdits = !draft.text.isEmpty
            // Legacy uncertain sends remain queryable; do not clear them.
            if let id = defaults.string(forKey: "PCCompanion.pendingSend"), PCCompanionPolicy.validReceipt(id),
               let origin = try? PCCompanionPolicy.origin(endpoint) {
                pending = PCPending(id: id, text: draft.text, revision: draft.revision,
                    conversation: draft.owner ?? "", server: PCConnection(origin: origin, token: pairingKey).identity)
            }
        }
        if let data = defaults.data(forKey: "PCCompanion.lastTab") { selected = try? JSONDecoder().decode(PCRemoteTab.self, from: data) }
        if let data = read("history.json"), let history = try? JSONDecoder().decode(PCSavedHistory.self, from: data), history.conversation == snapshot?.conversationId, history.document == snapshot?.documentId {
            olderMessages = Array(history.messages.prefix(300)); historyCursor = history.cursor; historyReachedStart = !history.hasMore; historyDocument = history.document
        }
        if let data = read("interaction.json") { pendingInteraction = try? JSONDecoder().decode(PCInteractionPending.self, from: data) }
    }
    deinit { pollTask?.cancel(); cacheTask?.cancel() }
    static var offlineSnapshot: PCRemoteSnapshot {
        PCRemoteSnapshot(schema: 1, documentId: "fixture", conversationId: "11111111-1111-4111-8111-111111111111",
            title: "PC 原生同步验收", messages: [PCRemoteMessage(id: "m1", role: "assistant",
            text: "已从 PC 同步的最新答案。手机原生界面无需加载完整网页。", blocks: [], links: [], truncated: false)],
            status: "completed", draft: "", draftHash: PCCompanionPolicy.hash(""), canSend: false,
            composing: false, unsupportedTools: true, historyPartial: true)
    }
    private func read(_ file: String) -> Data? { folder.flatMap { try? Data(contentsOf: $0.appendingPathComponent(file)) } }
    @discardableResult
    private func write<T: Encodable>(_ value: T, to file: String) -> Bool {
        guard let folder, let data = try? JSONEncoder().encode(value) else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var dir = folder; var attr = URLResourceValues(); attr.isExcludedFromBackup = true
            try dir.setResourceValues(attr)
            try data.write(to: folder.appendingPathComponent(file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { self.error = "本地保存失败，请保留当前草稿后重试。"; return false }
    }
    @discardableResult
    private func saveDraft() -> Bool { write(PCSavedDraft(draft: draft, pending: pending), to: "draft.json") }
    private func config() throws -> PCConnection {
        guard pairingKey.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw PCCompanionError(code: "invalid_pairing", status: 400)
        }
        let c = PCConnection(origin: try PCCompanionPolicy.origin(endpoint), token: pairingKey)
        if let pending, pending.server != c.identity { throw PCCompanionError(code: "connection_changed", status: 409) }
        return c
    }
    private func request<T: Decodable>(_ path: String, using c: PCConnection, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard path.hasPrefix("/v1/"), !path.contains("\\"), let u = URL(string: path, relativeTo: c.origin)?.absoluteURL,
              u.host == c.origin.host, u.port == c.origin.port, u.scheme == "https" else { throw URLError(.badURL) }
        var req = URLRequest(url: u); req.httpMethod = method
        req.setValue("Bearer " + c.token, forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        // Each action has exactly one data task. Retry loops exist only around GET.
        let (data, response) = try await transport.data(for: req)
        guard data.count <= 800000, let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if (300...399).contains(http.statusCode) { throw PCCompanionError(code: "redirect_refused", status: http.statusCode) }
        guard (200...299).contains(http.statusCode) else {
            let raw = (try? JSONDecoder().decode(PCFailure.self, from: data))?.error ?? "http_\(http.statusCode)"
            let safe = raw.range(of: "^[a-z0-9_]{1,80}$", options: .regularExpression) != nil ? raw : "server_error"
            throw PCCompanionError(code: safe, status: http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func current(_ epoch: Int) throws {
        guard generation == epoch, foreground, !Task.isCancelled else { throw CancellationError() }
    }
    func loadHistory() async {
        guard online, !historyLoading, let c = connection, let id = sessionID, let snap = snapshot,
              let cursor = historyCursor ?? snap.historyCursor, !historyReachedStart else { return }
        historyLoading = true; defer { historyLoading = false }
        let epoch = generation
        do {
            var components = URLComponents(); components.queryItems = [URLQueryItem(name: "before", value: cursor), URLQueryItem(name: "documentId", value: snap.documentId)]
            let page: PCHistoryPage = try await request("/v1/sessions/\(id)/history?\(components.percentEncodedQuery ?? "")", using: c)
            try current(epoch)
            guard page.schema == 1, page.documentId == snap.documentId, page.conversationId == snap.conversationId,
                  page.messages.count <= 24, Set(page.messages.map(\.id)).count == page.messages.count else { throw PCCompanionError(code: "schema_invalid", status: 409) }
            let known = Set(displayMessages.map(\.id))
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
            let receipt: PCReceipt = try await request("/v1/sessions/\(id)/commands", using: c, method: "POST", body: [
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
            let receipt: PCReceipt = try await request("/v1/commands/\(pendingInteraction.id)", using: c)
            resolveInteraction(receipt, using: c)
        } catch { self.error = error.localizedDescription }
    }
    func loadLibrary() async {
        guard !libraryLoading, !working else { return }
        libraryLoading = true; defer { libraryLoading = false }
        do {
            let c = try config()
            if let active = connection, active.identity != c.identity { throw PCCompanionError(code: "connection_changed", status: 409) }
            let path = selected.map { "/v1/library?tabId=\($0.tabId)" } ?? "/v1/library"
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
        guard !working, !libraryLoading, !hasPendingInteraction else { return }
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
    func loadTabs() async {
        guard !working else { return }; working = true; defer { working = false }; error = nil
        do {
            let c = try config()
            if let old = connection, old.identity != c.identity { await disconnect(clearSelection: true) }
            let list: PCTabs = try await request("/v1/tabs", using: c)
            tabs = list.tabs
            if !networkFixture { try PCPairingKeychain.save(c.token); defaults.set(c.origin.absoluteString, forKey: "PCCompanion.endpoint") }
            connection = c; status = tabs.isEmpty ? "PC 没有已打开的对话" : "选择 PC 上的会话"
        } catch { self.error = error.localizedDescription }
    }
    func connect(_ tab: PCRemoteTab) async {
        guard !working, !hasPendingInteraction else { return }
        if let pending, pending.conversation != tab.conversationId {
            error = "请先核对当前消息的发送回执，再切换会话。"; return
        }
        if draft.text.isEmpty && draft.owner != tab.conversationId {
            draft = PCDraftBuffer(); saveDraft()
        }
        guard draft.canSelect(tab.conversationId) else { error = PCCompanionError(code: "other_draft", status: 409).localizedDescription; return }
        working = true; defer { working = false }; error = nil
        do {
            let c = try config()
            await disconnect(clearSelection: false)
            foreground = true; connection = c; selected = tab; let epoch = generation
            let value: PCRemoteEnvelope = try await request("/v1/sessions", using: c, method: "POST", body: ["tabId": tab.tabId])
            try current(epoch); sessionID = value.sessionId; revision = -1
            try apply(value); online = true
            if !networkFixture { defaults.set(try JSONEncoder().encode(tab), forKey: "PCCompanion.lastTab") }
            startPolling(epoch)
        } catch { online = false; self.error = error.localizedDescription }
    }
    private func apply(_ value: PCRemoteEnvelope) throws {
        guard value.ok, value.sessionId == sessionID else { throw PCCompanionError(code: "schema_invalid", status: 409) }
        guard !value.routeChanged else { throw PCCompanionError(code: "pc_route_changed", status: 409) }
        guard value.revision >= revision else { return }
        revision = value.revision
        guard let fresh = value.snapshot else { return }
        guard fresh.schema == 1, fresh.conversationId == selected?.conversationId, fresh.messages.count <= 24,
              Set(fresh.messages.map(\.id)).count == fresh.messages.count else { throw PCCompanionError(code: "schema_invalid", status: 409) }
        if historyDocument != fresh.documentId || snapshot?.conversationId != fresh.conversationId {
            olderMessages = []; historyCursor = nil; historyReachedStart = fresh.hasOlder == false; historyDocument = fresh.documentId
        }
        snapshot = fresh; capturedAt = value.capturedAt
        draft.receive(text: fresh.draft, hash: fresh.draftHash, conversation: fresh.conversationId, blocked: writing || hasPending)
        status = fresh.status == "running" ? "PC 生成中" : fresh.status == "waiting" ? "等待 PC 工具授权" : "已同步 PC"
        if cacheTask == nil {
            cacheTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let self, !Task.isCancelled else { return }
                self.persistSnapshot(); self.cacheTask = nil
            }
        }
    }
    private func persistSnapshot() {
        if let snapshot { write(PCSavedView(snapshot: snapshot, capturedAt: capturedAt, server: connection?.identity), to: "latest.json") }
        saveDraft()
    }
    private func startPolling(_ epoch: Int) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in await self?.poll(epoch) }
    }
    private func poll(_ epoch: Int) async {
        var failures = 0; var rejoined = false
        while !Task.isCancelled, generation == epoch, foreground, let id = sessionID, let c = connection {
            do {
                let value: PCRemoteEnvelope = try await request("/v1/sessions/\(id)?after=\(revision)", using: c)
                try current(epoch); try apply(value); online = true; reconnecting = false; failures = 0
                // Keep command errors visible: successful reading does not resolve a draft conflict.
            } catch {
                if Task.isCancelled || generation != epoch || !foreground { return }
                online = false
                if (error as? PCCompanionError)?.status == 410, !rejoined {
                    rejoined = true
                    do { try await rejoin(c, epoch: epoch); continue } catch { self.error = error.localizedDescription }
                }
                guard PCCompanionPolicy.retryableRead(error), failures < 4 else {
                    reconnecting = false; status = "连接中断 · 已保留本地内容"; self.error = error.localizedDescription; return
                }
                failures += 1; reconnecting = true; status = "正在重连 PC（\(failures)/4）"
                do { try await Task.sleep(nanoseconds: UInt64(1 << (failures - 1)) * 1_000_000_000) } catch { return }
            }
        }
    }
    private func rejoin(_ c: PCConnection, epoch: Int) async throws {
        guard let target = selected else { throw PCCompanionError(code: "pc_route_changed", status: 409) }
        let list: PCTabs = try await request("/v1/tabs", using: c); try current(epoch)
        guard let tab = list.tabs.first(where: { $0.conversationId == target.conversationId }) else { throw PCCompanionError(code: "pc_route_changed", status: 409) }
        selected = tab; tabs = list.tabs
        // Only resubscribe to the same previously selected chat; never navigate PC.
        let value: PCRemoteEnvelope = try await request("/v1/sessions", using: c, method: "POST", body: ["tabId": tab.tabId])
        try current(epoch); sessionID = value.sessionId; revision = -1; try apply(value); online = true; reconnecting = false
    }
    func edited(_ value: String) {
        draft.edit(String(value.prefix(16000)), conversation: snapshot?.conversationId, remoteHash: snapshot?.draftHash)
        saveDraft()
    }
    func usePCDraft() {
        guard !working, !hasPending, let snapshot else { return }
        draft = PCDraftBuffer(text: snapshot.draft, owner: snapshot.conversationId, baseHash: snapshot.draftHash)
        error = nil; saveDraft()
    }
    private func sync(_ c: PCConnection, epoch: Int) async throws -> (text: String, hash: String, edit: Int, document: String) {
        guard online, let id = sessionID, let snap = snapshot, draft.owner == nil || draft.owner == snap.conversationId,
              let hash = draft.baseHash ?? (draft.localEdits ? nil : snap.draftHash) else { throw PCCompanionError(code: "draft_conflict", status: 409) }
        let text = draft.text; let edit = draft.revision
        let receipt: PCReceipt = try await request("/v1/sessions/\(id)/commands", using: c, method: "POST", body: [
            "commandId": UUID().uuidString, "action": "draft", "documentId": snap.documentId, "baseDraftHash": hash, "text": text])
        try current(epoch)
        guard receipt.ok, receipt.result?.status == "draft_synced", let ack = receipt.result?.draftHash,
              receipt.result?.documentId == snap.documentId else { throw PCCompanionError(code: "pc_result_unknown", status: 409) }
        draft.acknowledged(text: text, hash: ack, editedAt: edit); saveDraft()
        return (text, ack, edit, snap.documentId)
    }
    func syncDraft() async {
        guard canWrite, let c = connection else { return }; working = true; writing = true; defer { working = false; writing = false }; error = nil
        do { _ = try await sync(c, epoch: generation); status = "草稿已同步，尚未发送" }
        catch { self.error = error.localizedDescription }
    }
    func send() async {
        guard canWrite, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let c = connection else { return }
        working = true; writing = true; defer { working = false; writing = false }; error = nil; let epoch = generation
        do {
            let value = try await sync(c, epoch: epoch); try current(epoch)
            guard draft.revision == value.edit, draft.text == value.text, let id = sessionID,
                  let snap = snapshot, snap.documentId == value.document else { throw PCCompanionError(code: "draft_conflict", status: 409) }
            let command = PCPending(id: UUID().uuidString, text: value.text, revision: value.edit, conversation: snap.conversationId, server: c.identity)
            pending = command
            guard saveDraft() else {
                pending = nil
                throw PCCompanionError(code: "local_receipt_storage_failed", status: 0)
            } // Never send if the durable local reservation could not be saved.
            let receipt: PCReceipt = try await request("/v1/sessions/\(id)/commands", using: c, method: "POST", body: [
                "commandId": command.id, "action": "send", "documentId": value.document, "baseDraftHash": value.hash, "text": value.text])
            resolve(receipt, using: c)
        } catch { self.error = error.localizedDescription; if hasPending { status = "发送结果待确认 · 不会自动重发" } }
    }
    private func resolve(_ receipt: PCReceipt, using c: PCConnection) {
        guard let command = pending, command.id == receipt.commandId, command.server == c.identity else { return }
        if receipt.state == "done", receipt.result?.status == "sent_confirmed" {
            draft.sent(text: command.text, editedAt: command.revision); pending = nil; error = nil
            defaults.removeObject(forKey: "PCCompanion.pendingSend"); status = "PC 网页已确认消息"
        } else if receipt.state == "failed" {
            pending = nil
            defaults.removeObject(forKey: "PCCompanion.pendingSend")
            error = PCCompanionError(code: receipt.result?.error ?? "not_sent", status: 409).localizedDescription
            status = "确定未发送 · 草稿已保留"
        } else { status = "发送结果仍待确认 · 不会再次发送" }
        saveDraft()
    }
    func checkReceipt() async {
        guard !working, let pending, PCCompanionPolicy.validReceipt(pending.id) else { return }
        working = true; defer { working = false }
        do {
            let c = try config(); guard c.identity == pending.server else { throw PCCompanionError(code: "connection_changed", status: 409) }
            let value: PCReceipt = try await request("/v1/commands/\(pending.id)", using: c); resolve(value, using: c)
        } catch { self.error = error.localizedDescription }
    }
    func acknowledgeManualCheck() {
        // User explicitly confirmed inspecting the PC; this clears UI blocking,
        // never replays the old command or erases its server-side reservation.
        pending = nil; defaults.removeObject(forKey: "PCCompanion.pendingSend"); saveDraft()
        status = "已记录手动核对 · 未发送任何内容"
    }
    func disconnect(clearSelection: Bool = false) async {
        generation &+= 1; pollTask?.cancel(); pollTask = nil; online = false; reconnecting = false
        let id = sessionID, c = connection; sessionID = nil; revision = -1
        if clearSelection { selected = nil; defaults.removeObject(forKey: "PCCompanion.lastTab") }
        if let id, let c { let _: PCOK? = try? await request("/v1/sessions/\(id)", using: c, method: "DELETE") }
        persistSnapshot(); status = snapshot == nil ? "未连接 PC" : "本地快照 · PC 未连接"
    }
    func pause() {
        foreground = false; generation &+= 1; pollTask?.cancel(); pollTask = nil
        online = false; reconnecting = false; persistSnapshot(); status = "已暂停连接 · 保留本地快照"
    }
    func resume() async {
        foreground = true
        guard !working, !reconnecting, !online, !fixture, (!networkFixture || selected != nil) else { return }
        guard selected != nil else { restored = true; return }
        working = true; reconnecting = true; defer { working = false; reconnecting = false; restored = true }
        error = nil; generation &+= 1; let epoch = generation
        do {
            let c = try config(); connection = c
            if let id = sessionID {
                do { let value: PCRemoteEnvelope = try await request("/v1/sessions/\(id)", using: c); try current(epoch); try apply(value); online = true }
                catch { guard (error as? PCCompanionError)?.status == 410 else { throw error }; try await rejoin(c, epoch: epoch) }
            } else { try await rejoin(c, epoch: epoch) }
            try current(epoch); startPolling(epoch)
        } catch { online = false; self.error = error.localizedDescription; status = "本地快照 · 点击重连 PC" }
    }
}

struct PCCompanionView: View {
    @StateObject private var model = PCCompanionModel()
    @State private var settings = false
    @Environment(\.scenePhase) private var scenePhase
    let returnToWeb: () -> Void
    var body: some View {
        NativeConversationScreen(model: model, openSettings: { settings = true }, returnToWeb: returnToWeb)
            .sheet(isPresented: $settings) { configuration }
            .task { await model.resume(); if model.pairingKey.isEmpty { settings = true } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.resume() } } else if phase == .background { model.pause() } }
            .onDisappear { model.pause() }
    }
    private var configuration: some View {
        NavigationStack {
            Form {
                Section("PC 配对") {
                    TextField("HTTPS 服务地址", text: $model.endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("配对密钥", text: $model.pairingKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { values in if let value = values.first { model.pairingKey = value.trimmingCharacters(in: .whitespacesAndNewlines) } }
                    Button("读取 PC 会话") { Task { await model.loadTabs() } }.disabled(model.working)
                    Text("专属地址已预填，保留 :58443。请在电脑打开 localhost:3210/mobile.html，显示并复制配对密钥；密钥仅保存在手机钥匙串，不发送至其他服务。").font(.caption)
                    if model.connectionChanged { Text("输入了新的连接信息，点击读取会话后才生效。").font(.caption).foregroundStyle(.orange) }
                }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
                Section("PC 已打开的对话") {
                    ForEach(model.tabs) { tab in Button(tab.title) { Task { await model.connect(tab); if model.online { settings = false } } }.disabled(model.working) }
                }
                Section {
                    Text("PC 必须保持在线。断线只重连读取，不重发消息；生成和工具授权仍在 PC 上运行。试用版暂不支持手机上传附件或控制复杂 MCP 界面。").font(.caption)
                    Button("断开 PC") { Task { await model.disconnect(clearSelection: true) } }.disabled(model.working)
                }
            }.navigationTitle("连接 PC").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { settings = false } } }
        }
    }
}
