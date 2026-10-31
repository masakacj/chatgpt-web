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
    var canSend: Bool?; var canStop: Bool?; var stopTargetId: String?
    var pcDraftOccupied: Bool?; var composing: Bool?; var responsePhase: String?
    var interactions: [PCInteractionCard]?; var historyCursor: String?; var hasOlder: Bool?
    var sidebarIndicators: [STSidebarSignal]?
    var model: STPCModel?
}
struct STPCThinking: Codable, Equatable {
    var observed: Bool?
    var effort: String?
    var value: Double?
    var source: String?
    var observedAt: Double?
    var confidence: String?
}
struct STPCModel: Codable, Equatable {
    let available: Bool
    let name: String
    var source: String?
    var thinking: STPCThinking?

    enum CodingKeys: String, CodingKey {
        case available, name, source, thinking
    }

    init(available: Bool, name: String, source: String? = nil, thinking: STPCThinking? = nil) {
        self.available = available
        self.name = name
        self.source = source
        self.thinking = thinking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try container.decode(Bool.self, forKey: .available)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        if let th = try? container.decodeIfPresent(STPCThinking.self, forKey: .thinking) {
            thinking = th
        } else if let boolVal = try? container.decodeIfPresent(Bool.self, forKey: .thinking) {
            thinking = STPCThinking(observed: boolVal, effort: nil, value: nil, source: nil, observedAt: nil, confidence: nil)
        } else {
            thinking = nil
        }
    }
}
struct STModelOption: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    var selected: Bool?
    var submenu: Bool?
    var kind: String?
    var value: Double?
    var description: String?
    var disabled: Bool?
    var selectionEvidence: String?
    var min: Double?
    var max: Double?
    var step: Double?
    var valueText: String?
}
struct STModelCatalog: Decodable {
    let available: Bool
    let current: String
    let options: [STModelOption]
    var effort: String?
    var thinking: STPCThinking?
    var kind: String?
}
struct STModelChoice: Decodable {
    let status: String
    var error: String?
    var model: STPCModel?
    var options: [STModelOption]?
    var submenuOpened: Bool?
    var selectionObserved: Bool?
    var selectionEvidence: String?
}
private struct STUploadResult: Decodable { let status: String; var error: String?; var name: String? }
struct STSidebarSignal: Codable {
    let id: String
    let status: String
    let readState: String
    var activityAt: Double?
    var watermark: String?
    var lastMessageId: String?
}
struct STEnvelope: Decodable {
    let ok: Bool; let sessionId: String; let revision: Int
    var capturedAt: Double?; var routeChanged: Bool?; var tabClosed: Bool?; var snapshot: STSnapshot?
}
struct STProject: Codable, Identifiable { let id: String; let title: String; let collapsed: Bool; let hasMore: Bool }
struct STChat: Codable, Identifiable {
    let id: String; let title: String
    var projectId: String?; var current: Bool?; var status: String?; var readState: String?; var activityAt: Double?
    var watermark: String?
    var lastMessageId: String?
}
struct STLibrary: Decodable {
    var projects: [STProject]?; var chats: [STChat]?; var partial: Bool?; var source: String?
    var hasMore: Bool?; var loading: Bool?; var emptyConfirmed: Bool?; var snapshot: STSnapshot?
}
private struct STHealth: Decodable { let capabilities: [String]? }
private struct STTabs: Decodable { let tabs: [STTab] }

// Read-only recovery: prefer the old tab, otherwise match exactly one
// previously viewed conversation. A brand-new binding with no remembered
// conversation is safe only when the PC offers a single ChatGPT tab.
enum STTabRecovery {
    static func select(_ tabs: [STTab], previousTabId: Int?, conversationId: String?) -> STTab? {
        let valid = tabs.filter { $0.tabId >= 0 }
        if let previousTabId { // The original tab follows PC conversation navigation.
            let same = valid.filter { $0.tabId == previousTabId }
            if same.count == 1 { return same[0] }
        }
        if let conversationId, !conversationId.isEmpty {
            let matching = valid.filter { $0.conversationId == conversationId }
            return matching.count == 1 ? matching[0] : nil
        }
        return valid.count == 1 ? valid[0] : nil
    }
}
private struct STOK: Decodable { let ok: Bool? }
private struct STFailure: Decodable { let error: String }
private struct STResult: Decodable {
    var status: String?
    var error: String?
    var conversationId: String?
    var projectId: String?
    var commandId: String?
    var documentId: String?
    var selectionObserved: Bool?
    var selectionEvidence: String?
    var model: STPCModel?
    var options: [STModelOption]?
    var submenuOpened: Bool?
}
private struct STReceipt: Decodable { let commandId: String; let state: String; var result: STResult? }
private struct STHistory: Decodable { let documentId: String; let conversationId: String; let messages: [PCRemoteMessage]; var cursor: String?; let hasMore: Bool }
struct STActionPending: Codable {
    let id: String; let server: String; let conversation: String
    // Optional to preserve previously stored interaction receipts unchanged.
    var kind: String? = nil
    var stopTargetId: String? = nil
    var documentId: String? = nil
    var optionId: String? = nil
    var targetLabel: String? = nil
    var optionMenuLevel: String? = nil
}
struct STReadAcknowledgement: Codable, Equatable {
    let conversationId: String
    var server: String?
    var activityAt: Double?
    var observedAt: Double?
    var status: String?
    var revision: Int?
    var watermark: String?
    var lastMessageId: String?
}
struct STSaved: Codable {
    var ledger: STDraftLedger; var tabId: Int?; var snapshot: STSnapshot?; var server: String?
    var actionPending: STActionPending?
    var parkedActions: [STActionPending]?
    var verifiedEffort: String?
    var verifiedEffortDocId: String?
    var verifiedEffortConvId: String?
    var readAcknowledgements: [String: STReadAcknowledgement]?
    var scopedReadAcknowledgements: [String: [String: STReadAcknowledgement]]?
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
private struct STRecoveryConfig: Codable {
    let endpoint: String
    let pairingKey: String
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
    @Published var tabs: [STTab] = []
    @Published var projects: [STProject] = []
    @Published var chats: [STChat] = []
    @Published var recentActive: [STChat] = []
    @Published var modelOptions: [STModelOption] = []
    @Published private(set) var modelOptionsLevel = ""
    @Published private(set) var modelOptionsDocumentId = ""
    @Published private(set) var modelOptionsConversationId = ""
    private var modelCatalogGeneration = 0
    @Published var modelPickerLoading = false
    @Published var uploading = false
    @Published var controlNotice: String?
    @Published var snapshot: STSnapshot?
    @Published var older: [PCRemoteMessage] = []
    @Published var text = ""
    @Published private(set) var composerResetToken = 0
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
    @Published private(set) var parkedActions: [String: STActionPending] = [:]
    var hasUnresolvedActionReceipts: Bool { actionPending != nil || !parkedActions.isEmpty }
    @Published private(set) var receiptChecking = false
    // A successful native click is not proof that generation has stopped.
    // Don't expose the same PC Stop control for a second click until it changes.
    @Published private(set) var stopAcknowledgedTarget: String?
    @Published var verifiedEffort: String?
    @Published private(set) var readAcknowledgements: [String: STReadAcknowledgement] = [:]
    private var scopedReadAcknowledgements: [String: [String: STReadAcknowledgement]] = [:]
    private(set) var verifiedEffortDocId: String?
    private(set) var verifiedEffortConvId: String?
    private(set) var selectedTabId: Int?
    // Existing CF settings retain their original local ledger/Keychain identity.
    // Their actual network requests now use the trusted home gateway.
    var retiredCloudflareEndpointRouted: Bool {
        (try? PCCompanionPolicy.origin(endpoint))?.absoluteString == PCCompanionPolicy.retiredCloudflareEndpoint
    }
    private var owner = ""
    private var connection: STConnection?
    private var sessionID: String?
    private var revision = -1
    private var epoch = 0
    private var foreground = true
    private var resuming = false
    private var pollTask: Task<Void, Never>?
    private var receiptRecoveryTasks: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    private func cancelReceiptRecoveryTasks() {
        for item in receiptRecoveryTasks.values { item.task.cancel() }
        receiptRecoveryTasks.removeAll()
    }
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var capabilities = Set<String>()
    private var saveTask: Task<Void, Never>?
    private var historyCursor: String?
    private var historyHasMore: Bool?
    private let redirect = STNoRedirect()
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
    // Phone-local draft always owns explicit Send. A parked PC draft and the
    // remote native button's disabled/IME state are NOT phone-side vetoes.
    // The PC Bridge will temporarily park/restore PC draft and independently
    // reject a real document change, approval gate or concurrent edit race.
    var canSubmit: Bool {
        guard let snap = snapshot else { return false }
        let blockedByPage = ["loading", "waiting", "searching"].contains(snap.status)
        // An UNKNOWN older command must remain queryable, not become a permanent
        // lock on a deliberately edited *different* new message.
        return online && !busy && !loading && !blockedByPage && ledger.canReserve(owner)
    }
    var sendDisabledReason: String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if !online { return "PC 连接未恢复，手机草稿已保留" }
        if busy { return "当前操作正在执行，请稍后发送" }
        guard let snap = snapshot else { return "PC 页面尚未加载，请先选择或重连标签页" }
        if loading || snap.status == "loading" { return "PC 页面加载中，请稍后发送" }
        if snap.status == "waiting" { return "PC 正在等待工具确认；先处理确认再发送" }
        if snap.status == "searching" { return "请先关闭 PC 搜索界面再发送" }
        if !ledger.canReserve(owner) {
            if currentPending != nil {
                return "这条消息结果尚未确认；不要重复发送。核对回执，或编辑成不同的新消息"
            }
            return "手机草稿尚未绑定到当前 PC 对话；请刷新连接"
        }
        return nil
    }
    private var nativeStopTarget: String? {
        guard online, !loading, let snap = snapshot, !snap.conversationId.isEmpty else { return nil }
        return PCCompanionPolicy.nativeStopTarget(canStop: snap.canStop, id: snap.stopTargetId,
                                                   hasCapability: capabilities.contains("native-stop-generation"))
    }
    var showsNativeStop: Bool { nativeStopTarget != nil }
    var canStopGeneration: Bool {
        guard let target = nativeStopTarget else { return false }
        return !busy && actionPending == nil && stopAcknowledgedTarget != target
    }
    var canUpload: Bool { online && !busy && !uploading && !loading && capabilities.contains("mobile-upload") && snapshot != nil && snapshot?.status != "waiting" }
    var canPickModel: Bool { online && !busy && capabilities.contains("model-selection") && snapshot != nil }
    static func parseModelAndEffort(rawName: String) -> (model: String, effort: String?) {
        if rawName.contains(" Thinking · ") {
            let parts = rawName.components(separatedBy: " Thinking · ")
            return (parts[0].trimmingCharacters(in: .whitespaces), parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil)
        }
        if rawName.contains(" · ") {
            let parts = rawName.components(separatedBy: " · ")
            return (parts[0].trimmingCharacters(in: .whitespaces), parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil)
        }
        return (rawName.trimmingCharacters(in: .whitespaces), nil)
    }
    var isThinkingModel: Bool {
        guard let snap = snapshot, let m = snap.model else { return false }
        if m.thinking != nil { return true }
        let parsed = Self.parseModelAndEffort(rawName: m.name)
        if parsed.effort != nil { return true }
        let lower = m.name.lowercased()
        return lower.contains("thinking") || lower.contains("o1") || lower.contains("o3") || lower.contains("o4") || lower.contains("gpt-6")
    }
    var displayedModelName: String {
        guard let snap = snapshot, let m = snap.model else { return "模型" }
        let parsed = Self.parseModelAndEffort(rawName: m.name)
        return parsed.model.isEmpty ? (m.name.isEmpty ? "模型" : m.name) : parsed.model
    }
    var displayedEffortName: String {
        guard let snap = snapshot, let m = snap.model else { return "不适用" }
        guard isThinkingModel else { return "无独立强度/不适用" }
        if let th = m.thinking {
            if th.observed == false || th.confidence == "unconfirmed" {
                return "强度未确认"
            }
            if th.observed == true, let effort = th.effort, !effort.isEmpty {
                return effort
            }
        }
        if let verified = verifiedEffort,
           verifiedEffortDocId == snap.documentId,
           verifiedEffortConvId == snap.conversationId {
            return verified
        }
        if m.thinking == nil {
            let parsed = Self.parseModelAndEffort(rawName: m.name)
            if let pe = parsed.effort, !pe.isEmpty {
                return pe
            }
        }
        return "强度未确认"
    }
    var isEffortUnconfirmed: Bool {
        isThinkingModel && displayedEffortName == "强度未确认"
    }
    var thinking: Bool { snapshot?.responsePhase == "thinking" || snapshot?.status == "running" && snapshot?.messages.last?.role != "assistant" }
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
            endpoint = "https://shared-tab.invalid"; pairingKey = String(repeating: "T", count: 43)
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--shared-fixture-missing-tab") || args.contains("--shared-fixture-multiple-tabs") {
                selectedTabId = nil
            } else if args.contains("--shared-fixture-stale-tab") || args.contains("--shared-fixture-stale-tab-match") {
                selectedTabId = 99
            } else {
                selectedTabId = 7
            }
            if args.contains("--shared-fixture-stale-tab-match") {
                let old = #"{"schema":1,"documentId":"fixture-document-A","conversationId":"11111111-1111-4111-8111-111111111111","title":"测试对话 A","messages":[],"status":"completed","draftHash":""}"#
                snapshot = try? JSONDecoder().decode(STSnapshot.self, from: Data(old.utf8))
            }
            return
        }
        UserDefaults.standard.set(clientID, forKey: "SharedPC.clientID")
        pairingKey = STKeychain.load()
        if let file = stateFile, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(STSaved.self, from: data) {
            ledger = saved.ledger; selectedTabId = saved.tabId; actionPending = saved.actionPending
            parkedActions = Dictionary(uniqueKeysWithValues: (saved.parkedActions ?? []).map { ($0.id, $0) })
            verifiedEffort = saved.verifiedEffort
            verifiedEffortDocId = saved.verifiedEffortDocId
            verifiedEffortConvId = saved.verifiedEffortConvId
            scopedReadAcknowledgements = saved.scopedReadAcknowledgements ?? [:]
            if let legacy = saved.readAcknowledgements, let srv = saved.server, scopedReadAcknowledgements[srv] == nil {
                scopedReadAcknowledgements[srv] = legacy
            }
            if let c = try? config(), saved.server == c.identity {
                snapshot = saved.snapshot
                readAcknowledgements = saved.readAcknowledgements ?? scopedReadAcknowledgements[c.identity] ?? [:]
                if let snap = snapshot { owner = ownerKey(snap, c); text = ledger.draft(owner).text }
                status = "本地快照 · 正在连接 PC"
            }
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
    func exportRecoveryConfig() -> Data? {
        guard !fixture, let c = try? config(), STKeychain.load() == c.key else { return nil }
        return try? JSONEncoder().encode(STRecoveryConfig(endpoint: c.origin.absoluteString,
                                                           pairingKey: c.key))
    }

    func importRecoveryConfig(_ data: Data) -> Bool {
        guard !fixture, !busy, !online,
              let config = try? JSONDecoder().decode(STRecoveryConfig.self, from: data),
              config.pairingKey.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              let origin = try? PCCompanionPolicy.origin(config.endpoint) else { return false }
        do { try STKeychain.save(config.pairingKey) }
        catch { return false }
        endpoint = origin.absoluteString
        pairingKey = config.pairingKey
        UserDefaults.standard.set(endpoint, forKey: "PCCompanion.endpoint")
        tabs = []
        needsSettings = true
        return true
    }

    private func ownerKey(_ s: STSnapshot, _ c: STConnection) -> String { c.identity + "|" + (s.conversationId.isEmpty ? "new:" + (s.projectId ?? "") : s.conversationId) }
    @discardableResult private func save() -> Bool {
        if fixture { return true }
        guard let file = stateFile else { return false }
        do {
            let parent = file.deletingLastPathComponent(); try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            var directory = parent; var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
            let saved = STSaved(ledger: ledger, tabId: selectedTabId, snapshot: snapshot, server: connection?.identity ?? (try? config().identity), actionPending: actionPending, parkedActions: Array(parkedActions.values), verifiedEffort: verifiedEffort, verifiedEffortDocId: verifiedEffortDocId, verifiedEffortConvId: verifiedEffortConvId, readAcknowledgements: readAcknowledgements, scopedReadAcknowledgements: scopedReadAcknowledgements)
            try JSONEncoder().encode(saved).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); return true
        } catch { self.error = STError(code: "local_storage_failed").localizedDescription; return false }
    }
    private func saveSoon() {
        saveTask?.cancel(); saveTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 300_000_000); guard !Task.isCancelled else { return }; self?.save() }
    }
    func edited(_ value: String) { text = value; ledger.edit(owner, text: value); saveSoon() }
    private func request<T: Decodable>(_ path: String, using c: STConnection, body: [String: Any]? = nil, method: String? = nil) async throws -> T {
        let transportOrigin = PCCompanionPolicy.transportOrigin(for: c.origin)
        guard path.hasPrefix("/v1/"), !path.contains("\\"), let url = URL(string: path, relativeTo: transportOrigin)?.absoluteURL,
              url.host == transportOrigin.host, url.port == transportOrigin.port, url.scheme == "https" else { throw URLError(.badURL) }
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
    private func current(_ generation: Int) throws { guard epoch == generation, foreground, !Task.isCancelled else { throw CancellationError() } }
    func loadTabs() async {
        guard !busy else { return }; busy = true; defer { busy = false }; error = nil
        do {
            let c = try config()
            if connection?.identity != c.identity {
                readAcknowledgements = scopedReadAcknowledgements[c.identity] ?? [:]
            }
            let health: STHealth = try await request("/v1/health", using: c)
            capabilities = Set(health.capabilities ?? [])
            guard health.capabilities?.contains("shared-tab-v1") == true else { throw STError(code: "shared_bridge_required") }
            let value: STTabs = try await request("/v1/tabs?shared=1", using: c); tabs = value.tabs
            if !fixture {
                try STKeychain.save(c.key)
                UserDefaults.standard.set(c.origin.absoluteString, forKey: "PCCompanion.endpoint")
                if let backup = exportRecoveryConfig() {
                    Task { await ConfigRecovery.uploadSaved(.mirror, data: backup) }
                }
            }
            status = tabs.isEmpty ? "PC 没有可绑定的 ChatGPT 页面" : "选择要与手机共用的 PC 标签页"
        } catch { self.error = error.localizedDescription }
    }
    func bind(_ tab: STTab) async {
        guard !busy else { return }; busy = true; defer { busy = false }; error = nil
        save()
        do {
            let c = try config()
            if connection?.identity != c.identity {
                readAcknowledgements = scopedReadAcknowledgements[c.identity] ?? [:]
            }
            await disconnectSession(); selectedTabId = tab.tabId; connection = c; foreground = true; try await subscribe(using: c); needsSettings = false; startPolling();
        }
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
        if envelope.revision == revision && envelope.routeChanged != true && envelope.tabClosed != true && online &&
           !loading && envelope.snapshot?.status == snapshot?.status &&
           envelope.snapshot?.documentId == snapshot?.documentId &&
           envelope.snapshot?.conversationId == snapshot?.conversationId { return }
        revision = envelope.revision
        if envelope.tabClosed == true { online = false; loading = false; snapshot = nil; status = "绑定标签页已关闭"; needsSettings = true; return }
        if envelope.routeChanged == true && envelope.snapshot == nil { loading = true; snapshot = nil; older = []; status = "PC 正在切换对话"; return }
        guard let fresh = envelope.snapshot else { return }
        try display(fresh, using: c)
    }
    // Navigation returns a PC-observed snapshot directly. Display it immediately
    // instead of waiting for a later cached session GET to catch up.
    private func display(_ fresh: STSnapshot, using c: STConnection) throws {
        // A mounted long conversation can legitimately contain more than 24 turns.
        // Bound the payload without rejecting the 30-message native fixture or
        // real currently mounted history. LazyVStack keeps rendering demand-led.
        guard fresh.schema == 1, fresh.sharedTab == true, fresh.messages.count <= 80 else { throw STError(code: "schema_invalid") }
        if snapshot?.documentId != fresh.documentId || snapshot?.conversationId != fresh.conversationId {
            if let previous = actionPending,
               previous.conversation != fresh.conversationId || previous.documentId != fresh.documentId {
                // The in-flight command remains queryable, but no longer owns B's controls.
                parkedActions[previous.id] = previous
                actionPending = nil
            }
            if actionPending == nil, let returned = parkedActions.values.first(where: {
                $0.server == c.identity && $0.conversation == fresh.conversationId &&
                ($0.documentId == nil || $0.documentId == fresh.documentId)
            }) {
                actionPending = returned
                parkedActions.removeValue(forKey: returned.id)
            }
            // Result/option menus belong to the old PC document, never the new chat.
            modelCatalogGeneration += 1
            modelPickerLoading = false
            modelOptions = []
            modelOptionsLevel = ""
            modelOptionsDocumentId = ""
            modelOptionsConversationId = ""
            if controlNotice?.contains("选择结果") == true { controlNotice = nil }
            older = []; historyCursor = nil; historyHasMore = nil
            verifiedEffort = nil; verifiedEffortDocId = nil; verifiedEffortConvId = nil
        }
        let prevModel = displayedModelName
        let newParsed = Self.parseModelAndEffort(rawName: fresh.model?.name ?? "")
        if prevModel != "模型" && !prevModel.isEmpty && !newParsed.model.isEmpty && newParsed.model != prevModel {
            verifiedEffort = nil; verifiedEffortDocId = nil; verifiedEffortConvId = nil
        }
        if let th = fresh.model?.thinking {
            if th.observed == true, let effort = th.effort, !effort.isEmpty {
                verifiedEffort = effort
                verifiedEffortDocId = fresh.documentId
                verifiedEffortConvId = fresh.conversationId
            } else if th.observed == false || th.confidence == "unconfirmed" {
                verifiedEffort = nil; verifiedEffortDocId = nil; verifiedEffortConvId = nil
            }
        } else if let parsedEffort = newParsed.effort, !parsedEffort.isEmpty {
            verifiedEffort = parsedEffort
            verifiedEffortDocId = fresh.documentId
            verifiedEffortConvId = fresh.conversationId
        } else {
            // A fresh PC snapshot without native effort evidence cannot
            // confirm a previously selected value after a PC-side change.
            verifiedEffort = nil; verifiedEffortDocId = nil; verifiedEffortConvId = nil
        }
        let newOwner = ownerKey(fresh, c)
        let waitingForNewReceipt = busy && currentPending?.temporary == true && !fresh.conversationId.isEmpty
        if newOwner != owner && !waitingForNewReceipt {
            // edited() persisted this draft; a stale editor must not undo a confirmed ledger clear.
            owner = newOwner; text = ledger.draft(owner).text
        } else if newOwner == owner && text != ledger.draft(owner).text {
            text = ledger.draft(owner).text
            if text.isEmpty { composerResetToken += 1 }
        }
        if let acknowledged = stopAcknowledgedTarget,
           fresh.documentId != snapshot?.documentId || fresh.canStop != true || fresh.stopTargetId != acknowledged {
            stopAcknowledgedTarget = nil
            if controlNotice == "已点击 PC 中止控件，等待网页确认停止" { controlNotice = nil }
        }
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
                if let act = marker.activityAt { chat.activityAt = act }
                if let wm = marker.watermark { chat.watermark = wm }
                if let mid = marker.lastMessageId { chat.lastMessageId = mid }
                return chat
            }
            recentActive = recentActive.map { original in
                guard let marker = byId[original.id] else { return original }
                var chat = original
                chat.status = marker.status
                chat.readState = marker.readState
                if let act = marker.activityAt { chat.activityAt = act }
                if let wm = marker.watermark { chat.watermark = wm }
                if let mid = marker.lastMessageId { chat.lastMessageId = mid }
                return chat
            }
            for marker in indicators {
                if marker.status == "running", var ack = readAcknowledgements[marker.id] {
                    ack.status = "running"
                    readAcknowledgements[marker.id] = ack
                    scopedReadAcknowledgements[c.identity, default: [:]][marker.id] = ack
                }
            }
        }
        if !fresh.conversationId.isEmpty {
            let assistantMsgId = fresh.messages.last(where: { $0.role == "assistant" })?.id
            chats = chats.map { original in
                guard original.id == fresh.conversationId else { return original }
                var chat = original
                if ["completed", "stopped", "error", "waiting", "running"].contains(fresh.status) {
                    chat.status = fresh.status
                }
                if let assistantMsgId {
                    chat.watermark = assistantMsgId
                    chat.lastMessageId = assistantMsgId
                }
                return chat
            }
            recentActive = recentActive.map { original in
                guard original.id == fresh.conversationId else { return original }
                var chat = original
                if ["completed", "stopped", "error", "waiting", "running"].contains(fresh.status) {
                    chat.status = fresh.status
                }
                if let assistantMsgId {
                    chat.watermark = assistantMsgId
                    chat.lastMessageId = assistantMsgId
                }
                return chat
            }
        }
        status = loading ? "PC 页面加载中" : fresh.status == "running" ? "PC 生成中 · 手机可独立发送" : fresh.status == "waiting" ? "PC 等待确认 · 手机草稿已保留" : "与 PC 共用此标签页"
        if ledger.pendingFor(owner) != nil { status += " · 发送回执待确认" }
        // A prior definite busy rejection must not leave an obsolete red alert
        // after the same PC page explicitly reports that composing is possible.
        if fresh.status != "waiting" && error == STError(code: "pc_busy_or_approval").localizedDescription { error = nil }
        saveSoon()
    }
    private func scheduleReconnect() {
        // Long PC conversations can take longer than four short recovery rounds.
        // Reads only; every failed send/receipt remains explicitly reserved.
        guard foreground, reconnectTask == nil, reconnectAttempts < 10 else { return }
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
                    // A transient route/loading snapshot may never bump the
                    // local revision if the extension has finished while a
                    // long-poll awaited the old value. Reconcile by asking the
                    // SAME authenticated PC binding for a fresh, read-only
                    // snapshot; never infer completion from elapsed time.
                    let recovering = self.loading || self.snapshot?.status == "loading"
                    let query = recovering ? "after=-1&refresh=1" : "after=\(self.revision)"
                    let value: STEnvelope = try await self.request("/v1/sessions/\(id)?\(query)", using: c)
                    try self.current(generation); try self.apply(value, using: c); failures = 0
                    if recovering && self.loading {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    }
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
    // A lost/closed Chrome tab ID is not a pairing failure. Read the
    // existing authenticated tab list, never navigate another PC tab.
    private func recoverTab(using c: STConnection, previousTabId: Int?, allowExisting: Bool = false) async throws -> Bool {
        let generation = epoch
        let result: STTabs = try await request("/v1/tabs?shared=1", using: c)
        try current(generation)
        tabs = result.tabs
        if let previousTabId, result.tabs.contains(where: { $0.tabId == previousTabId }), !allowExisting {
            status = "原 PC 标签页仍存在，但连接未恢复；请重新选择"
            needsSettings = true
            return false  // Never switch to a different tab on an ambiguous error.
        }
        guard let target = STTabRecovery.select(result.tabs, previousTabId: previousTabId,
                                                conversationId: snapshot?.conversationId) else {
            status = "请确认要连接的 PC 标签页"
            needsSettings = true
            return false
        }
        selectedTabId = target.tabId
        sessionID = nil
        return true
    }
    private func subscribeRestoringTab(using c: STConnection) async throws -> Bool {
        do {
            try await subscribe(using: c)
            return true
        } catch {
            guard let e = error as? STError,
                  ["invalid_tab", "not_chatgpt_tab", "tab_closed"].contains(e.code) else {
                throw error  // Never replay an ambiguous/timeout subscribe.
            }
            guard try await recoverTab(using: c, previousTabId: selectedTabId) else { return false }
            try await subscribe(using: c)
            return true
        }
    }
    func resume() async {
        foreground = true
        if online {
            // A scene foreground event may happen after a stale loading frame
            // was cached. Refresh the SAME authenticated PC tab immediately,
            // rather than requiring the user to tap "刷新状态".
            if loading { await reconcileLoading() }
            return
        }
        if resuming { return }
        if busy { scheduleReconnect(); return }
        if pairingKey.isEmpty { needsSettings = true; return }
        busy = true; resuming = true; defer { busy = false; resuming = false }; epoch += 1
        status = "PC 连接恢复中 · 本地内容已保留"
        error = nil
        do {
            let c = try config(); connection = c
            let health: STHealth = try await request("/v1/health", using: c)
            capabilities = Set(health.capabilities ?? [])
            guard health.capabilities?.contains("shared-tab-v1") == true else { throw STError(code: "shared_bridge_required") }
            if selectedTabId == nil {
                guard try await recoverTab(using: c, previousTabId: nil) else { return }
            }
            if let id = sessionID {
                do {
                    let result: STEnvelope = try await request("/v1/sessions/\(id)?after=-1", using: c)
                    if result.tabClosed == true {
                        guard try await recoverTab(using: c, previousTabId: selectedTabId,
                                                   allowExisting: true) else { return }
                        _ = try await subscribeRestoringTab(using: c)
                    } else {
                        try apply(result, using: c)
                        online = true
                    }
                } catch {
                    if (error as? STError)?.status == 410 {
                        sessionID = nil
                        _ = try await subscribeRestoringTab(using: c)
                    } else { throw error }
                }
            } else { _ = try await subscribeRestoringTab(using: c) }
            if online {
                needsSettings = false
                reconnectAttempts = 0
                reconnectTask?.cancel(); reconnectTask = nil
                error = nil
                startPolling()
                await checkReceiptsInternal(using: c)
                if let activeId = sessionID {
                    for command in ledger.pending.values where command.server == c.identity {
                        recoverSendReceipt(command.id, using: c, sessionId: activeId, generation: epoch)
                    }
                }
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
        cancelReceiptRecoveryTasks()
        pollTask?.cancel()
        reconnectTask?.cancel(); reconnectTask = nil; reconnectAttempts = 0
        online = false; save(); status = "本地快照"
        if error?.localizedCaseInsensitiveContains("timed out") == true ||
           error?.contains("超时") == true { error = nil }
    }
    private func disconnectSession() async {
        epoch += 1; cancelReceiptRecoveryTasks(); pollTask?.cancel(); online = false; revision = -1
        verifiedEffort = nil; verifiedEffortDocId = nil; verifiedEffortConvId = nil
        let id = sessionID; sessionID = nil
        if let id, let c = connection { let _: STOK? = try? await request("/v1/sessions/\(id)", using: c, method: "DELETE") }
    }
    func disconnect() async { save(); await disconnectSession() }
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
        stopAcknowledgedTarget = nil
        verifiedEffort = nil; verifiedEffortDocId = nil; verifiedEffortConvId = nil
        readAcknowledgements = [:]
        owner = ""; text = ""
        error = nil
        status = "测试通道 · 请复制 PC 13213 的配对密钥"
        needsSettings = true
    }
    private func refresh(using c: STConnection, fromPC: Bool = false) async throws {
        guard let id = sessionID else { return }; let generation = epoch
        // The ordinary cached GET is not enough when a PC Send timed out after
        // a real native click. Explicitly read the SAME bound PC tab, never POST.
        let path = "/v1/sessions/\(id)?after=-1" + (fromPC ? "&refresh=1" : "")
        let value: STEnvelope = try await request(path, using: c)
        try current(generation); try apply(value, using: c)
    }
    private func recoverSendReceipt(_ commandId: String, using c: STConnection,
                                    sessionId: String, generation: Int) {
        guard receiptRecoveryTasks[commandId] == nil else { return }
        let token = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.receiptRecoveryTasks[commandId]?.token == token {
                    self.receiptRecoveryTasks.removeValue(forKey: commandId)
                }
            }
            // Bounded read-only reconciliation. UNKNOWN is never an excuse
            // to submit another compose with the same or a new command ID.
            for delay in [UInt64(500_000_000), 1_500_000_000, 3_000_000_000] {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, self.foreground, self.epoch == generation,
                      self.sessionID == sessionId, self.connection?.identity == c.identity,
                      self.ledger.pending[commandId] != nil else { return }
                try? await self.refresh(using: c, fromPC: true)
                guard !Task.isCancelled, self.epoch == generation,
                      self.connection?.identity == c.identity else { return }
                if let receipt: STReceipt = try? await self.request("/v1/commands/\(commandId)", using: c) {
                    self.resolve(receipt, using: c,
                                 displayOnCurrent: self.foreground && self.epoch == generation && !Task.isCancelled)
                }
            }
        }
        receiptRecoveryTasks[commandId] = (token: token, task: task)
    }
    // Explicit recovery when the PC already finished but the iOS UI is
    // displaying an old "loading" snapshot. This only refreshes the existing
    // paired session; it cannot navigate or submit any user message.
    func reconcileLoading() async {
        guard online, !busy, let c = connection, let id = sessionID else { return }
        let generation = epoch
        do {
            let value: STEnvelope = try await request("/v1/sessions/\(id)?after=-1&refresh=1", using: c)
            try current(generation)
            try apply(value, using: c)
        } catch {
            if generation == epoch {
                status = "PC 状态仍在同步 · 可再次刷新"
                self.error = nil
            }
        }
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
    func open(_ chat: STChat) async {
        if snapshot?.conversationId == chat.id {
            acknowledgeRead(for: chat.id, activityAt: chat.activityAt, status: chat.status)
            return
        }
        await navigate("open", fields: ["targetConversationId": chat.id])
    }
    func newChat(project: STProject? = nil) async { await navigate("new", fields: project.map { ["projectId": $0.id] } ?? [:]) }
    private func navigate(_ action: String, fields: [String: Any]) async {
        guard online, !busy, !libraryLoading, let c = connection, let id = sessionID, let snap = snapshot else { return }
        busy = true; defer { busy = false }; error = nil; save(); let generation = epoch
        do {
            var body: [String: Any] = ["action": action, "commandId": UUID().uuidString, "documentId": snap.documentId]; body.merge(fields) { _, value in value }
            let result: STLibrary = try await request("/v1/sessions/\(id)/actions", using: c, body: body)
            try current(generation)
            // The action response already contains the page observed after the
            // native PC navigation. Only adopt its matching destination; GET
            // reconciliation below still handles any subsequent PC-side change.
            if let fresh = result.snapshot,
               (action != "new" || fresh.conversationId.isEmpty),
               (action != "open" || fresh.conversationId == (fields["targetConversationId"] as? String ?? "")),
               (action != "new" || fresh.documentId != snap.documentId) {
                try display(fresh, using: c)
                if action == "open", let targetId = fields["targetConversationId"] as? String, fresh.conversationId == targetId {
                    let matchingChat = chats.first { $0.id == targetId } ?? recentActive.first { $0.id == targetId }
                    acknowledgeRead(for: targetId, activityAt: matchingChat?.activityAt, status: fresh.status)
                }
            }
            try await refresh(using: c)
            if action == "open", let targetId = fields["targetConversationId"] as? String, snapshot?.conversationId == targetId {
                let matchingChat = chats.first { $0.id == targetId } ?? recentActive.first { $0.id == targetId }
                acknowledgeRead(for: targetId, activityAt: matchingChat?.activityAt, status: snapshot?.status)
            }
        } catch { self.error = error.localizedDescription; try? await refresh(using: c) }
    }
    func acknowledgeRead(for conversationId: String, activityAt: Double? = nil, status: String? = nil, watermark: String? = nil) {
        guard !conversationId.isEmpty else { return }
        let currentConn = connection ?? (try? config())
        let serverIdentity = currentConn?.identity ?? "local"

        let matchingChat = chats.first { $0.id == conversationId } ?? recentActive.first { $0.id == conversationId }
        let effectiveActivity = activityAt ?? matchingChat?.activityAt
        let effectiveStatus = status ?? matchingChat?.status
        let effectiveWatermark = watermark ?? matchingChat?.watermark ?? matchingChat?.lastMessageId ??
            (snapshot?.conversationId == conversationId ? (snapshot?.messages.last(where: { $0.role == "assistant" })?.id ?? snapshot?.messages.last?.id ?? snapshot?.documentId) : nil)

        let ack = STReadAcknowledgement(
            conversationId: conversationId,
            server: serverIdentity,
            activityAt: effectiveActivity,
            observedAt: Date().timeIntervalSince1970,
            status: effectiveStatus,
            revision: revision,
            watermark: effectiveWatermark,
            lastMessageId: matchingChat?.lastMessageId
        )
        readAcknowledgements[conversationId] = ack
        scopedReadAcknowledgements[serverIdentity, default: [:]][conversationId] = ack

        // Bounded <= 200 items: evict oldest
        if readAcknowledgements.count > 200 {
            let sortedByTime = readAcknowledgements.sorted {
                ($0.value.observedAt ?? 0) < ($1.value.observedAt ?? 0)
            }
            for item in sortedByTime.prefix(readAcknowledgements.count - 200) {
                readAcknowledgements.removeValue(forKey: item.key)
            }
        }
        if var serverAcks = scopedReadAcknowledgements[serverIdentity], serverAcks.count > 200 {
            let sortedByTime = serverAcks.sorted {
                ($0.value.observedAt ?? 0) < ($1.value.observedAt ?? 0)
            }
            for item in sortedByTime.prefix(serverAcks.count - 200) {
                serverAcks.removeValue(forKey: item.key)
            }
            scopedReadAcknowledgements[serverIdentity] = serverAcks
        }

        chats = chats.map { original in
            guard original.id == conversationId else { return original }
            var updated = original
            updated.readState = "read"
            return updated
        }
        recentActive = recentActive.map { original in
            guard original.id == conversationId else { return original }
            var updated = original
            updated.readState = "read"
            return updated
        }
        saveSoon()
    }
    func isChatUnread(_ chat: STChat) -> Bool {
        guard chat.readState != "unknown", chat.readState == "unread" else { return false }
        // Binding or refreshing a tab is not a positive *read* action.
        // Clear an observed unread state only after an explicit open/ACK,
        // so initial project/sidebar unread and newly arrived replies survive.
        guard let ack = readAcknowledgements[chat.id] else {
            return true
        }
        if let ackServer = ack.server, let conn = connection ?? (try? config()), ackServer != conn.identity {
            return true
        }
        // 1. Higher activityAt timestamp than acknowledged
        if let newAct = chat.activityAt, let oldAct = ack.activityAt, newAct > oldAct {
            return true
        }
        // 2. Newer positive observed assistant event watermark / messageId
        if let newWm = chat.watermark, let oldWm = ack.watermark, !newWm.isEmpty, newWm != oldWm {
            return true
        }
        if let newMid = chat.lastMessageId, let oldMid = ack.lastMessageId, !newMid.isEmpty, newMid != oldMid {
            return true
        }
        // 3. State transition: acknowledged while running, now completed with positive unread
        if ack.status == "running" && chat.status == "completed" {
            return true
        }
        // Suppress stale PC unread replay; lacking newer-turn evidence must not invent unread
        return false
    }
    func isChatPendingRefresh(_ chat: STChat) -> Bool {
        guard chat.readState != "unknown", chat.readState == "unread" else { return false }
        guard let ack = readAcknowledgements[chat.id] else {
            return false
        }
        if let ackServer = ack.server, let conn = connection ?? (try? config()), ackServer != conn.identity {
            return false
        }
        if isChatUnread(chat) {
            return false
        }
        return true
    }
    func effectiveChatStatus(_ chat: STChat) -> String {
        if chat.id == snapshot?.conversationId,
           let live = snapshot?.status,
           ["completed", "stopped", "error", "waiting", "running"].contains(live) {
            return live
        }
        return chat.status ?? "unknown"
    }
    func projectTitle(for projectId: String?) -> String? {
        guard let projectId else { return nil }
        return projects.first { $0.id == projectId }?.title
    }
    var allObservedChats: [STChat] {
        var map: [String: STChat] = [:]
        for chat in chats + recentActive {
            if var existing = map[chat.id] {
                if (existing.status == nil || existing.status == "unknown") && chat.status != nil && chat.status != "unknown" {
                    existing.status = chat.status
                }
                if (existing.readState == nil || existing.readState == "unknown") && chat.readState != nil && chat.readState != "unknown" {
                    existing.readState = chat.readState
                }
                if existing.projectId == nil && chat.projectId != nil {
                    existing.projectId = chat.projectId
                }
                if (chat.activityAt ?? 0) > (existing.activityAt ?? 0) {
                    existing.activityAt = chat.activityAt
                }
                map[chat.id] = existing
            } else {
                map[chat.id] = chat
            }
        }
        if let snap = snapshot, !snap.conversationId.isEmpty {
            if var boundChat = map[snap.conversationId] {
                if ["running", "waiting", "error", "completed", "stopped"].contains(snap.status) {
                    boundChat.status = snap.status
                }
                map[snap.conversationId] = boundChat
            } else {
                map[snap.conversationId] = STChat(id: snap.conversationId, title: snap.title, projectId: snap.projectId, status: snap.status, readState: "read", activityAt: nil)
            }
        }
        return Array(map.values)
    }
    var runningChats: [STChat] {
        var seenIds = Set<String>()
        var list: [STChat] = []
        for chat in allObservedChats {
            let st = effectiveChatStatus(chat)
            guard st != "unknown", st == "running" else { continue }
            if !seenIds.contains(chat.id) {
                seenIds.insert(chat.id)
                list.append(chat)
            }
        }
        return list.sorted { ($0.activityAt ?? 0) > ($1.activityAt ?? 0) }
    }
    var unreadChats: [STChat] {
        let runningIds = Set(runningChats.map(\.id))
        var seenIds = Set<String>()
        var list: [STChat] = []
        for chat in allObservedChats {
            guard !runningIds.contains(chat.id) else { continue }
            guard chat.readState != "unknown", isChatUnread(chat) else { continue }
            if !seenIds.contains(chat.id) {
                seenIds.insert(chat.id)
                list.append(chat)
            }
        }
        return list.sorted { ($0.activityAt ?? 0) > ($1.activityAt ?? 0) }
    }
    var prioritizedRecentActive: [STChat] {
        let priorityIds = Set(runningChats.map(\.id) + unreadChats.map(\.id))
        var seenIds = Set<String>()
        var list: [STChat] = []
        for chat in recentActive {
            guard !priorityIds.contains(chat.id) else { continue }
            if !seenIds.contains(chat.id) {
                seenIds.insert(chat.id)
                list.append(chat)
            }
        }
        return list
    }
    func loadModelOptions(menuLevel: String = "model") async {
        guard menuLevel == "model" || menuLevel == "effort" else { return }
        guard canPickModel, let c = connection, let id = sessionID, let snap = snapshot else { return }
        modelCatalogGeneration += 1
        let catalogGeneration = modelCatalogGeneration
        modelOptionsLevel = menuLevel
        modelOptionsDocumentId = snap.documentId
        modelOptionsConversationId = snap.conversationId
        modelOptions = []
        controlNotice = nil
        modelPickerLoading = true
        defer { if modelCatalogGeneration == catalogGeneration { modelPickerLoading = false } }
        do {
            let value: STModelCatalog = try await request("/v1/sessions/\(id)/actions", using: c,
                body: ["action": "model_catalog", "menuLevel": menuLevel,
                       "commandId": UUID().uuidString, "documentId": snap.documentId])
            guard modelCatalogGeneration == catalogGeneration && modelOptionsLevel == menuLevel &&
                  snapshot?.documentId == snap.documentId && snapshot?.conversationId == snap.conversationId else { return }
            modelOptions = value.available ? value.options : []
            let selectedStep = modelOptions.first { $0.kind == "slider" && $0.selected == true && $0.disabled != true }
            if let th = value.thinking, th.observed == true, let eff = th.effort, !eff.isEmpty {
                verifiedEffort = eff
                verifiedEffortDocId = snap.documentId
                verifiedEffortConvId = snap.conversationId
            } else if let step = selectedStep, !step.label.isEmpty {
                // Native selected slider option is PC evidence, unlike
                // the previous locally cached selected value.
                verifiedEffort = step.label
                verifiedEffortDocId = snap.documentId
                verifiedEffortConvId = snap.conversationId
            } else {
                verifiedEffort = nil; verifiedEffortDocId = nil; verifiedEffortConvId = nil
            }
            if modelOptions.isEmpty { controlNotice = "PC 当前未提供可镜像的模型或思考选项" }
        } catch {
            if modelCatalogGeneration == catalogGeneration { controlNotice = error.localizedDescription }
        }
    }
    func chooseModel(_ option: STModelOption, value: Double? = nil) async {
        guard canPickModel, let c = connection, let id = sessionID, let snap = snapshot else { return }
        guard actionPending == nil else {
            controlNotice = "上一操作尚未确认，请等待 PC 确认或核对回执"
            return
        }
        guard !modelPickerLoading, modelOptionsDocumentId == snap.documentId,
              modelOptionsConversationId == snap.conversationId,
              ["model", "effort"].contains(modelOptionsLevel),
              modelOptions.contains(where: { $0.id == option.id && $0.disabled != true }) else {
            controlNotice = "PC 选项已变化，请重新读取当前菜单"
            return
        }
        modelCatalogGeneration += 1 // A user selection invalidates old catalog requests.
        let selectionGeneration = modelCatalogGeneration
        let selectionLevel = modelOptionsLevel
        modelPickerLoading = true
        defer { if modelCatalogGeneration == selectionGeneration { modelPickerLoading = false } }
        let commandId = UUID().uuidString
        let pending = STActionPending(id: commandId, server: c.identity, conversation: snap.conversationId,
                                      kind: "model_select", stopTargetId: nil, documentId: snap.documentId,
                                      optionId: option.id, targetLabel: option.label,
                                      optionMenuLevel: modelOptionsLevel)
        actionPending = pending
        guard save() else {
            actionPending = nil
            controlNotice = "保存操作意图失败，未提交选择"
            return
        }
        do {
            var body: [String: Any] = [
                "action": "model_select",
                "commandId": commandId,
                "documentId": snap.documentId,
                "optionId": option.id
            ]
            if let targetValue = value ?? option.value { body["value"] = targetValue }
            let result: STModelChoice = try await request("/v1/sessions/\(id)/actions", using: c, body: body)
            if snapshot?.documentId != snap.documentId || snapshot?.conversationId != snap.conversationId ||
               modelCatalogGeneration != selectionGeneration || modelOptionsLevel != selectionLevel {
                // Another route or newer catalog took ownership while this
                // exact PC click was in flight; settle its identity only.
                // Do not apply stale model options or notice.
                if result.status == "option_clicked" || result.status == "not_selected" {
                    if actionPending?.id == commandId { actionPending = nil }
                    parkedActions.removeValue(forKey: commandId)
                    save()
                }
                return
            }
            guard result.status == "option_clicked" else {
                actionPending = nil; save()
                throw STError(code: result.error ?? "model_option_changed")
            }
            if result.submenuOpened == true {
                actionPending = nil; save()
                modelOptionsLevel = "effort"
                modelOptionsDocumentId = snap.documentId
                modelOptionsConversationId = snap.conversationId
                modelOptions = result.options ?? []
                controlNotice = "请选择 PC 网页实际提供的细分档位"
                return
            }
            // The PC confirmed this click. Keep uncertainty in the notice, not in a
            // pending command that disables every later explicit user choice.
            actionPending = nil; save()
            if let returnedOptions = result.options, !returnedOptions.isEmpty {
                modelOptions = returnedOptions
            }
            let sameDocAndConv = (snapshot?.documentId == snap.documentId && snapshot?.conversationId == snap.conversationId)
            if result.selectionObserved == true && sameDocAndConv {
                actionPending = nil
                if let freshModel = result.model {
                    if let th = freshModel.thinking, th.observed == true, let eff = th.effort, !eff.isEmpty {
                        verifiedEffort = eff
                        verifiedEffortDocId = snap.documentId
                        verifiedEffortConvId = snap.conversationId
                    } else if freshModel.thinking?.observed == false || freshModel.thinking?.confidence == "unconfirmed" {
                        verifiedEffort = nil
                        verifiedEffortDocId = nil
                        verifiedEffortConvId = nil
                    } else if freshModel.thinking == nil {
                        let parsed = Self.parseModelAndEffort(rawName: freshModel.name)
                        if let pe = parsed.effort, !pe.isEmpty {
                            verifiedEffort = pe
                            verifiedEffortDocId = snap.documentId
                            verifiedEffortConvId = snap.conversationId
                        }
                    }
                } else if option.kind == "effort" || option.kind == "slider" || option.label.contains("High") || option.label.contains("Medium") || option.label.contains("Instant") {
                    let parsed = Self.parseModelAndEffort(rawName: option.label)
                    verifiedEffort = parsed.effort ?? option.label
                    verifiedEffortDocId = snap.documentId
                    verifiedEffortConvId = snap.conversationId
                }
                controlNotice = "已在 PC 网页选择：\(option.label)"
                save()
                try? await refresh(using: c)
            } else if result.selectionObserved == false {
                controlNotice = "未确认 PC 已切换选项，请核对电脑网页"
                status = "选择结果待确认 · 不会自动重试"
                save()
                try? await refresh(using: c)
            } else {
                controlNotice = "选择结果待确认；缺少网页生效证据。请核对 PC 页面。"
                status = "选择结果待确认 · 不会自动重试"
                save()
                try? await refresh(using: c)
            }
        } catch {
            if snapshot?.documentId == snap.documentId && snapshot?.conversationId == snap.conversationId &&
               modelCatalogGeneration == selectionGeneration && modelOptionsLevel == selectionLevel {
                controlNotice = "选择结果待确认；不会自动重试。请核对 PC 页面。"
                status = "选择结果待确认 · 不会自动重试"
            }
            save()
        }
    }
    func upload(_ data: Data, filename: String, mimeType: String) async {
        guard canUpload, let c = connection, let id = sessionID, let snap = snapshot else { return }
        guard !data.isEmpty && data.count <= 10 * 1024 * 1024 else {
            controlNotice = "附件须小于 10 MB，草稿仍已保留"; return
        }
        uploading = true; defer { uploading = false }; controlNotice = "正在交给 PC 网页附件控件…"
        let safeName = String(filename.replacingOccurrences(of: #"[\\/\x00-\x1f]"#,
                         with: "_", options: .regularExpression).prefix(180))
        do {
            let result: STUploadResult = try await request("/v1/sessions/\(id)/uploads", using: c,
                body: ["uploadId": UUID().uuidString, "documentId": snap.documentId,
                       "name": safeName, "mimeType": mimeType, "base64": data.base64EncodedString()])
            controlNotice = result.status == "handed_to_pc" ?
                "已交给 PC 网页附件控件，请确认处理完成后发送" :
                "未确认 PC 附件上传：\(result.error ?? result.status)，请先核对 PC"
        } catch {
            controlNotice = "附件结果未确认：\(error.localizedDescription)。不会自动重传"
        }
    }
    func send() async {
        guard canSubmit, let c = connection, let id = sessionID, let snap = snapshot else { return }
        busy = true; defer { busy = false }; error = nil
        let generation = epoch, submittedOwner = owner
        var submittedID: String?
        do {
            let command = try ledger.reserve(owner, server: c.identity, temporary: snap.conversationId.isEmpty)
            guard save() else { ledger.definitelyNotSent(command.id); throw STError(code: "local_storage_failed") }
            submittedID = command.id
            var body: [String: Any] = ["commandId": command.id, "action": "compose", "documentId": snap.documentId, "baseDraftHash": snap.draftHash, "text": command.text]
            if let project = snap.projectId { body["projectId"] = project }
            let receipt: STReceipt = try await request("/v1/sessions/\(id)/commands", using: c, body: body)
            resolve(receipt, using: c, displayOnCurrent: epoch == generation && foreground && !Task.isCancelled)
            try current(generation); try? await refresh(using: c, fromPC: true)
        } catch {
            let failure = error
            // A lost POST response may follow a confirmed Send. Query the original
            // command ID once; never replay compose or infer success from page text.
            if let submittedID, ledger.pending[submittedID] != nil,
               let receipt: STReceipt = try? await request("/v1/commands/\(submittedID)", using: c) {
                resolve(receipt, using: c, displayOnCurrent: epoch == generation && foreground && !Task.isCancelled)
            }
            // A may have sent while the PC switched to B. Do not paint A's
            // failure or pending status over B's composer.
            if epoch == generation && foreground && !Task.isCancelled &&
               owner == submittedOwner && snapshot?.documentId == snap.documentId &&
               snapshot?.conversationId == snap.conversationId && connection?.identity == c.identity {
                if let submittedID, ledger.pending[submittedID] != nil {
                    self.error = failure.localizedDescription
                    status = "发送结果待确认 · 不会自动重发"
                } else if submittedID == nil { self.error = failure.localizedDescription }
            }
            if epoch == generation && foreground && !Task.isCancelled &&
               sessionID == id && connection?.identity == c.identity {
                try? await refresh(using: c, fromPC: true)
                if let submittedID, ledger.pending[submittedID] != nil,
                   let receipt: STReceipt = try? await request("/v1/commands/\(submittedID)", using: c) {
                    resolve(receipt, using: c, displayOnCurrent: epoch == generation && foreground && !Task.isCancelled)
                }
            }
            save()
        }
        if let submittedID, ledger.pending[submittedID] != nil &&
           epoch == generation && foreground && !Task.isCancelled &&
           sessionID == id && connection?.identity == c.identity {
            recoverSendReceipt(submittedID, using: c, sessionId: id, generation: generation)
        }
    }
    // One explicit tap maps to ONE PC-native Stop button; never infer a stop
    // from generic in_progress status, and never replay an uncertain click.
    func stopGeneration() async {
        guard canStopGeneration, let target = nativeStopTarget,
              let c = connection, let id = sessionID, let snap = snapshot else { return }
        let pending = STActionPending(id: UUID().uuidString, server: c.identity,
                                      conversation: snap.conversationId,
                                      kind: "stop", stopTargetId: target)
        actionPending = pending
        guard save() else {
            actionPending = nil
            error = STError(code: "local_storage_failed").localizedDescription
            return
        }
        busy = true; defer { busy = false }
        error = nil
        do {
            let receipt: STReceipt = try await request("/v1/sessions/\(id)/commands", using: c,
                body: ["action": "stop", "commandId": pending.id,
                       "documentId": snap.documentId, "conversationId": snap.conversationId,
                       "stopTargetId": target, "confirmed": true])
            resolveAction(receipt, using: c)
            // The command receipt proves a physical click, NOT that the
            // official generation finished. Refresh native state separately.
            try? await refresh(using: c)
        } catch {
            if snapshot?.conversationId == snap.conversationId &&
               snapshot?.documentId == snap.documentId && connection?.identity == c.identity {
                self.error = "中止结果待确认；不会再次点击。请核对回执或 PC 页面。"
                status = "中止结果待确认 · 不会自动重试"
            }
            save()
        }
    }
    private func resolveAction(_ receipt: STReceipt, using c: STConnection) {
        let parked = parkedActions[receipt.commandId]
        guard let pending = (actionPending?.id == receipt.commandId ? actionPending : parked),
              pending.server == c.identity else { return }
        let receiptScopeMatches = (receipt.result?.documentId == nil || receipt.result?.documentId == pending.documentId) &&
                                  (receipt.result?.conversationId == nil || receipt.result?.conversationId == pending.conversation)
        if parked != nil {
            // The command's durable terminal state settles A, but never
            // asserts a model/interaction result in currently visible B.
            if receiptScopeMatches && (receipt.state == "failed" || receipt.state == "done") {
                parkedActions.removeValue(forKey: receipt.commandId)
                save()
            }
            return
        }
        // A receipt with a foreign, explicitly observed route must never
        // unlock or confirm the current pending action, even if commandId matches.
        guard receiptScopeMatches else { return }
        if snapshot?.conversationId != pending.conversation ||
           (pending.documentId != nil && snapshot?.documentId != pending.documentId) {
            // Reconcile a terminal, ID-bound old receipt without changing the
            // current conversation's model UI, notices, draft or Send state.
            if receiptScopeMatches && (receipt.state == "failed" ||
               (receipt.state == "done" && ["option_clicked", "not_selected", "interaction_clicked", "stop_clicked"].contains(receipt.result?.status ?? ""))) {
                actionPending = nil; save()
            }
            return
        }
        if receipt.state == "failed" {
            actionPending = nil
            error = STError(code: receipt.result?.error ?? "pc_operation_failed").localizedDescription
        } else if receipt.state == "done" && receipt.result?.status == "stop_clicked" && pending.kind == "stop" {
            if snapshot?.conversationId == pending.conversation {
                stopAcknowledgedTarget = pending.stopTargetId
                controlNotice = "已点击 PC 中止控件，等待网页确认停止"
            }
            actionPending = nil
            status = "已点击 PC 中止 · 等待原生状态"
        } else if receipt.state == "done" && receipt.result?.status == "interaction_clicked" &&
                  pending.kind != "stop" && pending.kind != "model_select" {
            actionPending = nil
        } else if receipt.state == "done" && pending.kind == "model_select" {
            let res = receipt.result
            let matchesScope = (res?.documentId == nil || res?.documentId == pending.documentId) &&
                               (res?.conversationId == nil || res?.conversationId == pending.conversation) &&
                               (snapshot?.documentId == pending.documentId && snapshot?.conversationId == pending.conversation)
            if matchesScope && (res?.status == "option_clicked" || res?.status == "not_selected") {
                actionPending = nil // Only a matching terminal receipt releases this action.
            }
            if res?.status == "option_clicked" && res?.selectionObserved == true && matchesScope {
                actionPending = nil
                if let freshModel = res?.model {
                    if let th = freshModel.thinking, th.observed == true, let eff = th.effort, !eff.isEmpty {
                        verifiedEffort = eff
                        verifiedEffortDocId = pending.documentId
                        verifiedEffortConvId = pending.conversation
                    } else if freshModel.thinking?.observed == false || freshModel.thinking?.confidence == "unconfirmed" {
                        verifiedEffort = nil
                        verifiedEffortDocId = nil
                        verifiedEffortConvId = nil
                    }
                }
                controlNotice = "已在 PC 网页选择：\(pending.targetLabel ?? "所选项目")"
                status = "与 PC 共用此标签页"
            } else if res?.status == "option_clicked" && res?.selectionObserved == false {
                controlNotice = "未确认 PC 已切换选项，请核对电脑网页"
                status = "选择结果待确认 · 不会自动重试"
            } else if res?.status == "option_clicked" {
                controlNotice = "选择结果待确认；缺少网页生效证据。请核对 PC 页面。"
                status = "选择结果待确认 · 不会自动重试"
            } else {
                status = "选择结果待确认 · 不会自动重试"
            }
        } else {
            status = pending.kind == "stop" ? "中止结果待确认 · 不会自动重试" :
                     pending.kind == "model_select" ? "选择结果待确认 · 不会自动重试" :
                                                     "操作结果待确认 · 不会自动重试"
        }
        save()
    }
    private func resolve(_ receipt: STReceipt, using c: STConnection, displayOnCurrent: Bool = true) {
        guard let command = ledger.pending[receipt.commandId], command.server == c.identity else { return }
        // A stale send still settles its durable ledger, but never changes the
        // current composer after backgrounding, rebinding or moving to B.
        let affectsCurrentConversation = displayOnCurrent && command.owner == owner
        if receipt.state == "done" && receipt.result?.status == "sent_confirmed" {
            let actualOwner = receipt.result?.conversationId.map { c.identity + "|" + $0 }
            ledger.confirmed(command.id, actualOwner: actualOwner)
            if affectsCurrentConversation {
                if command.temporary, let actualOwner { owner = actualOwner }
                text = ledger.draft(owner).text
                if text.isEmpty { composerResetToken += 1 }
                status = ledger.pendingFor(owner) == nil ? "消息已发送" : "新消息已发送 · 另有旧回执待确认"
                error = nil
            }
        } else if receipt.state == "failed" {
            ledger.definitelyNotSent(command.id)
            if affectsCurrentConversation {
                error = STError(code: receipt.result?.error ?? "not_sent").localizedDescription
                status = "确定未发送 · 草稿已保留"
            }
        } else if affectsCurrentConversation {
            status = "发送结果待确认 · 不会自动重发"
        }
        save()
    }
    // A slow receipt lookup for an older chat is read-only. It must never
    // hold the current conversation's global Send/navigation busy lock.
    func checkReceipts() async {
        guard !busy, !receiptChecking, let c = connection else { return }
        receiptChecking = true; defer { receiptChecking = false }
        await checkReceiptsInternal(using: c)
    }
    private func checkReceiptsInternal(using c: STConnection) async {
        let receiptEpoch = epoch
        for command in Array(ledger.pending.values).filter({ $0.server == c.identity }) {
            if let receipt: STReceipt = try? await request("/v1/commands/\(command.id)", using: c) {
                resolve(receipt, using: c, displayOnCurrent: receiptEpoch == epoch && foreground &&
                        !Task.isCancelled && connection?.identity == c.identity)
            }
        }
        for old in Array(parkedActions.values).filter({ $0.server == c.identity }) {
            if let receipt: STReceipt = try? await request("/v1/commands/\(old.id)", using: c) {
                resolveAction(receipt, using: c)
            }
        }
        if let pending = actionPending, pending.server == c.identity,
           let receipt: STReceipt = try? await request("/v1/commands/\(pending.id)", using: c) {
            resolveAction(receipt, using: c)
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
        busy = true; defer { busy = false }; let pending = STActionPending(id: UUID().uuidString,
            server: c.identity, conversation: snap.conversationId, documentId: document)
        actionPending = pending
        guard save() else { actionPending = nil; return }
        do {
            let result: STReceipt = try await request("/v1/sessions/\(id)/commands", using: c, body: ["action": "interact", "commandId": pending.id, "documentId": document, "interactionId": button.id, "interactionRevision": button.revision, "confirmed": true])
            resolveAction(result, using: c)
            // Re-read the PC result after the one confirmed click; never click twice.
            try? await refresh(using: c)
        } catch {
            if snapshot?.conversationId == snap.conversationId &&
               snapshot?.documentId == snap.documentId && connection?.identity == c.identity {
                self.error = "操作结果待确认；不会重复点击。"
            }
            save()
        }
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
