#if DEBUG
import Foundation

// Only installed into the private URLSession under BOTH --ui-testing and
// --pc-companion-network-fixture. No connection to the real PC or real key.
final class PCCompanionTestProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var draft = ""
    private static var sessions = 0
    private static var sends = 0
    private static var polls = 0
    private static var readFailed = false
    private static var expired = false
    private static var receiptID = ""
    private static var sentText = ""
    private static var version = 1
    private var work: DispatchWorkItem?
    private static let firstConversation = "11111111-1111-4111-8111-111111111111"
    private static var conversation = firstConversation
    private static var projectExpanded = false

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        draft = ""; sessions = 0; sends = 0; polls = 0; readFailed = false
        expired = false; receiptID = ""; sentText = ""; version = 1
        conversation = firstConversation; projectExpanded = false
    }
    static var counters: String {
        lock.lock(); defer { lock.unlock() }
        return "发送请求：\(sends)；订阅：\(sessions)；读取：\(polls)"
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "pc-companion.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private func body() -> [String: Any] {
        if let data = request.httpBody { return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
        guard let stream = request.httpBodyStream else { return [:] }
        stream.open(); defer { stream.close() }; var data = Data(); var bytes = [UInt8](repeating: 0, count: 2048)
        while stream.hasBytesAvailable {
            let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(bytes, count: n)
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    private static func snapshot() -> [String: Any] {
        let args = ProcessInfo.processInfo.arguments
        let answer = conversation != firstConversation ? "目录切换成功" : expired ? "会话重建成功" : readFailed ? "重连后答案" : "联调初始答案"
        var messages: [[String: Any]] = [["id":"answer1", "role":"assistant", "text":answer,
            "blocks":[], "links":[], "truncated":false]]
        if !sentText.isEmpty { messages.append(["id":"user1", "role":"user", "text":sentText, "blocks":[], "links":[], "truncated":false]) }
        if args.contains("--pc-fixture-unknown") && sends > 0 { messages.append(["id":"answer2", "role":"assistant", "text":"已收到一次消息", "blocks":[], "links":[], "truncated":false]) }
        return ["schema":1, "documentId":"fixture-document", "conversationId":conversation, "title":"联调测试会话",
            "messages":messages, "status":"completed", "draft":draft, "draftHash":PCCompanionPolicy.hash(draft),
            "canSend":!draft.isEmpty, "composing":false, "unsupportedTools":false, "historyPartial":true]
    }
    private static func library() -> [String: Any] {
        let project = "g-p-aaaaaaaaaaaaaaaa"
        var chats: [[String: Any]] = [["id":firstConversation,"title":"联调测试会话","current":conversation == firstConversation,"status":"completed","readState":"read","tabId":1]]
        if projectExpanded { chats.append(["id":"22222222-2222-4222-8222-222222222222","title":"第二个项目对话","projectId":project,"current":false,"status":"completed","readState":"unread"]) }
        return ["ok":true,"sourceTabId":1,"projects":[["id":project,"title":"Project Alpha","collapsed":!projectExpanded,"hasMore":false]],
            "chats":chats,"tabs":[["tabId":1,"title":"联调测试会话","conversationId":conversation,"active":true]],"partial":true,"sidebarAvailable":true]
    }
    private static func envelope() -> [String: Any] {
        ["ok":true, "sessionId":"fixture-session-\(sessions)", "revision":version,
         "capturedAt":Date().timeIntervalSince1970 * 1000, "routeChanged":false, "snapshot":snapshot()]
    }
    override func startLoading() {
        let payload = body()
        Self.lock.lock()
        let path = request.url?.path ?? "", method = request.httpMethod ?? "GET"
        let args = ProcessInfo.processInfo.arguments
        var code = 200; var json: [String: Any] = [:]; var delay = 0.04
        if request.value(forHTTPHeaderField: "Authorization") != "Bearer " + String(repeating: "T", count: 43) {
            code = 401; json = ["error":"pairing_required"]
        } else if path == "/v1/library" { json = Self.library()
        } else if path == "/v1/library/actions" && method == "POST" {
            if payload["action"] as? String == "project" { Self.projectExpanded = true; json = Self.library() }
            else {
                Self.conversation = payload["conversationId"] as? String ?? Self.firstConversation; Self.version += 1
                json = ["ok":true,"tab":["tabId":1,"title":"第二个项目对话","conversationId":Self.conversation,"active":true]]
            }
        } else if path == "/v1/tabs" {
            json = ["tabs":[["tabId":1,"title":"联调测试会话","conversationId":Self.conversation,"active":true]]]
        } else if path == "/v1/sessions" && method == "POST" {
            Self.sessions += 1; Self.version += 1; json = Self.envelope()
        } else if path.hasPrefix("/v1/commands/") {
            json = ["ok":true,"commandId":Self.receiptID,"state":"done","result":["status":"sent_confirmed","messageId":"user1","documentId":"fixture-document"]]
        } else if path.hasSuffix("/commands") && method == "POST" {
            let action = payload["action"] as? String ?? "", id = payload["commandId"] as? String ?? ""
            if action == "draft" {
                if args.contains("--pc-fixture-conflict") {
                    code = 409; json = ["error":"draft_conflict"]; Self.draft = "电脑端新草稿"; Self.version += 1
                } else if payload["baseDraftHash"] as? String != PCCompanionPolicy.hash(Self.draft) {
                    code = 409; json = ["error":"draft_conflict"]
                } else {
                    Self.draft = payload["text"] as? String ?? ""; Self.version += 1
                    json = ["ok":true,"commandId":id,"state":"done","result":["status":"draft_synced","draftHash":PCCompanionPolicy.hash(Self.draft),"documentId":"fixture-document"]]
                }
            } else if action == "send" && args.contains("--pc-fixture-not-sent") {
                Self.sends += 1; Self.receiptID = id
                json = ["ok":false,"commandId":id,"state":"failed","result":["status":"not_sent","error":"send_unavailable","documentId":"fixture-document"]]
            } else if action == "send" {
                Self.sends += 1; Self.receiptID = id; Self.sentText = Self.draft; Self.draft = ""; Self.version += 1
                if args.contains("--pc-fixture-unknown") { code = 503; json = ["error":"pc_result_unknown"] }
                else { json = ["ok":true,"commandId":id,"state":"done","result":["status":"sent_confirmed","messageId":"user1","documentId":"fixture-document"]] }
            }
        } else if path.hasPrefix("/v1/sessions/") && method == "DELETE" { json = ["ok":true]
        } else if path.hasPrefix("/v1/sessions/") {
            Self.polls += 1
            if args.contains("--pc-fixture-reconnect") && !Self.readFailed {
                Self.readFailed = true; Self.version += 1; code = 503; json = ["error":"pc_offline"]
            } else if args.contains("--pc-fixture-expire") && !Self.expired {
                Self.expired = true; code = 410; json = ["error":"session_expired"]
            } else {
                json = Self.envelope()
                let after = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {$0.name == "after"})?.value
                if after == String(Self.version) { delay = 1.0 } // Bounded deterministic long poll.
            }
        } else { code = 404; json = ["error":"not_found"] }
        Self.lock.unlock()
        let result = json; let status = code
        let pending = DispatchWorkItem { [weak self] in
            guard let self, let url = self.request.url, let data = try? JSONSerialization.data(withJSONObject: result),
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"]) else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data); self.client?.urlProtocolDidFinishLoading(self)
        }
        work = pending; DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: pending)
    }
    override func stopLoading() { work?.cancel(); work = nil }
}
#endif
