import Foundation
import CryptoKit

// Pure state reducer shared by the iOS UI and compiled native regression tests.
struct PCDraftBuffer: Codable {
    var text = ""
    var owner: String?
    var baseHash: String?
    var localEdits = false
    var revision = 0
    var expectedEcho: String?

    mutating func edit(_ value: String, conversation: String?, remoteHash: String?) {
        if !localEdits && expectedEcho == nil { baseHash = remoteHash ?? baseHash }
        if owner == nil { owner = conversation }
        text = value; localEdits = true; revision &+= 1
    }
    mutating func receive(text remote: String, hash: String, conversation: String, blocked: Bool) {
        guard owner == nil || owner == conversation || (!localEdits && text.isEmpty) else { return }
        guard !blocked else { return }
        if let echo = expectedEcho {
            guard echo == hash else { return } // Late snapshot from before our edit.
            expectedEcho = nil
        }
        // First pairing may keep locally typed text only against a confirmed
        // empty PC editor; a preexisting PC draft must not be silently replaced.
        if localEdits && owner == nil && baseHash == nil && remote.isEmpty {
            owner = conversation; baseHash = hash
        }
        guard !localEdits else { return }
        text = remote; baseHash = hash; owner = conversation
    }
    mutating func acknowledged(text sent: String, hash: String, editedAt: Int) {
        baseHash = hash; expectedEcho = hash
        // Typing during an in-flight sync stays local and must not be erased.
        if revision == editedAt && text == sent { localEdits = false }
    }
    mutating func sent(text submitted: String, editedAt: Int) {
        baseHash = PCCompanionPolicy.hash(""); expectedEcho = baseHash
        if revision == editedAt && text == submitted { text = ""; localEdits = false }
    }
    var hasLocalDraft: Bool { localEdits || !text.isEmpty }
    func canSelect(_ conversation: String) -> Bool {
        text.isEmpty || owner == nil || owner == conversation
    }
}

enum PCCompanionPolicy {
    // Home HTTPS is the only production transport. Preserve the saved
    // origin for draft/receipt identity, with no retry or command replay.
    static let defaultEndpoint = "https://chatgpt-pc.781751.xyz:58443"
    static let legacyEndpoint = defaultEndpoint
    static let retiredCloudflareEndpoint = "https://chatgpt-pc.78175132.xyz"
    static func transportOrigin(for origin: URL) -> URL {
        // Only the precise former CF origin is remapped to the home gateway.
        // All other custom/test origins retain their explicit destination.
        origin.absoluteString == retiredCloudflareEndpoint ? URL(string: defaultEndpoint)! : origin
    }
    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func origin(_ text: String) throws -> URL {
        guard var c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", (c.port ?? 443) > 0, (c.port ?? 443) <= 65535 else {
            throw PCCompanionError(code: "invalid_endpoint", status: 400)
        }
        c.path = ""; guard let url = c.url else { throw PCCompanionError(code: "invalid_endpoint", status: 400) }
        return url
    }
    static func retryableRead(_ error: Error) -> Bool {
        if let e = error as? PCCompanionError { return [408, 425, 500, 502, 503, 504].contains(e.status) }
        let e = error as NSError
        return e.domain == NSURLErrorDomain && [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet, NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost].contains(e.code)
    }
    // Mirror only a stop control positively observed on the bound PC page.
    // A generic "running" status is not permission to stop a conversation.
    static func nativeStopTarget(canStop: Bool?, id: String?, hasCapability: Bool) -> String? {
        guard hasCapability, canStop == true, let id, validReceipt(id) else { return nil }
        return id
    }
    static func validReceipt(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{16,100}$", options: .regularExpression) != nil
    }
}

struct PCCompanionError: Error, LocalizedError {
    let code: String
    let status: Int
    var errorDescription: String? {
        let labels = [
            "invalid_endpoint": "请使用不含路径或密钥的 HTTPS 服务地址。",
            "pairing_required": "配对密钥无效，请在 PC 本机配对页重新复制。",
            "invalid_pairing": "请输入 PC 本机配对页中的完整密钥。",
            "pc_offline": "PC 扩展暂时离线，已保留本地答案和草稿。",
            "not_sent": "消息没有发送，草稿仍保留在两端。",
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
            "draft_conflict": "电脑端草稿已变化，已阻止覆盖。请核对两端草稿。",
            "pc_composing": "电脑正在输入法组词，请完成输入后再同步。",
            "pc_busy_or_approval": "PC 正在生成或等待工具授权，请先处理该操作。",
            "workflow_busy": "PC 工作流正在运行，暂不接收远程输入。",
            "session_expired": "连接已过期，将重新连接原会话。",
            "tab_already_paired": "旧连接尚未释放，请稍后重连，不会重发消息。",
            "pc_route_changed": "PC 已切换页面，请重新选择会话。",
            "session_or_route_changed": "PC 已切换或刷新页面，请重新连接。",
            "command_expired": "操作已过期，没有自动重发。",
            "pc_result_unknown": "操作回执未确认，请核对回执，不要重复发送。",
            "other_draft": "另一会话仍有本地草稿。请先复制保存或清空，再切换会话。",
            "connection_changed": "连接已改变，已忽略旧页面的返回结果。",
            "schema_invalid": "PC 返回的数据格式不匹配，请更新客户端或扩展。",
            "redirect_refused": "连接发生重定向，已停止请求以保护配对密钥。"
        ]
        return labels[code] ?? (status == 429 ? "服务暂时限流，自动重连已暂停。" : "连接异常：\(code)")
    }
}
