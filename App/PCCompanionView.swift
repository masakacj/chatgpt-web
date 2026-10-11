import SwiftUI
import Security
import CryptoKit

struct PCRemoteBlock: Codable { let kind: String; let text: String }
struct PCRemoteLink: Codable { let title: String; let url: String }
struct PCRemoteMessage: Codable, Identifiable {
    let id: String; let role: String; let text: String
    let blocks: [PCRemoteBlock]; let links: [PCRemoteLink]; let truncated: Bool
}
struct PCRemoteSnapshot: Codable {
    let schema: Int; let documentId: String; let conversationId: String; let title: String
    let messages: [PCRemoteMessage]; let status: String; let draft: String; let draftHash: String
    let canSend: Bool; let composing: Bool; let unsupportedTools: Bool; let historyPartial: Bool
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
        online && !working && !reconnecting && !hasPending && snapshot != nil &&
        snapshot?.status != "running" && snapshot?.status != "waiting" && snapshot?.composing != true
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
        fixture = args.contains("--ui-testing") && args.contains("--pc-companion-fixture")
        networkFixture = args.contains("--ui-testing") && args.contains("--pc-companion-network-fixture")
        #endif
        defaults = fixture || networkFixture ? UserDefaults(suiteName: "PCCompanion.UITests")! : .standard
        if fixture {
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
    private func write<T: Encodable>(_ value: T, to file: String) {
        guard let folder, let data = try? JSONEncoder().encode(value) else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var dir = folder; var attr = URLResourceValues(); attr.isExcludedFromBackup = true
            try dir.setResourceValues(attr)
            try data.write(to: folder.appendingPathComponent(file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { self.error = "本地保存失败，请保留当前草稿后重试。" }
    }
    private func saveDraft() { write(PCSavedDraft(draft: draft, pending: pending), to: "draft.json") }
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
        guard !working else { return }
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
        snapshot = fresh; capturedAt = value.capturedAt
        draft.receive(text: fresh.draft, hash: fresh.draftHash, conversation: fresh.conversationId, blocked: working || hasPending)
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
                try current(epoch); try apply(value); online = true; reconnecting = false; failures = 0; error = nil
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
        guard canWrite, let c = connection else { return }; working = true; defer { working = false }; error = nil
        do { _ = try await sync(c, epoch: generation); status = "草稿已同步，尚未发送" }
        catch { self.error = error.localizedDescription }
    }
    func send() async {
        guard canWrite, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let c = connection else { return }
        working = true; defer { working = false }; error = nil; let epoch = generation
        do {
            let value = try await sync(c, epoch: epoch); try current(epoch)
            guard draft.revision == value.edit, draft.text == value.text, let id = sessionID,
                  let snap = snapshot, snap.documentId == value.document else { throw PCCompanionError(code: "draft_conflict", status: 409) }
            let command = PCPending(id: UUID().uuidString, text: value.text, revision: value.edit, conversation: snap.conversationId, server: c.identity)
            pending = command; saveDraft() // Persist before the single Send request.
            let receipt: PCReceipt = try await request("/v1/sessions/\(id)/commands", using: c, method: "POST", body: [
                "commandId": command.id, "action": "send", "documentId": value.document, "baseDraftHash": value.hash, "text": value.text])
            resolve(receipt, using: c)
        } catch { self.error = error.localizedDescription; if hasPending { status = "发送结果待确认 · 不会自动重发" } }
    }
    private func resolve(_ receipt: PCReceipt, using c: PCConnection) {
        guard let command = pending, command.id == receipt.commandId, command.server == c.identity else { return }
        if receipt.state == "done", receipt.result?.status == "sent_confirmed" {
            draft.sent(text: command.text, editedAt: command.revision); pending = nil
            defaults.removeObject(forKey: "PCCompanion.pendingSend"); status = "PC 网页已确认消息"
        } else if receipt.state == "failed" {
            pending = nil; error = receipt.result?.error ?? "发送未执行"; status = "请核对 PC 后再操作"
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
        guard !working, !reconnecting, !online, !fixture, !networkFixture || selected != nil else { return }
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
    @State private var confirmDraft = false
    @State private var confirmReceipt = false
    @Environment(\.scenePhase) private var scenePhase
    let returnToWeb: () -> Void
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Circle().fill(model.online ? Color.green : Color.gray).frame(width: 7, height: 7)
                    Text(model.status).font(.caption).accessibilityIdentifier("pc.remote.status")
                    Spacer()
                    if model.working || model.reconnecting { ProgressView().controlSize(.small) }
                    if !model.online { Button("重连") { Task { await model.resume() } }.font(.caption).disabled(model.working).accessibilityIdentifier("pc.remote.reconnect") }
                }.padding(.horizontal).padding(.vertical, 8)
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal).accessibilityIdentifier("pc.remote.error") }
                if let snapshot = model.snapshot {
                    ScrollViewReader { proxy in
                        VStack(spacing: 0) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 18) {
                                    if !model.online { Text("离线快照 · \(Date(timeIntervalSince1970: model.capturedAt / 1000), style: .time)").font(.caption).foregroundStyle(.secondary) }
                                    if snapshot.historyPartial { Text("同步最近已加载的消息，完整历史保留在 PC。").font(.caption).foregroundStyle(.secondary) }
                                    ForEach(snapshot.messages) { message in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(message.role == "user" ? "你" : "ChatGPT").font(.caption.bold()).foregroundStyle(.secondary)
                                                Spacer()
                                                Button { UIPasteboard.general.string = message.text } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("复制消息")
                                            }
                                            Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                            ForEach(Array(message.links.enumerated()), id: \.offset) { _, link in
                                                if let u = URL(string: link.url), ["https", "http"].contains(u.scheme ?? "") {
                                                    Link(link.title.isEmpty ? (u.host ?? "打开链接") : link.title, destination: u).font(.caption)
                                                }
                                            }
                                            if message.truncated { Text("正文较长，剩余部分请在 PC 查看").font(.caption).foregroundStyle(.secondary) }
                                        }.padding(12).background(.quaternary.opacity(message.role == "user" ? 0.8 : 0.25)).clipShape(RoundedRectangle(cornerRadius: 12)).id(message.id)
                                    }
                                    if snapshot.unsupportedTools { Label("复杂工具、授权及附件请在 PC 处理", systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary) }
                                    Color.clear.frame(height: 1).id("end")
                                }.padding()
                            }.onAppear { proxy.scrollTo("end", anchor: .bottom) }
                             .onChange(of: snapshot.conversationId) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                            HStack { Spacer(); Button("最新消息 ↓") { proxy.scrollTo("end", anchor: .bottom) }.font(.caption).padding(.horizontal) }
                        }
                    }
                } else { ContentUnavailableView("连接你的 PC Chrome", systemImage: "desktopcomputer", description: Text("PC 运行官方网页，手机原生显示答案。")) }
                VStack(spacing: 8) {
                    TextEditor(text: Binding(get: { model.draft.text }, set: { model.edited($0) }))
                        .frame(minHeight: 55, maxHeight: 100).padding(6).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("pc.remote.composer")
                    HStack {
                        if model.hasPending {
                            Button("核对发送回执") { Task { await model.checkReceipt() } }.accessibilityIdentifier("pc.remote.receipt")
                            Button("已在 PC 核对") { confirmReceipt = true }.font(.caption)
                        } else {
                            Button("同步草稿") { Task { await model.syncDraft() } }.disabled(!model.canWrite)
                            Button("采用 PC 草稿") { confirmDraft = true }.font(.caption).disabled(model.working || model.snapshot == nil)
                        }
                        Spacer()
                        Button("发送") { Task { await model.send() } }.buttonStyle(.borderedProminent)
                            .disabled(!model.canWrite || model.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.padding().background(.regularMaterial)
            }.navigationTitle(model.snapshot?.title ?? "PC 同步").navigationBarTitleDisplayMode(.inline)
             .toolbar {
                 ToolbarItem(placement: .topBarLeading) { Button("原网页") { Task { await model.disconnect(); returnToWeb() } }.disabled(model.working) }
                 ToolbarItem(placement: .topBarTrailing) { Button("连接") { settings = true } }
             }
             .sheet(isPresented: $settings) { configuration }
             .alert("采用 PC 草稿？", isPresented: $confirmDraft) {
                 Button("取消", role: .cancel) {}; Button("替换手机草稿", role: .destructive) { model.usePCDraft() }
             } message: { Text("仅替换手机输入框，不会发送消息。请先复制需要保留的本地文字。") }
             .alert("已检查 PC 发送结果？", isPresented: $confirmReceipt) {
                 Button("取消", role: .cancel) {}; Button("已核对，解除等待") { model.acknowledgeManualCheck() }
             } message: { Text("请先在 PC 确认该消息是否已发送。此操作不会重发，也不会删除服务端防重复记录。") }
             .task { await model.resume(); if model.pairingKey.isEmpty { settings = true } }
             .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.resume() } } else if phase == .background { model.pause() } }
             .onDisappear { model.pause() }
        }
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
