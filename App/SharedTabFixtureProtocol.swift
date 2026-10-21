#if DEBUG
import Foundation

/// Simulator-only transport. Never reads pairing Keychain or reaches a real PC.
final class SharedTabFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static let a = "11111111-1111-4111-8111-111111111111"
    private static let b = "22222222-2222-4222-8222-222222222222"
    private static let c = "33333333-3333-4333-8333-333333333333"
    private static let d = "44444444-4444-4444-8444-444444444444"
    private static let project = "g-p-aaaaaaaaaaaaaaaa"
    private static var current = a
    private static var projectID: String?
    private static var document = "fixture-document-A"
    private static var revision = 0
    private static var stalePCLoading = true
    private static var sends = 0
    private static var stops = 0
    private static let nativeStopId = "fixture-native-stop-control-001122"
    private static var draftWrites = 0
    private static var actions = 0
    private static var reads = 0
    private static var healthReads = 0
    private static var reportOldSessionClosed = false
    private static var newChats = 0
    private static var interactionClicks = 0
    private static var modelSelects = 0
    private static var lateSettlements = 0
    private static var modelName = "GPT-6"
    private static var effortName: String? = "High"
    private static var effortObserved = true
    private static var sentText: String?
    private static var receipts: [String: [String: Any]] = [:]
    private var cancelled = false
    private let instanceLock = NSLock()

    static var counters: String {
        lock.lock(); defer { lock.unlock() }
        return "发送请求：\(sends) · 中止请求：\(stops) · 草稿同步：\(draftWrites) · 导航：\(actions) · 交互：\(interactionClicks) · 模型选择：\(modelSelects) · 旧回执结算：\(lateSettlements)"
    }
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        current = a; projectID = nil; document = "fixture-document-A"; revision = 0; stalePCLoading = true; sends = 0; stops = 0; draftWrites = 0; actions = 0; reads = 0; healthReads = 0; newChats = 0; interactionClicks = 0; modelSelects = 0; lateSettlements = 0; modelName = "GPT-6"; effortName = "High"; effortObserved = true; sentText = nil; receipts = [:]; reportOldSessionClosed = false
    }
    static func simulateOldSessionClosed() {
        lock.lock(); defer { lock.unlock() }
        reportOldSessionClosed = true
    }
    static func simulatePCModelSwitch() {
        lock.lock(); defer { lock.unlock() }
        guard ProcessInfo.processInfo.arguments.contains("--shared-fixture-pc-model-switch") else { return }
        modelName = "GPT-4o"
        effortName = nil
        effortObserved = false
        revision += 1
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
            Self.lock.lock()
            let health = request.url?.path == "/v1/health"
            let failOnce = health && ProcessInfo.processInfo.arguments.contains("--shared-fixture-resume-timeout") && Self.healthReads == 1
            if health { Self.healthReads += 1 }
            let result = failOnce ? nil : Self.response(request)
            Self.lock.unlock()
            if failOnce {
                self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                return
            }
            guard let result, let url = request.url, let response = HTTPURLResponse(url: url, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]), let data = try? JSONSerialization.data(withJSONObject: result.1) else { return }
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
    private static func snapshot() -> [String: Any] {
        let args = ProcessInfo.processInfo.arguments
        let title = current.isEmpty ? "新聊天" : current == a ? "测试对话 A" : current == b ? "历史对话 B" : "已创建的新聊天"
        var messages: [[String: Any]] = current.isEmpty ? [] : [message("u-" + current, "user", "测试提问"), message("a-" + current, "assistant", current == a ? "原生测试答案 A" : "原生历史答案 B")]
        if args.contains("--shared-fixture-long") || args.contains("--shared-fixture-scroll") {
            var longMessages: [[String: Any]] = []
            for i in 1...15 {
                longMessages.append(message("long-u-\(i)", "user", "长对话提问 第 \(i) 轮：请分析多阶段架构和分布式系统的一致性保障。"))
                longMessages.append(message("long-a-\(i)", "assistant", "长对话回答 第 \(i) 轮：这是第 \(i) 轮详细的回复内容。分布式系统的每个节点在执行变更前必须通过共识协议提交日志，确保状态机在任何副本崩溃恢复后能够重建完全一致的状态视图。\n\n关键要点：\n1. 严格的领导者选举与心跳机制；\n2. 多数派写确认；\n3. 租约与幂等防重放保护。"))
            }
            messages = longMessages
        }
        if let sentText { messages.append(message("sent-user-\(sends)", "user", sentText)); messages.append(message("sent-answer-\(sends)", "assistant", "原生回复：" + sentText)) }
        if args.contains("--shared-fixture-native-resources") {
            messages.append(["id": "fixture-native-resources", "role": "assistant", "text": "公开链接和文件", "blocks": [
                ["kind": "text", "text": "公开链接和文件"],
                ["kind": "attachment", "text": "demo.pdf", "url": "https://www.example.com/demo.pdf"],
                ["kind": "attachment", "text": "仅 PC 私有文件", "url": ""]
            ], "links": [["title": "官方帮助", "url": "https://www.example.com/help"]], "truncated": false])
        }
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

        var modelPayload: [String: Any] = ["available": true, "name": modelName]
        if args.contains("--shared-fixture-model-effort-unknown") ||
           args.contains("--shared-fixture-model-thinking-unobserved-high") {
            modelPayload = ["available": true, "name": "GPT-6 Thinking · High", "thinking": ["observed": false, "confidence": "unconfirmed"]]
        } else if args.contains("--shared-fixture-model-non-thinking") {
            modelPayload["name"] = "GPT-4o"
        } else if args.contains("--shared-fixture-doc-change-invalidates-effort") && reads >= 6 {
            document = "fixture-document-switched"
            modelPayload = ["available": true, "name": "GPT-6", "thinking": ["observed": false, "confidence": "unconfirmed"]]
        } else if let eff = effortName, effortObserved {
            modelPayload["thinking"] = ["observed": true, "effort": eff, "source": "native_checked_radio"]
        }

        if args.contains("--shared-fixture-sidebar-completed-over-running") {
            current = a
        }

        var s: [String: Any] = ["schema": 1, "sharedTab": true, "documentId": document, "conversationId": current, "title": title, "messages": messages, "status": "completed", "draftHash": PCCompanionPolicy.hash(""), "draft": "PC_TEXT_MUST_NEVER_APPEAR_IN_PHONE", "temporary": current.isEmpty, "canSend": true, "pcDraftOccupied": false, "composing": false, "responsePhase": "completed", "model": modelPayload, "interactions": [], "hasOlder": args.contains("--shared-fixture-history"), "historyCursor": "oldest-visible-turn"]
        if args.contains("--shared-fixture-pc-done-loading") && stalePCLoading {
            // PC's initial loading frame was observed, but the live page has
            // since completed without advancing the old long-poll revision.
            s["status"] = "loading"
            s["responsePhase"] = "loading"
        }
        if args.contains("--shared-fixture-pc-draft-native-blocked") {
            // The phone must be allowed to Send its own text even if the PC
            // has a parked local draft and reports disabled native controls.
            s["pcDraftOccupied"] = true
            s["draftHash"] = PCCompanionPolicy.hash("PC parked draft")
            s["canSend"] = false
            s["composing"] = true
        }
        if let projectID { s["projectId"] = projectID }
        if args.contains("--shared-fixture-native-stop") ||
           args.contains("--shared-fixture-stop-unknown") ||
           args.contains("--shared-fixture-stale-stop") ||
           args.contains("--shared-fixture-stop-and-unknown-send") {
            let finished = stops > 0 && !args.contains("--shared-fixture-stop-unknown")
            s["status"] = finished ? "stopped" : "running"
            s["responsePhase"] = finished ? "stopped" : "responding"
            s["canStop"] = !finished
            if finished { s["stopTargetId"] = NSNull() }
            else { s["stopTargetId"] = nativeStopId }
            // Match the actual PC controls: while generating, the ordinary
            // send control may be disabled, but the phone may still type.
            s["canSend"] = false
        }
        if args.contains("--shared-fixture-sidebar") || args.contains("--shared-fixture-sidebar-both") || args.contains("--shared-fixture-sidebar-read-ack") || args.contains("--shared-fixture-sidebar-new-unread") || args.contains("--shared-fixture-sidebar-colors") || args.contains("--shared-fixture-sidebar-completed-over-running") {
            if args.contains("--shared-fixture-sidebar-completed-over-running") {
                // Only bound chat A is stale-running. B must not add an
                // unrelated running section after A is completed in snapshot.
                s["sidebarIndicators"] = [["id": a, "status": "running", "readState": "read"],
                                           ["id": b, "status": "completed", "readState": "read"]]
            } else if args.contains("--shared-fixture-sidebar-both") {
                s["sidebarIndicators"] = [["id": a, "status": "completed", "readState": "read"],
                                           ["id": b, "status": "running", "readState": "unread"]]
            } else if args.contains("--shared-fixture-sidebar-new-unread") {
                s["sidebarIndicators"] = [["id": a, "status": "completed", "readState": "unread"],
                                           ["id": b, "status": "completed", "readState": "read"]]
            } else if args.contains("--shared-fixture-sidebar-colors") {
                s["sidebarIndicators"] = [["id": a, "status": "completed", "readState": "unread"],
                                           ["id": d, "status": "unknown", "readState": "unread"],
                                           ["id": b, "status": "running", "readState": "unknown"]]
            } else {
                s["sidebarIndicators"] = [["id": a, "status": "completed", "readState": "unread"],
                                           ["id": b, "status": "running", "readState": "unknown"]]
            }
        }
        if args.contains("--shared-fixture-busy-send") || args.contains("--shared-fixture-busy-blocked") {
            s["status"] = "running"; s["responsePhase"] = "responding"
            s["canSend"] = !args.contains("--shared-fixture-busy-blocked")
        }
        if (args.contains("--shared-fixture-interaction") || args.contains("--shared-fixture-result-choice-unknown")) && interactionClicks == 0 && current == a {
            let resultChoice = args.contains("--shared-fixture-result-choice-unknown")
            s["status"] = "waiting"; s["canSend"] = false
            s["interactions"] = [["id": "fixture-card-001", "title": resultChoice ? "选择结果" : "测试确认", "summary": "只执行一次本地测试操作", "buttons": [["id": "fixture-button-0001", "label": resultChoice ? "选择结果" : "允许一次", "revision": "fixture-revision-001", "disabled": false, "requiresConfirmation": true]]]]
        }
        return s
    }
    private static func envelope() -> [String: Any] {
        ["ok": true, "sessionId": "shared-fixture-session-001", "tabId": 7, "followTab": true, "revision": revision, "routeChanged": false, "tabClosed": false, "capturedAt": Date().timeIntervalSince1970 * 1000, "snapshot": snapshot()]
    }
    private static func library(search: Bool = false) -> [String: Any] {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--shared-fixture-sidebar-completed-over-running") {
            return ["ok": true, "projects": [["id": project, "title": "Project Alpha", "collapsed": false, "hasMore": false]], "chats": [
                ["id": a, "title": "测试对话 A", "projectId": project, "status": "running", "readState": "read", "activityAt": 1000.0],
                ["id": b, "title": "历史对话 B", "status": "completed", "readState": "read", "activityAt": 2000.0]
            ], "partial": true, "source": "official_sidebar", "hasMore": false, "loading": false]
        }
        let selected: [[String: Any]] = search ? [["id": b, "title": "历史对话 B", "status": "completed", "readState": "read"]] :
            (args.contains("--shared-fixture-sidebar") || args.contains("--shared-fixture-sidebar-both") || args.contains("--shared-fixture-sidebar-read-ack") || args.contains("--shared-fixture-sidebar-new-unread") || args.contains("--shared-fixture-sidebar-colors")) ? [
            ["id": a, "title": "测试对话 A", "status": "completed", "readState": "unread", "activityAt": (args.contains("--shared-fixture-sidebar-new-unread") && actions >= 1) ? 99999.0 : 1000.0, "watermark": (args.contains("--shared-fixture-sidebar-new-unread") && actions >= 1) ? "watermark-turn-2" : "watermark-turn-1"],
            ["id": b, "title": "历史对话 B", "projectId": project, "status": args.contains("--shared-fixture-sidebar-new-unread") ? "completed" : "running", "readState": args.contains("--shared-fixture-sidebar-both") ? "unread" : "unknown", "activityAt": 9000.0],
            ["id": c, "title": "近期对话 C", "status": "completed", "readState": "read", "activityAt": 5000.0],
            ["id": d, "title": "其它未读 D", "status": "unknown", "readState": "unread", "activityAt": 2000.0]
        ] : [["id": a, "title": "测试对话 A", "status": "completed", "readState": "read"]]
        return ["ok": true, "projects": [["id": project, "title": "Project Alpha", "collapsed": false, "hasMore": false]], "chats": selected, "partial": true, "source": search ? "official_search" : "official_sidebar", "hasMore": false, "loading": false]
    }
    private static func response(_ req: URLRequest) -> (Int, [String: Any]) {
        let path = req.url?.path ?? "", input = body(req), args = ProcessInfo.processInfo.arguments
        if path == "/v1/health" { return (200, ["capabilities": ["shared-tab-v1", "compose-on-send", "model-selection", "mobile-upload", "recent-activity", "native-stop-generation"]]) }
        if path == "/v1/tabs" {
            let first: [String: Any] = ["tabId": 7, "title": "测试共用标签页", "conversationId": current, "active": true]
            if args.contains("--shared-fixture-multiple-tabs") || args.contains("--shared-fixture-stale-tab-match") {
                return (200, ["tabs": [first, ["tabId": 9, "title": "另一测试标签页", "conversationId": b, "active": false]]])
            }
            return (200, ["tabs": [first]])
        }
        if path == "/v1/sessions" {
            if input["tabId"] as? Int != 7 { return (400, ["error": "invalid_tab"]) }
            return (200, envelope())
        }
        if path.hasSuffix("/actions") {
            let action = input["action"] as? String ?? ""
            if action == "catalog" || action == "project" { return (200, library()) }
            if action == "model_catalog" {
                let quickEffort = (input["menuLevel"] as? String) == "effort"
                if args.contains("--shared-fixture-model-effort-unknown") {
                    return (200, ["available": true, "current": "GPT-6", "thinking": ["observed": false, "confidence": "unconfirmed"], "options": [["id": "fixture-model-option-unknown", "label": "Thinking (未指定强度)", "selected": true, "submenu": false]]])
                }
                if args.contains("--shared-fixture-model-non-thinking") {
                    return (200, ["available": true, "current": "GPT-4o", "options": [["id": "fixture-model-gpt4o", "label": "GPT-4o", "selected": true, "submenu": false]]])
                }
                if args.contains("--shared-fixture-nested-effort-submenu") {
                    if quickEffort {
                        return (200, ["available": true, "current": "GPT-6", "options": [
                            ["id": "fixture-effort-medium", "label": "Medium", "kind": "effort", "selected": false, "submenu": false],
                            ["id": "fixture-effort-high", "label": "High", "kind": "effort", "selected": true, "submenu": false]
                        ]])
                    }
                    return (200, ["available": true, "current": "GPT-6", "options": [
                        ["id": "fixture-option-gpt4o", "label": "GPT-4o", "kind": "model", "selected": false, "submenu": false],
                        ["id": "fixture-option-gpt6-thinking", "label": "GPT-6 (Thinking)", "kind": "submenu", "selected": true, "submenu": true]
                    ]])
                }
                if args.contains("--shared-fixture-effort-slider") {
                    if quickEffort {
                        return (200, ["available": true, "current": "GPT-6", "options": [
                            ["id": "fixture-effort-level-1", "label": "Low (Level 1)", "kind": "slider", "value": 1, "selected": false],
                            ["id": "fixture-effort-level-2", "label": "Medium (Level 2)", "kind": "slider", "value": 2, "selected": false],
                            ["id": "fixture-effort-level-3", "label": "High (Level 3)", "kind": "slider", "value": 3, "selected": true],
                            ["id": "fixture-effort-level-4", "label": "Extra High (Level 4)", "kind": "slider", "value": 4, "selected": false]
                        ]])
                    }
                    return (200, ["available": true, "current": "GPT-6", "options": [
                        ["id": "fixture-slider-effort", "label": "Thinking Effort", "kind": "slider", "value": 3, "min": 1, "max": 5, "step": 1, "valueText": "High (Level 3)", "description": "More reasoning steps for complex problems"]
                    ]])
                }
                if args.contains("--shared-fixture-option-disabled") {
                    return (200, ["available": true, "current": "GPT-6", "options": [
                        ["id": "fixture-option-disabled-pro", "label": "Extra High (需要 Pro 订阅)", "disabled": true, "description": "当前账号不可用"]
                    ]])
                }
                if quickEffort {
                    return (200, ["available": true, "current": modelName, "options": [
                        ["id": "fixture-effort-option-high", "label": "Thinking · High", "kind": "effort", "selected": false, "submenu": false]
                    ]])
                }
                return (200, ["available": true, "current": modelName, "options": [
                    ["id": "fixture-model-option-0001", "label": "Thinking · High", "selected": false, "submenu": false],
                    ["id": "fixture-model-option-gpt4o", "label": "GPT-4o", "selected": false, "submenu": false]
                ]])
            }
            if action == "model_select" {
                modelSelects += 1
                let cmdId = input["commandId"] as? String ?? UUID().uuidString
                let optionId = input["optionId"] as? String ?? ""

                if args.contains("--shared-fixture-model-select-timeout") {
                    receipts[cmdId] = ["ok": true, "commandId": cmdId, "state": "unknown", "result": ["error": "pc_result_unknown"]]
                    return (504, ["error": "pc_result_unknown"])
                }
                if args.contains("--shared-fixture-model-cross-scope-receipt") ||
                   args.contains("--shared-fixture-model-cross-scope-false-confirm") {
                    let foreignConfirmed = args.contains("--shared-fixture-model-cross-scope-false-confirm")
                    receipts[cmdId] = ["ok": true, "commandId": cmdId, "state": "done", "result": [
                        "status": "option_clicked", "selectionObserved": foreignConfirmed,
                        "conversationId": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
                        "model": ["available": true, "name": "GPT-4o"]
                    ]]
                    return (504, ["error": "pc_result_unknown"])
                }
                if args.contains("--shared-fixture-model-select-nil-evidence") {
                    let val: [String: Any] = ["ok": true, "commandId": cmdId, "state": "done", "result": ["status": "option_clicked"]]
                    receipts[cmdId] = val
                    return (200, ["status": "option_clicked", "options": []])
                }
                if args.contains("--shared-fixture-option-clicked-unobserved") {
                    let val: [String: Any] = ["ok": true, "commandId": cmdId, "state": "done", "result": ["status": "option_clicked", "selectionObserved": false]]
                    receipts[cmdId] = val
                    return (200, ["status": "option_clicked", "selectionObserved": false, "options": []])
                }
                if args.contains("--shared-fixture-nested-effort-submenu") {
                    if optionId == "fixture-option-gpt6-thinking" {
                        return (200, [
                            "status": "option_clicked",
                            "submenuOpened": true,
                            "options": [
                                ["id": "fixture-effort-instant", "label": "Instant", "kind": "effort", "selected": false],
                                ["id": "fixture-effort-medium", "label": "Medium", "kind": "effort", "selected": false],
                                ["id": "fixture-effort-high", "label": "High", "kind": "effort", "selected": true],
                                ["id": "fixture-effort-extra", "label": "Extra High", "kind": "effort", "selected": false]
                            ]
                        ])
                    }
                    if optionId == "fixture-effort-medium" {
                        effortName = "Medium"
                        effortObserved = true
                        revision += 1
                        let resModel: [String: Any] = ["available": true, "name": "GPT-6", "thinking": ["observed": true, "effort": "Medium"]]
                        receipts[cmdId] = ["ok": true, "commandId": cmdId, "state": "done", "result": ["status": "option_clicked", "selectionObserved": true, "model": resModel]]
                        return (200, ["status": "option_clicked", "selectionObserved": true, "model": resModel, "options": []])
                    }
                }
                if args.contains("--shared-fixture-effort-slider") {
                    let val = input["value"] as? Double ?? 4
                    effortName = "Level \(Int(val))"
                    effortObserved = true
                    revision += 1
                    let resModel: [String: Any] = ["available": true, "name": "GPT-6", "thinking": ["observed": true, "effort": "Level \(Int(val))", "value": val]]
                    receipts[cmdId] = ["ok": true, "commandId": cmdId, "state": "done", "result": ["status": "option_clicked", "selectionObserved": true, "model": resModel]]
                    return (200, ["status": "option_clicked", "selectionObserved": true, "model": resModel, "options": []])
                }
                if optionId == "fixture-model-option-gpt4o" {
                    modelName = "GPT-4o"
                    effortName = nil
                    effortObserved = false
                    revision += 1
                    let resModel: [String: Any] = ["available": true, "name": "GPT-4o"]
                    receipts[cmdId] = ["ok": true, "commandId": cmdId, "state": "done", "result": ["status": "option_clicked", "selectionObserved": true, "model": resModel]]
                    return (200, ["status": "option_clicked", "selectionObserved": true, "model": resModel, "options": []])
                }
                effortName = "High"
                effortObserved = true
                revision += 1
                let resModel: [String: Any] = ["available": true, "name": "GPT-6 Thinking · High", "thinking": ["observed": true, "effort": "High"]]
                receipts[cmdId] = ["ok": true, "commandId": cmdId, "state": "done", "result": ["status": "option_clicked", "selectionObserved": true, "model": resModel]]
                return (200, ["status": "option_clicked", "selectionObserved": true, "model": resModel, "options": []])
            }
            if action == "search" { return (200, library(search: true)) }
            actions += 1; revision += 1; sentText = nil
            if action == "open" { current = input["targetConversationId"] as? String ?? b; projectID = nil }
            if action == "new" { current = ""; projectID = input["projectId"] as? String }
            document = "fixture-document-\(revision)"
            return (200, ["ok": true, "snapshot": snapshot()])
        }
        if path.hasSuffix("/uploads") { return (200, ["status": "handed_to_pc", "name": input["name"] ?? "test.png"]) }
        if path.hasSuffix("/commands") {
            let id = input["commandId"] as? String ?? "", action = input["action"] as? String ?? ""
            if let existing = receipts[id] { return (200, existing) }
            if action == "draft" { draftWrites += 1; return (400, ["error": "draft_sync_not_supported"]) }
            if action == "stop" {
                let matching = input["documentId"] as? String == document &&
                    input["conversationId"] as? String == current &&
                    input["stopTargetId"] as? String == nativeStopId &&
                    input["confirmed"] as? Bool == true &&
                    stops == 0 && !args.contains("--shared-fixture-stale-stop")
                if !matching {
                    let value: [String: Any] = ["ok": false, "commandId": id,
                        "state": "failed", "result": ["status": "not_acted", "error": "stop_target_changed"]]
                    receipts[id] = value; return (200, value)
                }
                stops += 1; revision += 1
                if args.contains("--shared-fixture-stop-unknown") {
                    receipts[id] = ["ok": true, "commandId": id,
                                    "state": "unknown", "result": ["error": "pc_result_unknown"]]
                    return (504, ["error": "pc_result_unknown"])
                }
                let value: [String: Any] = ["ok": true, "commandId": id,
                    "state": "done", "result": ["status": "stop_clicked", "conversationId": current]]
                receipts[id] = value; return (200, value)
            }
            if action == "interact" {
                interactionClicks += 1; revision += 1
                if args.contains("--shared-fixture-result-choice-unknown") {
                    receipts[id] = ["ok": true, "commandId": id, "state": "unknown", "result": ["error": "pc_result_unknown"]]
                    return (504, ["error": "pc_result_unknown"])
                }
                let value: [String: Any] = ["ok": true, "commandId": id, "state": "done", "result": ["status": "interaction_clicked"]]; receipts[id] = value; return (200, value)
            }
            sends += 1
            if args.contains("--shared-fixture-unknown") ||
               args.contains("--shared-fixture-stop-and-unknown-send") ||
               (current == a && args.contains("--shared-fixture-late-old-send-confirm")) ||
               (current == a && args.contains("--shared-fixture-late-old-send-fail")) {
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
        if path.hasPrefix("/v1/commands/") {
            let commandId = String(path.split(separator: "/").last ?? "")
            if current == b, let existing = receipts[commandId], existing["state"] as? String == "unknown" {
                if args.contains("--shared-fixture-late-old-send-confirm") {
                    lateSettlements += 1
                    receipts[commandId] = ["ok": true, "commandId": commandId, "state": "done",
                        "result": ["status": "sent_confirmed", "conversationId": a]]
                } else if args.contains("--shared-fixture-late-old-send-fail") {
                    lateSettlements += 1
                    receipts[commandId] = ["ok": false, "commandId": commandId, "state": "failed",
                        "result": ["status": "not_sent", "error": "send_unavailable", "conversationId": a]]
                }
            }
            return receipts[commandId].map { (200, $0) } ?? (404, ["error": "unknown_command"])
        }
        if path.hasSuffix("/history") { return (200, ["documentId": document, "conversationId": current, "messages": [message("old-user", "user", "更早的问题"), message("old-answer", "assistant", "更早的正式回复")], "cursor": "history-start", "hasMore": false]) }
        if path.contains("/sessions/") {
            if req.httpMethod == "DELETE" { return (200, ["ok": true]) }
            reads += 1
            if args.contains("--shared-fixture-old-session-closed") && reportOldSessionClosed {
                reportOldSessionClosed = false
                return (200, ["ok": true, "sessionId": "shared-fixture-session-001",
                              "tabId": 7, "followTab": true, "revision": revision + 1,
                              "routeChanged": false, "tabClosed": true])
            }
            if args.contains("--shared-fixture-pc-done-loading") &&
               req.url?.query?.contains("refresh=1") == true &&
               stalePCLoading {
                stalePCLoading = false
                revision += 1
            }
            if args.contains("--shared-fixture-pc-switch") && reads == 15 { current = b; document = "fixture-PC-changed-B"; sentText = nil; revision += 1 }
            if args.contains("--shared-fixture-doc-change-invalidates-effort") && reads >= 6 { document = "fixture-document-switched"; effortName = nil; effortObserved = false; revision += 1 }
            return (200, envelope())
        }
        return (404, ["error": "not_found"])
    }
}
#endif
