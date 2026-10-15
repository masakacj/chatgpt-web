#if DEBUG
import Foundation

/// Simulator-only transport. Never reads pairing Keychain or reaches a real PC.
final class SharedTabFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static let a = "11111111-1111-4111-8111-111111111111"
    private static let b = "22222222-2222-4222-8222-222222222222"
    private static let project = "g-p-aaaaaaaaaaaaaaaa"
    private static var current = a
    private static var projectID: String?
    private static var document = "fixture-document-A"
    private static var revision = 0
    private static var sends = 0
    private static var draftWrites = 0
    private static var actions = 0
    private static var reads = 0
    private static var newChats = 0
    private static var interactionClicks = 0
    private static var stopClicks = 0
    private static var stopActive = true
    private static let stopTarget = "fixture-stop-target-001"
    private static var modelMenuLevel = 0
    private static var modelSelections = 0
    private static var modelCatalogReads = 0
    private static var modelName = "GPT-6 Thinking · Medium"
    private static var sentText: String?
    private static var receipts: [String: [String: Any]] = [:]
    private var cancelled = false
    private let instanceLock = NSLock()

    static var counters: String {
        lock.lock(); defer { lock.unlock() }
        return "发送请求：\(sends) · 草稿同步：\(draftWrites) · 导航：\(actions) · 交互：\(interactionClicks) · 停止：\(stopClicks) · 模型：\(modelSelections) · 菜单：\(modelCatalogReads)"
    }
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        current = a; projectID = nil; document = "fixture-document-A"; revision = 0; sends = 0; draftWrites = 0; actions = 0; reads = 0; newChats = 0; interactionClicks = 0; stopClicks = 0; stopActive = true; modelMenuLevel = 0; modelSelections = 0; modelCatalogReads = 0; modelName = "GPT-6 Thinking · Medium"; sentText = nil; receipts = [:]
    }
    override class func canInit(with request: URLRequest) -> Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--shared-tab-fixture") && request.url?.host == "shared-tab.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let request = self.request
        let delay: Double = request.httpMethod == "GET" && request.url?.path.contains("/sessions/") == true ? 0.18 : 0.03
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.instanceLock.lock(); let cancelled = self.cancelled; self.instanceLock.unlock(); guard !cancelled else { return }
            Self.lock.lock(); let result = Self.response(request); Self.lock.unlock()
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]), let data = try? JSONSerialization.data(withJSONObject: result.1) else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data); self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { instanceLock.lock(); cancelled = true; instanceLock.unlock() }
    private static func body(_ req: URLRequest) -> [String: Any] {
        var data = req.httpBody
        if data == nil, let stream = req.httpBodyStream {
            stream.open(); defer { stream.close() }; var all = Data(); var buffer = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; all.append(buffer, count: count) }; data = all
        }
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }
    private static func message(_ id: String, _ role: String, _ text: String) -> [String: Any] {
        ["id": id, "role": role, "text": text, "blocks": [["kind": "text", "text": text]], "links": [], "truncated": false]
    }
    private static func currentModel() -> [String: Any] {
        var result: [String: Any] = ["available": true, "name": modelName, "source": "pc_model_trigger"]
        if modelName.contains("Thinking") {
            result["thinking"] = ["observed": true, "effort": modelName.contains("Extra High") ? "Extra High" : modelName.contains("High") ? "High" : "Medium"]
        }
        return result
    }
    private static func modelOptions() -> [[String: Any]] {
        if modelMenuLevel == 1 {
            return [
                ["id": "fixture-effort-medium-10001", "label": "Medium", "selected": modelName.hasSuffix("Medium"), "submenu": false],
                ["id": "fixture-effort-high-10001", "label": "High", "selected": modelName.hasSuffix("· High"), "submenu": false],
                ["id": "fixture-effort-extra-high-10001", "label": "Extra High", "selected": modelName.hasSuffix("Extra High"), "submenu": false]
            ]
        }
        return [
            ["id": "fixture-model-instant-10001", "label": "GPT-6 Instant", "selected": modelName == "GPT-6 Instant", "submenu": false],
            ["id": "fixture-model-thinking-10001", "label": "GPT-6 Thinking", "selected": modelName.contains("Thinking"), "submenu": true]
        ]
    }
    private static func snapshot() -> [String: Any] {
        let args = ProcessInfo.processInfo.arguments
        let title = current.isEmpty ? "新聊天" : current == a ? "测试对话 A" : current == b ? "历史对话 B" : "已创建的新聊天"
        var messages: [[String: Any]] = current.isEmpty ? [] : [message("u-" + current, "user", "测试提问"), message("a-" + current, "assistant", current == a ? "原生测试答案 A" : "原生历史答案 B")]
        if let sentText { messages.append(message("sent-user-\(sends)", "user", sentText)); messages.append(message("sent-answer-\(sends)", "assistant", "原生回复：" + sentText)) }
        if args.contains("--shared-fixture-rich") {
            messages.append([
                "id": "fixture-rich-message", "role": "assistant", "text": "富内容验收",
                "blocks": [
                    ["kind": "heading", "text": "富内容验收"],
                    ["kind": "table", "text": "Name Value Alpha 42", "rows": [["Name", "Value"], ["Alpha", "42"]]],
                    ["kind": "code", "text": "print(42)"],
                    ["kind": "quote", "text": "这是引用"],
                    ["kind": "image", "text": "PC 私有图片", "url": ""],
                    ["kind": "attachment", "text": "notes.pdf"]
                ],
                "links": [["title": "Help in PC", "url": "https://docs.example.test/help", "interactionId": "link-fixture-anchor-0001", "interactionRevision": "fixture-revision-link-001"]], "truncated": false
            ])
        }

        var s: [String: Any] = ["schema": 1, "sharedTab": true, "documentId": document, "conversationId": current, "title": title, "messages": messages, "status": "completed", "draftHash": PCCompanionPolicy.hash(""), "draft": "PC_TEXT_MUST_NEVER_APPEAR_IN_PHONE", "temporary": current.isEmpty, "canSend": true, "pcDraftOccupied": false, "composing": false, "responsePhase": "completed", "interactions": [], "hasOlder": args.contains("--shared-fixture-history"), "historyCursor": "oldest-visible-turn"]
        if args.contains("--shared-fixture-stop") || args.contains("--shared-fixture-stop-unknown") {
            s["status"] = stopActive ? "running" : "stopped"
            s["responsePhase"] = stopActive ? "thinking" : "stopped"
            s["canStop"] = stopActive
            s["stopTargetId"] = stopActive ? stopTarget : NSNull()
        }
        if args.contains("--shared-fixture-model") || args.contains("--shared-fixture-model-unknown") {
            s["model"] = currentModel()
        }
        if args.contains("--shared-fixture-pc-draft") {
            s["pcDraftOccupied"] = true
            s["draftHash"] = PCCompanionPolicy.hash("PC parked draft")
        }
        if let projectID { s["projectId"] = projectID }
        if args.contains("--shared-fixture-busy-send") || args.contains("--shared-fixture-busy-blocked") {
            s["status"] = "running"; s["responsePhase"] = "responding"
            s["canSend"] = !args.contains("--shared-fixture-busy-blocked")
        }
        if args.contains("--shared-fixture-interaction") && interactionClicks == 0 {
            s["status"] = "waiting"; s["canSend"] = false; s["interactions"] = [["id": "fixture-card-001", "title": "测试确认", "summary": "只执行一次本地测试操作", "buttons": [["id": "fixture-button-0001", "label": "允许一次", "revision": "fixture-revision-001", "disabled": false, "requiresConfirmation": true]]]]
        }
        return s
    }
    private static func envelope() -> [String: Any] {
        ["ok": true, "sessionId": "shared-fixture-session-001", "tabId": 7, "followTab": true, "revision": revision, "routeChanged": false, "tabClosed": false, "capturedAt": Date().timeIntervalSince1970 * 1000, "snapshot": snapshot()]
    }
    private static func library(search: Bool = false) -> [String: Any] {
        ["ok": true, "projects": [["id": project, "title": "Project Alpha", "collapsed": false, "hasMore": false]], "chats": search ? [["id": b, "title": "历史对话 B", "status": "completed", "readState": "read"]] : [["id": a, "title": "测试对话 A", "status": "completed", "readState": "read"]], "partial": true, "source": search ? "official_search" : "official_sidebar", "hasMore": false, "loading": false]
    }
    private static func response(_ req: URLRequest) -> (Int, [String: Any]) {
        let path = req.url?.path ?? "", input = body(req), args = ProcessInfo.processInfo.arguments
        if path == "/v1/health" { return (200, ["capabilities": ["shared-tab-v1", "compose-on-send"]]) }
        if path == "/v1/tabs" { return (200, ["tabs": [["tabId": 7, "title": "测试共用标签页", "conversationId": current, "active": true]]]) }
        if path == "/v1/sessions" { return (200, envelope()) }
        if path.hasSuffix("/actions") {
            let action = input["action"] as? String ?? ""
            if action == "catalog" || action == "project" { return (200, library()) }
            if action == "search" { return (200, library(search: true)) }
            if action == "model_catalog" {
                modelCatalogReads += 1; modelMenuLevel = 0
                return (200, ["ok": true, "available": true, "current": modelName, "options": modelOptions()])
            }
            if action == "model_select" {
                let commandID = input["commandId"] as? String ?? ""
                if let saved = receipts[commandID], let status = (saved["result"] as? [String: Any])?["status"] as? String {
                    return (200, ["ok": true, "status": status, "model": currentModel(), "options": modelOptions()])
                }
                let option = input["optionId"] as? String ?? ""
                guard input["documentId"] as? String == document,
                      modelOptions().contains(where: { ($0["id"] as? String) == option }) else {
                    receipts[commandID] = ["ok": false, "commandId": commandID, "state": "failed", "result": ["status": "not_selected", "error": "model_option_changed"]]
                    return (200, ["ok": true, "status": "not_selected", "error": "model_option_changed"])
                }
                modelSelections += 1
                if option == "fixture-model-thinking-10001" {
                    modelMenuLevel = 1
                    receipts[commandID] = ["ok": true, "commandId": commandID, "state": "done", "result": ["status": "option_clicked"]]
                    return (200, ["ok": true, "status": "option_clicked", "model": currentModel(), "options": modelOptions(), "selectionObserved": false, "submenuOpened": true])
                }
                if option == "fixture-model-instant-10001" { modelName = "GPT-6 Instant" }
                else if option == "fixture-effort-medium-10001" { modelName = "GPT-6 Thinking · Medium" }
                else if option == "fixture-effort-high-10001" { modelName = "GPT-6 Thinking · High" }
                else if option == "fixture-effort-extra-high-10001" { modelName = "GPT-6 Thinking · Extra High" }
                revision += 1
                if args.contains("--shared-fixture-model-unknown") {
                    receipts[commandID] = ["ok": true, "commandId": commandID, "state": "unknown", "result": ["status": "action_unconfirmed"]]
                    return (504, ["error": "pc_result_unknown"])
                }
                receipts[commandID] = ["ok": true, "commandId": commandID, "state": "done", "result": ["status": "option_clicked"]]
                return (200, ["ok": true, "status": "option_clicked", "model": currentModel(), "options": modelOptions(), "selectionObserved": true, "selectionEvidence": "native_model_trigger", "submenuOpened": false])
            }
            actions += 1; revision += 1; sentText = nil
            if action == "open" { current = input["targetConversationId"] as? String ?? b; projectID = nil }
            if action == "new" { current = ""; projectID = input["projectId"] as? String }
            document = "fixture-document-\(revision)"
            return (200, ["ok": true, "snapshot": snapshot()])
        }
        if path.hasSuffix("/commands") {
            let id = input["commandId"] as? String ?? "", action = input["action"] as? String ?? ""
            if let existing = receipts[id] { return (200, existing) }
            if action == "draft" { draftWrites += 1; return (400, ["error": "draft_sync_not_supported"]) }
            if action == "stop" {
                guard stopActive, input["documentId"] as? String == document,
                      input["conversationId"] as? String == current,
                      input["stopTargetId"] as? String == stopTarget,
                      input["confirmed"] as? Bool == true else {
                    let value: [String: Any] = ["ok": false, "commandId": id, "state": "failed", "result": ["status": "not_acted", "error": "stop_target_changed"]]
                    receipts[id] = value; return (200, value)
                }
                stopClicks += 1; stopActive = false; revision += 1
                if args.contains("--shared-fixture-stop-unknown") {
                    receipts[id] = ["ok": true, "commandId": id, "state": "unknown", "result": ["status": "stop_unconfirmed"]]
                    return (504, ["error": "pc_result_unknown"])
                }
                let value: [String: Any] = ["ok": true, "commandId": id, "state": "done", "result": ["status": "stop_clicked"]]
                receipts[id] = value; return (200, value)
            }
            if action == "interact" {
                interactionClicks += 1; revision += 1
                let value: [String: Any] = ["ok": true, "commandId": id, "state": "done", "result": ["status": "interaction_clicked"]]; receipts[id] = value; return (200, value)
            }
            sends += 1
            if args.contains("--shared-fixture-unknown") {
                receipts[id] = ["ok": true, "commandId": id, "state": "unknown", "result": ["error": "pc_result_unknown"]]
                return (504, ["error": "pc_result_unknown"])
            }
            if input["documentId"] as? String != document {
                let value: [String: Any] = ["ok": false, "commandId": id, "state": "failed", "result": ["status": "not_sent", "error": "pc_route_changed"]]; receipts[id] = value; return (200, value)
            }
            if current.isEmpty { newChats += 1; current = String(format: "dddddddd-dddd-4ddd-8ddd-%012d", newChats); document = "fixture-created-\(newChats)" }
            sentText = input["text"] as? String; revision += 1
            var result: [String: Any] = ["status": "sent_confirmed", "conversationId": current]
            if let projectID { result["projectId"] = projectID }
            let value: [String: Any] = ["ok": true, "commandId": id, "state": "done", "result": result]; receipts[id] = value; return (200, value)
        }
        if path.hasPrefix("/v1/commands/") { return receipts[String(path.split(separator: "/").last ?? "")].map { (200, $0) } ?? (404, ["error": "unknown_command"]) }
        if path.hasSuffix("/history") { return (200, ["documentId": document, "conversationId": current, "messages": [message("old-user", "user", "更早的问题"), message("old-answer", "assistant", "更早的正式回复")], "cursor": "history-start", "hasMore": false]) }
        if path.contains("/sessions/") {
            if req.httpMethod == "DELETE" { return (200, ["ok": true]) }
            reads += 1
            if args.contains("--shared-fixture-pc-switch") && reads == 15 { current = b; document = "fixture-PC-changed-B"; sentText = nil; revision += 1 }
            return (200, envelope())
        }
        return (404, ["error": "not_found"])
    }
}
#endif
