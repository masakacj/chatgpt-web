import Foundation
import SwiftUI
import Security

struct STTab: Codable, Identifiable {
    let tabId: Int; let title: String; let conversationId: String; let active: Bool
    var id: Int { tabId }
}
struct STSnapshot: Codable {
    let schema: Int; let documentId: String; let conversationId: String; let title: String
    let messages: [PCRemoteMessage]; let status: String; let draftHash: String
    var sharedTab: Bool?; var route: String?; var projectId: String?; var temporary: Bool?
    var canSend: Bool?; var pcDraftOccupied: Bool?; var composing: Bool?; var responsePhase: String?
    var interactions: [PCInteractionCard]?; var historyCursor: String?; var hasOlder: Bool?
    var sidebarIndicators: [STSidebarSignal]?
    var model: STPCModel?
}
struct STPCModel: Codable { let available: Bool; let name: String }
struct STModelOption: Codable, Identifiable { let id: String; let label: String; var selected: Bool?; var submenu: Bool? }
private struct STModelCatalog: Decodable { let available: Bool; let current: String; let options: [STModelOption] }
private struct STModelChoice: Decodable { let status: String; var error: String?; var model: STPCModel?; var options: [STModelOption]? }
private struct STUploadResult: Decodable { let status: String; var error: String?; var name: String? }
struct STSidebarSignal: Codable {
    let id: String
    let status: String
    let readState: String
}
struct STEnvelope: Decodable {
    let ok: Bool; let sessionId: String; let revision: Int
    var capturedAt: Double?; var routeChanged: Bool?; var tabClosed: Bool?; var snapshot: STSnapshot?
}
struct STProject: Codable, Identifiable { let id: String; let title: String; let collapsed: Bool; let hasMore: Bool }
struct STChat: Codable, Identifiable {
    let id: String; let title: String
    var projectId: String?; var current: Bool?; var status: String?; var readState: String?; var activityAt: Double?
}
struct STLibrary: Decodable {
    var projects: [STProject]?; var chats: [STChat]?; var partial: Bool?; var source: String?
    var hasMore: Bool?; var loading: Bool?; var emptyConfirmed: Bool?; var snapshot: STSnapshot?
}
private struct STHealth: Decodable { let capabilities: [String]?; var serverId: String? }
private struct STTabs: Decodable { let tabs: [STTab] }
private struct STOK: Decodable { let ok: Bool? }
private struct STFailure: Decodable { let error: String }
private struct STResult: Decodable { var status: String?; var error: String?; var conversationId: String?; var projectId: String? }
private struct STReceipt: Decodable { let commandId: String; let state: String; var result: STResult? }
private struct STHistory: Decodable { let documentId: String; let conversationId: String; let messages: [PCRemoteMessage]; var cursor: String?; let hasMore: Bool }
struct STActionPending: Codable { let id: String; let server: String; let conversation: String; var kind: String? = nil }
private struct STSaved: Codable {
    var ledger: STDraftLedger; var tabId: Int?; var snapshot: STSnapshot?; var server: String?
    var actionPending: STActionPending?
}
private struct STConnection {
    let origin: URL; let key: String
    var identity: String { PCCompanionPolicy.hash(origin.absoluteString + "|" + key) }
}
struct STError: LocalizedError {
    let code: String; var status: Int = 0
    var errorDescription: String? {
        let text = [
            "shared_bridge_required": "PC 桥接尚不支持共享标签页，请更新桥接后连接。",
            "pc_route_changed": "PC 已切换对话，正在读取当前页面；没有重发消息。",
            "pc_draft_conflict": "PC 输入框有未发送内容，请先在电脑处理。手机草稿已保留。",
            "pc_draft_blocks_navigation": "PC 输入框有未发送内容，请先处理后再切换。",
            "draft_conflict": "PC 输入已变化，手机草稿已保留。",
            "pc_composing": "PC 正在输入，请稍后发送。",
            "pc_busy_or_approval": "当前对话正在生成或等待确认，请稍后发送。",
            "send_unavailable": "PC 发送按钮尚未就绪，消息未发送。",
            "page_loading": "PC 页面正在加载。",
            "page_not_ready": "PC 页面尚未就绪，请检查电脑上的页面。",
            "official_search_unavailable": "当前网页没有可用的历史搜索入口。",
            "conversation_not_observed": "该历史结果已失效，请重新搜索。",
            "new_chat_control_unavailable": "当前网页的新聊天入口不可用。",
            "project_navigation_unconfirmed": "未确认进入指定项目，未发送消息。",
            "tab_already_paired": "该标签页仍有连接，请稍后重连或选择其他页面。",
            "tab_closed": "绑定的 PC 标签页已关闭，请重新选择。",
            "local_storage_failed": "手机草稿保存失败，未提交发送。",
            "pairing_required": "配对失效，请重新连接 PC。",
            "invalid_pairing": "请填写有效的配对密钥。",
            "redirect_refused": "连接地址发生重定向，已停止请求。"
        ]
        return text[code] ?? (status == 401 || status == 403 ? "PC 连接未获授权，请检查配对。" : "操作未完成（\(code)），草稿已保留。")
    }
}
private enum STKeychain {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ChatGPTWeb.PCCompanion.v1", kSecAttrAccount as String: "pairing"]
    static func load() -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) throws {
        var q = query; let data = [kSecValueData as String: Data(key.utf8)]
        var result = SecItemUpdate(q as CFDictionary, data as CFDictionary)
        if result == errSecItemNotFound { q.merge(data) { _, value in value }; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; result = SecItemAdd(q as CFDictionary, nil) }
        guard result == errSecSuccess else { throw STError(code: "keychain_unavailable") }
    }
}
private final class STNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class SharedTabModel: ObservableObject {
    static let stageEndpoint = "https://chatgpt-bridge-test.78175132.xyz"
    @Published var endpoint = UserDefaults.standard.string(forKey: "PCCompanion.endpoint") ?? PCCompanionPolicy.defaultEndpoint
    @Published var pairingKey = ""
    @Published var homeEndpoint = UserDefaults.standard.string(forKey: "SharedPC.homeEndpoint") ?? ""
    @Published var homeEnabled = UserDefaults.standard.bool(forKey: "SharedPC.homeEnabled")
    @Published var routeStatus = "HTTPS · 单线路"
    @Published var routeNotice: String?
    @Published var tabs: [STTab] = []
    @Published var projects: [STProject] = []
    @Published var chats: [STChat] = []
    @Published var recentActive: [STChat] = []
    @Published var modelOptions: [STModelOption] = []
    @Published var modelPickerLoading = false
    @Published var uploading = false
    @Published var controlNotice: String?
    @Published var snapshot: STSnapshot?
    @Published var older: [PCRemoteMessage] = []
    @Published var text = ""
    @Published var online = false
    @Published var busy = false
    @Published var loading = false
    @Published var libraryLoading = false
    @Published var historyLoading = false
    @Published var searchHasMore = false
    @Published var searchNotice = ""
    @Published var error: String?
    @Published var status = "未连接 PC"
    @Published var needsSettings = false
    @Published private(set) var ledger = STDraftLedger()
    @Published private(set) var actionPending: STActionPending?
    private(set) var selectedTabId: Int?
    // Legacy settings retain their original ledger identity while HTTP uses
    // the stable 443 endpoint. This avoids orphaning drafts and pending receipts.
    var legacyEndpointRouted: Bool {
        (try? PCCompanionPolicy.origin(endpoint))?.absoluteString == PCCompanionPolicy.legacyEndpoint
    }
    private var owner = ""
    private var connection: STConnection?
    private var sessionID: String?
    private var revision = -1
    private var epoch = 0
    private var foreground = true
    private var resuming = false
    private var pollTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var capabilities = Set<String>()
    private var saveTask: Task<Void, Never>?
    private var historyCursor: String?
    private var historyHasMore: Bool?
    private let redirect = STNoRedirect()
    private let serviceRouter = STServiceConnectionRouter()
    let fixture: Bool
    private let clientID: String
    private lazy var transport: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 28; config.timeoutIntervalForResource = 32
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        config.waitsForConnectivity = false
        #if DEBUG
        if fixture { config.protocolClasses = [SharedTabFixtureProtocol.self] }
        #endif
        return URLSession(configuration: config, delegate: redirect, delegateQueue: nil)
    }()
    var displayMessages: [PCRemoteMessage] {
        let recent = snapshot?.messages ?? []; let ids = Set(recent.map(\.id))
        return older.filter { !ids.contains($0.id) } + recent
    }
    var canLoadHistory: Bool { online && !historyLoading && (historyHasMore ?? snapshot?.hasOlder ?? false) }
    var currentPending: STPendingSend? { ledger.pendingFor(owner) }
    // Mirror the bound official PC composer's eligibility, including native
    // follow-up Sends offered while a previous response is still generating.
    // Never override approval, PC-draft, navigation, or editing conflicts.
    var canSubmit: Bool {
        guard let snap = snapshot else { return false }
        return online && !busy && !loading && currentPending == nil && actionPending == nil && snap.canSend == true &&
            snap.pcDraftOccupied != true && snap.composing != true &&
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canUpload: Bool { online && !busy && !uploading && !loading && actionPending == nil && capabilities.contains("mobile-upload") && snapshot != nil && snapshot?.status != "waiting" }
    var canPickModel: Bool { online && !busy && actionPending == nil && capabilities.contains("model-selection") && snapshot?.model?.available == true }
    var thinking: Bool { online && (snapshot?.responsePhase == "thinking" || snapshot?.status == "running" && snapshot?.messages.last?.role != "assistant") }
    var projectTitle: String? { projects.first { $0.id == snapshot?.projectId }?.title }
    private var stateFile: URL? { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SharedPCCompanion/state.json") }

    init() {
        #if DEBUG
        fixture = ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--shared-tab-fixture")
        #else
        fixture = false
        #endif
        clientID = UserDefaults.standard.string(forKey: "SharedPC.clientID") ?? UUID().uuidString
        if fixture {
            #if DEBUG
            SharedTabFixtureProtocol.reset()
            #endif
            endpoint = "https://shared-tab.invalid"; pairingKey = String(repeating: "T", count: 43); selectedTabId = 7
            if ProcessInfo.processInfo.arguments.contains("--shared-fixture-legacy-origin") {
                endpoint = PCCompanionPolicy.legacyEndpoint
                let legacy = PCCompanionPolicy.hash(endpoint + "|" + pairingKey)
                owner = legacy + "|11111111-1111-4111-8111-111111111111"
                ledger.edit(owner, text: "原58443未发送草稿")
                text = ledger.draft(owner).text
            }
            homeEndpoint = "https://fixture-home.invalid"
            homeEnabled = ProcessInfo.processInfo.arguments.contains("--shared-fixture-dual") ||
                ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--shared-fixture-home-") }
            return
        }
        UserDefaults.standard.set(clientID, forKey: "SharedPC.clientID")
        pairingKey = STKeychain.load()
        if let file = stateFile, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(STSaved.self, from: data) {
            ledger = saved.ledger; selectedTabId = saved.tabId; actionPending = saved.actionPending
            if let c = try? config(), saved.server == c.identity { snapshot = saved.snapshot; if let snap = snapshot { owner = ownerKey(snap, c); text = ledger.draft(owner).text }; status = "本地快照 · 正在连接 PC" }
        } else { importLegacyDraft() }
        if selectedTabId == nil, let data = UserDefaults.standard.data(forKey: "PCCompanion.lastTab"), let tab = try? JSONDecoder().decode(PCRemoteTab.self, from: data) { selectedTabId = tab.tabId }
    }
    private func importLegacyDraft() {
        guard let c = try? config(), let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: root.appendingPathComponent("PCCompanion/draft.json")),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let draft = raw["draft"] as? [String: Any], let id = draft["owner"] as? String else { return }
        let key = c.identity + "|" + id
        ledger.drafts[key] = STLocalDraft(text: draft["text"] as? String ?? "", revision: draft["revision"] as? Int ?? 0)
        if let p = raw["pending"] as? [String: Any], let command = p["id"] as? String, let server = p["server"] as? String {
            ledger.pending[command] = STPendingSend(id: command, owner: key, text: p["text"] as? String ?? "", revision: p["revision"] as? Int ?? 0, server: server, temporary: false)
        }
    }
    private func config() throws -> STConnection {
        guard pairingKey.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { throw STError(code: "invalid_pairing") }
        return STConnection(origin: try PCCompanionPolicy.origin(endpoint), key: pairingKey)
    }
    private func ownerKey(_ s: STSnapshot, _ c: STConnection) -> String { c.identity + "|" + (s.conversationId.isEmpty ? "new:" + (s.projectId ?? "") : s.conversationId) }
    @discardableResult private func save() -> Bool {
        if fixture { return true }
        guard let file = stateFile else { return false }
        do {
            let parent = file.deletingLastPathComponent(); try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            var directory = parent; var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
            let saved = STSaved(ledger: ledger, tabId: selectedTabId, snapshot: snapshot, server: connection?.identity ?? (try? config().identity), actionPending: actionPending)
            try JSONEncoder().encode(saved).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); return true
        } catch { self.error = STError(code: "local_storage_failed").localizedDescription; return false }
    }
    private func saveSoon() {
        saveTask?.cancel(); saveTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 300_000_000); guard !Task.isCancelled else { return }; self?.save() }
    }
    func edited(_ value: String) { text = value; ledger.edit(owner, text: value); saveSoon() }
    /// The logical origin and Keychain key never change when a request takes
    /// another physical HTTPS route. Raw transport is used for attestation and
    /// for the router's strictly bounded, GET-only retry.
    private func rawRequest<T: Decodable>(_ path: String, using c: STConnection,
                                           via origin: URL, body: [String: Any]? = nil,
                                           method: String? = nil) async throws -> T {
        guard path.hasPrefix("/v1/"), !path.contains("\\"), let url = URL(string: path, relativeTo: origin)?.absoluteURL,
              url.host == origin.host, url.port == origin.port, url.scheme == "https" else { throw URLError(.badURL) }
        var req = URLRequest(url: url); req.httpMethod = method ?? (body == nil ? "GET" : "POST")
        req.setValue("Bearer " + c.key, forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await transport.data(for: req)
        guard data.count <= 800000, let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if (300...399).contains(http.statusCode) { throw STError(code: "redirect_refused", status: http.statusCode) }
        guard (200...299).contains(http.statusCode) else {
            let raw = (try? JSONDecoder().decode(STFailure.self, from: data))?.error ?? "http_\(http.statusCode)"
            throw STError(code: raw.range(of: "^[a-z0-9_]{1,80}$", options: .regularExpression) != nil ? raw : "server_error", status: http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func retryableGET(_ error: Error) -> Bool {
        if let failure = error as? STError { return [408, 425, 500, 502, 503, 504].contains(failure.status) }
        return PCCompanionPolicy.retryableRead(error)
    }
    private func updateRouteStatus() {
        routeStatus = serviceRouter.label
        routeNotice = serviceRouter.notice
    }
    private func request<T: Decodable>(_ path: String, using c: STConnection,
                                        body: [String: Any]? = nil, method: String? = nil) async throws -> T {
        let verb = method ?? (body == nil ? "GET" : "POST")
        defer { updateRouteStatus() }
        return try await serviceRouter.perform(method: verb, retryable: { self.retryableGET($0) },
            probe: { origin in
                let health: STHealth = try await self.rawRequest("/v1/health", using: c, via: origin)
                guard health.capabilities?.contains("shared-tab-v1") == true else { return nil }
                return health.serverId
            }, operation: { origin in
                try await self.rawRequest(path, using: c, via: origin, body: body, method: verb)
            })
    }
    /// CF443 is the identity anchor. Home is only eligible after the user has
    /// explicitly configured its HTTPS origin and both authenticated health
    /// responses attest to the same persistent serverId. Missing serverId
    /// keeps the legacy CF-only client operational.
    private func verifiedHealth(using c: STConnection) async throws -> STHealth {
        // The visible settings fields are staging inputs. No bearer token is
        // sent to a newly typed Home host until "应用线路配置" persists explicit
        // user consent. UI fixtures use only intercepted .invalid hosts.
        let allowedHome = fixture ? homeEnabled : UserDefaults.standard.bool(forKey: "SharedPC.homeEnabled")
        let approvedHome = fixture ? homeEndpoint : (UserDefaults.standard.string(forKey: "SharedPC.homeEndpoint") ?? "")
        serviceRouter.configure(logicalOrigin: c.origin,
            transportOrigin: PCCompanionPolicy.transportOrigin(for: c.origin),
            identity: c.identity, homeInput: approvedHome, homeEnabled: allowedHome, fixture: fixture)
        guard let cf = serviceRouter.cloudflareOrigin else { throw STError(code: "invalid_endpoint") }
        defer { updateRouteStatus() }
        let health: STHealth = try await rawRequest("/v1/health", using: c, via: cf)
        guard health.capabilities?.contains("shared-tab-v1") == true else { throw STError(code: "shared_bridge_required") }
        serviceRouter.attestCloudflare(health.serverId)
        if let home = serviceRouter.candidateHomeOrigin,
           serviceRouter.authenticatedServerId != nil {
            do {
                let proof: STHealth = try await rawRequest("/v1/health", using: c, via: home)
                guard proof.capabilities?.contains("shared-tab-v1") == true else {
                    throw STError(code: "shared_bridge_required")
                }
                serviceRouter.attestHome(proof.serverId)
            } catch {
                serviceRouter.reportHomeHealthError(error)
            }
        }
        return health
    }
    func applyHomeSettings() async {
        if homeEnabled && (try? PCCompanionPolicy.origin(homeEndpoint)) == nil {
            routeNotice = "请输入可信的 Home HTTPS 服务地址，未更改当前连接"
            return
        }
        if !fixture {
            UserDefaults.standard.set(homeEndpoint, forKey: "SharedPC.homeEndpoint")
            UserDefaults.standard.set(homeEnabled, forKey: "SharedPC.homeEnabled")
        }
        // No new owner or pairing key is created. Pending command IDs survive
        // suspension and are only reconciled by GET on resume.
        pause()
        await resume()
    }
    private func current(_ generation: Int) throws { guard epoch == generation, foreground, !Task.isCancelled else { throw CancellationError() } }
    func loadTabs() async {
        guard !busy else { return }; busy = true; defer { busy = false }; error = nil
        do {
            let c = try config(); let health = try await verifiedHealth(using: c)
            capabilities = Set(health.capabilities ?? [])
            guard health.capabilities?.contains("shared-tab-v1") == true else { throw STError(code: "shared_bridge_required") }
            let value: STTabs = try await request("/v1/tabs?shared=1", using: c); tabs = value.tabs
            if !fixture { try STKeychain.save(c.key); UserDefaults.standard.set(c.origin.absoluteString, forKey: "PCCompanion.endpoint") }
            status = tabs.isEmpty ? "PC 没有可绑定的 ChatGPT 页面" : "选择要与手机共用的 PC 标签页"
        } catch { self.error = error.localizedDescription }
    }
    func bind(_ tab: STTab) async {
        guard !busy else { return }; busy = true; defer { busy = false }; error = nil
        ledger.edit(owner, text: text); save()
        do { let c = try config(); await disconnectSession(); selectedTabId = tab.tabId; connection = c; foreground = true; try await subscribe(using: c); needsSettings = false; startPolling(); }
        catch { online = false; self.error = error.localizedDescription }
    }
    private func subscribe(using c: STConnection) async throws {
        guard let tab = selectedTabId else { throw STError(code: "tab_closed") }
        let generation = epoch
        let result: STEnvelope = try await request("/v1/sessions", using: c, body: ["tabId": tab, "followTab": true, "clientId": clientID])
        try current(generation)
        guard result.sessionId.range(of: "^[A-Za-z0-9_-]{16,100}$", options: .regularExpression) != nil else { throw STError(code: "schema_invalid") }
        sessionID = result.sessionId; revision = -1; try apply(result, using: c); online = true; save()
    }
    private func apply(_ envelope: STEnvelope, using c: STConnection) throws {
        guard envelope.ok, envelope.sessionId == sessionID else { throw STError(code: "schema_invalid") }
        guard envelope.revision >= revision else { return }
        // Resume may receive the same revision. We still have to rehydrate the
        // visible PC status after marking the app offline; skipping here leaves
        // the header stuck at '连接恢复中' even though the session is healthy.
        if envelope.revision == revision && envelope.routeChanged != true && envelope.tabClosed != true && online { return }
        revision = envelope.revision
        if envelope.tabClosed == true { online = false; loading = false; snapshot = nil; status = "绑定标签页已关闭"; needsSettings = true; return }
        if envelope.routeChanged == true && envelope.snapshot == nil { loading = true; snapshot = nil; older = []; status = "PC 正在切换对话"; return }
        guard let fresh = envelope.snapshot else { return }
        try display(fresh, using: c)
    }
    // Navigation returns a PC-observed snapshot directly. Display it immediately
    // instead of waiting for a later cached session GET to catch up.
    private func display(_ fresh: STSnapshot, using c: STConnection) throws {
        guard fresh.schema == 1, fresh.sharedTab == true, fresh.messages.count <= 24 else { throw STError(code: "schema_invalid") }
        if snapshot?.documentId != fresh.documentId { older = []; historyCursor = nil; historyHasMore = nil }
        let newOwner = ownerKey(fresh, c)
        let waitingForNewReceipt = busy && currentPending?.temporary == true && !fresh.conversationId.isEmpty
        if newOwner != owner && !waitingForNewReceipt { ledger.edit(owner, text: text); owner = newOwner; text = ledger.draft(owner).text }
        snapshot = fresh; loading = fresh.status == "loading"
        // Only official visible sidebar badges are projected. An unknown row
        // is unknown, not a guessed completion or inferred read receipt.
        if let indicators = fresh.sidebarIndicators, !indicators.isEmpty {
            let byId = Dictionary(indicators.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
            chats = chats.map { original in
                guard let marker = byId[original.id] else { return original }
                var chat = original
                chat.status = marker.status
                chat.readState = marker.readState
                return chat
            }
            recentActive = recentActive.map { original in
                guard let marker = byId[original.id] else { return original }
                var chat = original; chat.status = marker.status; chat.readState = marker.readState
                return chat
            }
        }
        status = loading ? "PC 页面加载中" : fresh.pcDraftOccupied == true ? "PC 有未发送内容" : fresh.status == "running" ? (fresh.canSend == true ? "PC 生成中 · 可继续发送" : "PC 生成中 · 手机草稿已保留") : fresh.status == "waiting" ? "PC 等待确认 · 手机草稿已保留" : "与 PC 共用此标签页"
        // A prior definite busy rejection must not leave an obsolete red alert
        // after the same PC page explicitly reports that composing is possible.
        if fresh.canSend == true && error == STError(code: "pc_busy_or_approval").localizedDescription { error = nil }
        saveSoon()
    }
    private func scheduleReconnect() {
        guard foreground, reconnectTask == nil, reconnectAttempts < 4 else { return }
        reconnectAttempts += 1
        let delay = UInt64(min(1 << (reconnectAttempts - 1), 8)) * 1_000_000_000
        reconnectTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, self.foreground else { return }
            self.reconnectTask = nil
            await self.resume()
        }
    }
    private func startPolling() {
        pollTask?.cancel(); let generation = epoch
        pollTask = Task { [weak self] in
            guard let self else { return }; var failures = 0
            while !Task.isCancelled && self.foreground && generation == self.epoch && self.online {
                guard let c = self.connection, let id = self.sessionID else { break }
                do {
                    let value: STEnvelope = try await self.request("/v1/sessions/\(id)?after=\(self.revision)", using: c)
                    try self.current(generation); try self.apply(value, using: c); failures = 0
                } catch is CancellationError { return }
                catch {
                    if Task.isCancelled || generation != self.epoch { return }
                    if let e = error as? STError, e.status == 410, failures < 2 { failures += 1; do { try await self.subscribe(using: c); continue } catch {} }
                    let code = (error as? STError)?.status ?? 0
                    if [401, 403, 429].contains(code) || failures >= 3 {
                        self.online = false
                        if PCCompanionPolicy.retryableRead(error) && ![401, 403, 429].contains(code) {
                            self.status = "PC 连接恢复中 · 本地内容已保留"
                            self.error = nil
                            self.scheduleReconnect()
                        } else {
                            self.status = "离线快照 · 点击重连"
                            self.error = error.localizedDescription
                        }
                        break
                    }
                    failures += 1; try? await Task.sleep(nanoseconds: UInt64(failures) * 1_000_000_000)
                }
            }
        }
    }
    func resume() async {
        foreground = true
        if online || resuming { return }
        if busy { scheduleReconnect(); return }
        if pairingKey.isEmpty { needsSettings = true; return }
        guard selectedTabId != nil else { needsSettings = true; await loadTabs(); return }
        busy = true; resuming = true; defer { busy = false; resuming = false }; epoch += 1
        status = "PC 连接恢复中 · 本地内容已保留"
        error = nil
        do {
            let c = try config(); connection = c
            let health = try await verifiedHealth(using: c)
            capabilities = Set(health.capabilities ?? [])
            guard health.capabilities?.contains("shared-tab-v1") == true else { throw STError(code: "shared_bridge_required") }
            if let id = sessionID {
                do { let result: STEnvelope = try await request("/v1/sessions/\(id)?after=-1", using: c); try apply(result, using: c); online = result.tabClosed != true }
                catch { if (error as? STError)?.status == 410 { sessionID = nil; try await subscribe(using: c) } else { throw error } }
            } else { try await subscribe(using: c) }
            if online {
                reconnectAttempts = 0
                reconnectTask?.cancel(); reconnectTask = nil
                error = nil
                startPolling()
                await checkReceiptsInternal(using: c)
            }
        } catch {
            online = false
            if PCCompanionPolicy.retryableRead(error) {
                self.error = nil
                status = "PC 连接恢复中 · 本地内容已保留"
                scheduleReconnect()
            } else {
                self.error = error.localizedDescription
                status = "离线快照 · 点击重连"
            }
        }
    }
    func pause() {
        foreground = false; epoch += 1
        pollTask?.cancel()
        reconnectTask?.cancel(); reconnectTask = nil; reconnectAttempts = 0
        online = false; save(); status = "本地快照"
        if error?.localizedCaseInsensitiveContains("timed out") == true ||
           error?.contains("超时") == true { error = nil }
    }
    private func disconnectSession() async {
        epoch += 1; pollTask?.cancel(); online = false; revision = -1
        let id = sessionID; sessionID = nil
        if let id, let c = connection { let _: STOK? = try? await request("/v1/sessions/\(id)", using: c, method: "DELETE") }
    }
    func disconnect() async { ledger.edit(owner, text: text); save(); await disconnectSession() }
    // Make the signed development IPA usable against the separately verified
    // public Bridge stage. Never send a saved production pairing key to stage.
    // Drafts are already persisted by disconnect() and remain keyed by server.
    func chooseStageBridge() async {
        guard !busy else { return }
        await disconnect()
        endpoint = Self.stageEndpoint
        pairingKey = ""
        connection = nil
        selectedTabId = nil
        tabs = []; chats = []; projects = []; recentActive = []; modelOptions = []
        snapshot = nil; older = []; historyCursor = nil; historyHasMore = nil
        owner = ""; text = ""
        error = nil
        status = "测试通道 · 请复制 PC 13213 的配对密钥"
        needsSettings = true
    }
    @discardableResult private func reserveAction(_ id: String, kind: String,
                                                   using c: STConnection, snapshot: STSnapshot) -> Bool {
        guard actionPending == nil else { controlNotice = "上次操作回执待确认；不会重复提交"; return false }
        actionPending = STActionPending(id: id, server: c.identity, conversation: snapshot.conversationId, kind: kind)
        if save() { return true }
        actionPending = nil
        controlNotice = STError(code: "local_storage_failed").localizedDescription
        return false
    }
    private func settleAction(_ id: String) {
        guard actionPending?.id == id else { return }
        actionPending = nil
        save()
    }
    private func refresh(using c: STConnection) async throws {
        guard let id = sessionID else { return }; let generation = epoch
        let value: STEnvelope = try await request("/v1/sessions/\(id)?after=-1", using: c); try current(generation); try apply(value, using: c)
    }
    func catalog() async { await libraryAction("catalog") }
    func search(_ query: String, more: Bool = false) async { await libraryAction("search", fields: ["query": query, "more": more], append: more) }
    func expand(_ project: STProject, more: Bool = false) async { await libraryAction("project", fields: ["projectId": project.id, "more": more]) }
    private func libraryAction(_ action: String, fields: [String: Any] = [:], append: Bool = false) async {
        guard online, !libraryLoading, !busy, let c = connection, let id = sessionID else { return }
        libraryLoading = true; defer { libraryLoading = false }; error = nil; let generation = epoch
        do {
            var body: [String: Any] = ["action": action, "commandId": UUID().uuidString, "documentId": snapshot?.documentId ?? ""]
            body.merge(fields) { _, value in value }
            let result: STLibrary = try await request("/v1/sessions/\(id)/actions", using: c, body: body); try current(generation)
            projects = result.projects ?? projects
            if append { let ids = Set(chats.map(\.id)); chats += (result.chats ?? []).filter { !ids.contains($0.id) } } else { chats = result.chats ?? [] }
            if action == "catalog" {
                recentActive = chats.filter { ($0.activityAt ?? 0) > 0 }
                    .sorted { ($0.activityAt ?? 0) > ($1.activityAt ?? 0) }.prefix(30).map { $0 }
            }
            searchHasMore = result.hasMore == true
            searchNotice = result.loading == true ? "官网搜索仍在加载" : result.emptyConfirmed == true ? "官网搜索未找到匹配对话" : result.source == "official_search" ? "官网历史搜索 · 按需加载" : "最近对话与项目 · 可搜索更早记录"
        } catch { self.error = error.localizedDescription }
    }
    func open(_ chat: STChat) async { await navigate("open", fields: ["targetConversationId": chat.id]) }
    func newChat(project: STProject? = nil) async { await navigate("new", fields: project.map { ["projectId": $0.id] } ?? [:]) }
    private func navigate(_ action: String, fields: [String: Any]) async {
        guard online, !busy, !libraryLoading, actionPending == nil, let c = connection, let id = sessionID, let snap = snapshot else { return }
        busy = true; defer { busy = false }; error = nil; ledger.edit(owner, text: text); save(); let generation = epoch
        let commandId = UUID().uuidString
        guard reserveAction(commandId, kind: "navigation", using: c, snapshot: snap) else { return }
        do {
            var body: [String: Any] = ["action": action, "commandId": commandId, "documentId": snap.documentId]; body.merge(fields) { _, value in value }
            let result: STLibrary = try await request("/v1/sessions/\(id)/actions", using: c, body: body)
            try current(generation)
            settleAction(commandId)
            // The action response already contains the page observed after the
            // native PC navigation. Only adopt its matching destination; GET
            // reconciliation below still handles any subsequent PC-side change.
            if let fresh = result.snapshot,
               (action != "new" || fresh.conversationId.isEmpty),
               (action != "open" || fresh.conversationId == (fields["targetConversationId"] as? String ?? "")),
               (action != "new" || fresh.documentId != snap.documentId) {
                try display(fresh, using: c)
            }
            try await refresh(using: c)
        } catch {
            self.error = "对话切换结果待确认；只核对命令回执，不会重新执行。\(error.localizedDescription)"
            try? await refresh(using: c)
        }
    }
    func loadModelOptions() async {
        guard canPickModel, let c = connection, let id = sessionID, let snap = snapshot else { return }
        modelPickerLoading = true; defer { modelPickerLoading = false }
        do {
            let value: STModelCatalog = try await request("/v1/sessions/\(id)/actions", using: c,
                body: ["action": "model_catalog", "commandId": UUID().uuidString, "documentId": snap.documentId])
            modelOptions = value.available ? value.options : []
            if modelOptions.isEmpty { controlNotice = "PC 当前未提供可镜像的模型或思考选项" }
        } catch { controlNotice = error.localizedDescription }
    }
    func chooseModel(_ option: STModelOption) async {
        guard canPickModel, let c = connection, let id = sessionID, let snap = snapshot else { return }
        modelPickerLoading = true; defer { modelPickerLoading = false }
        let generation = epoch, commandId = UUID().uuidString
        guard reserveAction(commandId, kind: "model", using: c, snapshot: snap) else { return }
        do {
            let result: STModelChoice = try await request("/v1/sessions/\(id)/actions", using: c,
                body: ["action": "model_select", "commandId": commandId,
                       "documentId": snap.documentId, "optionId": option.id])
            try current(generation)
            guard result.status == "option_clicked" else { throw STError(code: result.error ?? "model_option_changed") }
            settleAction(commandId)
            modelOptions = result.options ?? []
            controlNotice = modelOptions.isEmpty ? "已在 PC 网页选择：\(option.label)" : "请选择 PC 网页实际提供的细分档位"
            try? await refresh(using: c)
        } catch { controlNotice = "模型操作结果待确认；可核对回执，不会自动重复选择。\(error.localizedDescription)" }
    }
    func upload(_ data: Data, filename: String, mimeType: String) async {
        guard canUpload, let c = connection, let id = sessionID, let snap = snapshot else { return }
        guard !data.isEmpty && data.count <= 10 * 1024 * 1024 else {
            controlNotice = "附件须小于 10 MB，草稿仍已保留"; return
        }
        uploading = true; defer { uploading = false }; controlNotice = "正在交给 PC 网页附件控件…"
        let safeName = String(filename.replacingOccurrences(of: #"[\\/\x00-\x1f]"#,
                         with: "_", options: .regularExpression).prefix(180))
        let generation = epoch, uploadId = UUID().uuidString
        guard reserveAction(uploadId, kind: "upload", using: c, snapshot: snap) else { return }
        do {
            let result: STUploadResult = try await request("/v1/sessions/\(id)/uploads", using: c,
                body: ["uploadId": uploadId, "documentId": snap.documentId,
                       "name": safeName, "mimeType": mimeType, "base64": data.base64EncodedString()])
            try current(generation)
            if result.status == "handed_to_pc" {
                settleAction(uploadId)
                controlNotice = "已交给 PC 网页附件控件，云端完成状态仍需在 PC 确认"
            } else {
                controlNotice = "附件结果待确认：\(result.error ?? result.status)，不会自动重传"
            }
        } catch {
            controlNotice = "附件结果待确认：\(error.localizedDescription)。仅通过原 uploadId 查询回执，不会自动重传"
        }
    }
    func send() async {
        guard canSubmit, let c = connection, let id = sessionID, let snap = snapshot else { return }
        busy = true; defer { busy = false }; error = nil; ledger.edit(owner, text: text); let generation = epoch
        do {
            let command = try ledger.reserve(owner, server: c.identity, temporary: snap.conversationId.isEmpty)
            guard save() else { ledger.definitelyNotSent(command.id); throw STError(code: "local_storage_failed") }
            var body: [String: Any] = ["commandId": command.id, "action": "compose", "documentId": snap.documentId, "baseDraftHash": snap.draftHash, "text": command.text]
            if let project = snap.projectId { body["projectId"] = project }
            let receipt: STReceipt = try await request("/v1/sessions/\(id)/commands", using: c, body: body)
            try current(generation); resolve(receipt, using: c); try? await refresh(using: c)
        } catch { self.error = error.localizedDescription; if currentPending != nil { status = "发送结果待确认 · 不会自动重发" }; save() }
    }
    private func resolve(_ receipt: STReceipt, using c: STConnection) {
        guard let command = ledger.pending[receipt.commandId], command.server == c.identity else { return }
        if receipt.state == "done" && receipt.result?.status == "sent_confirmed" {
            let actualOwner = receipt.result?.conversationId.map { c.identity + "|" + $0 }
            ledger.confirmed(command.id, actualOwner: actualOwner)
            if command.temporary, owner == command.owner, let actualOwner { owner = actualOwner }
            text = ledger.draft(owner).text; status = "消息已发送"; error = nil
        } else if receipt.state == "failed" {
            ledger.definitelyNotSent(command.id); error = STError(code: receipt.result?.error ?? "not_sent").localizedDescription; status = "确定未发送 · 草稿已保留"
        } else { status = "发送结果待确认 · 不会自动重发" }
        save()
    }
    func checkReceipts() async { guard !busy, let c = connection else { return }; busy = true; defer { busy = false }; await checkReceiptsInternal(using: c) }
    private func checkReceiptsInternal(using c: STConnection) async {
        for command in Array(ledger.pending.values).filter({ $0.server == c.identity }) {
            if let receipt: STReceipt = try? await request("/v1/commands/\(command.id)", using: c) { resolve(receipt, using: c) }
        }
        if let pending = actionPending, pending.server == c.identity {
            do {
                let receipt: STReceipt = try await request("/v1/commands/\(pending.id)", using: c)
                guard receipt.commandId == pending.id else { return }
                if receipt.state == "done" || receipt.state == "failed" {
                    settleAction(pending.id)
                    controlNotice = receipt.state == "done" ?
                        "PC 已确认操作回执（\(pending.kind ?? "action")）；不代表附件已完成云端上传" :
                        "PC 确认本次操作未完成，仍可核对当前页面"
                } else {
                    controlNotice = "操作结果待确认，保留原 commandId，不会自动重试"
                }
            } catch {
                controlNotice = "原命令回执尚未确认（\(error.localizedDescription)）；不会重新执行"
            }
        }
    }
    func followRemoteLink(_ link: PCRemoteLink) async {
        guard let id = link.interactionId, let revision = link.interactionRevision,
              !id.isEmpty, !revision.isEmpty else {
            error = "当前链接未能映射到 PC 网页，请在电脑上操作。"
            return
        }
        let action = PCInteractionButton(id: id, label: link.title, revision: revision,
                                         disabled: false, requiresConfirmation: false)
        await interact(action, document: snapshot?.documentId ?? "")
    }
    func interact(_ button: PCInteractionButton, document: String) async {
        guard online, !busy, actionPending == nil, let c = connection, let id = sessionID, let snap = snapshot, snap.documentId == document else { error = STError(code: "pc_route_changed").localizedDescription; return }
        busy = true; defer { busy = false }
        let pending = STActionPending(id: UUID().uuidString, server: c.identity,
                                      conversation: snap.conversationId, kind: "interaction")
        guard reserveAction(pending.id, kind: "interaction", using: c, snapshot: snap) else { return }
        do {
            let result: STReceipt = try await request("/v1/sessions/\(id)/commands", using: c, body: ["action": "interact", "commandId": pending.id, "documentId": document, "interactionId": button.id, "interactionRevision": button.revision, "confirmed": true])
            if result.state == "failed" || result.result?.status == "interaction_clicked" { actionPending = nil; save() }
            else { status = "操作结果待确认，请核对回执" }
        } catch { self.error = "操作结果待确认；不会重复点击。" }
    }
    func loadEarlier() async {
        guard canLoadHistory, let c = connection, let id = sessionID, let snap = snapshot, let cursor = historyCursor ?? snap.historyCursor else { return }
        historyLoading = true; defer { historyLoading = false }; let generation = epoch
        do {
            var query = URLComponents(); query.queryItems = [URLQueryItem(name: "before", value: cursor), URLQueryItem(name: "documentId", value: snap.documentId)]
            let result: STHistory = try await request("/v1/sessions/\(id)/history?\(query.percentEncodedQuery ?? "")", using: c)
            try current(generation); guard result.documentId == snapshot?.documentId, result.conversationId == snapshot?.conversationId else { return }
            let ids = Set(displayMessages.map(\.id)); older = result.messages.filter { !ids.contains($0.id) } + older
            historyCursor = result.cursor; historyHasMore = result.hasMore && result.cursor != cursor
        } catch { self.error = error.localizedDescription }
    }
}
