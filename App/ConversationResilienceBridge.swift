import Foundation
import UIKit
import WebKit

private final class WeakConversationHandler: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    weak var owner: ChatGPTConversationResilience?
    init(_ owner: ChatGPTConversationResilience) { self.owner = owner }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.readEvidence(message)
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let owner else { replyHandler(nil,"container_unavailable"); return }
        owner.handle(message, reply: replyHandler)
    }
}

final class ChatGPTConversationResilience {
    static let version = "1.0.0"
    static let world = WKContentWorld.world(name: "ChatGPTNativeConversation")
    private weak var webView: WKWebView?
    private let store = ConversationResilienceStore()
    private var proxy: WeakConversationHandler?
    private var urlObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private var activeObserver: NSObjectProtocol?
    private var document: String?
    private var failure: ConversationResilienceStore.Failure?
    private var failureCode = 0

    static func installScripts(on controller: WKUserContentController) {
        // This main-world script only observes matching saved-conversation
        // reads. Original fetch arguments, Promise and Response are preserved.
        for (name, time, world) in [
            ("NativeConversationEvidence", WKUserScriptInjectionTime.atDocumentStart, WKContentWorld.page),
            ("NativeConversationClient", WKUserScriptInjectionTime.atDocumentEnd, Self.world)
        ] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if !controller.userScripts.contains(where: {$0.source == source}) {
                controller.addUserScript(WKUserScript(source: source, injectionTime: time,
                                                      forMainFrameOnly: true, in: world))
            }
        }
    }
    func attach(to view: WKWebView) {
        if webView === view { return }
        detach()
        webView = view
        let proxy = WeakConversationHandler(self); self.proxy = proxy
        let controller = view.configuration.userContentController
        controller.add(proxy, contentWorld: .page, name: "nativeReadEvidence")
        controller.addScriptMessageHandler(proxy, contentWorld: Self.world, name: "nativeConversation")
        Self.installScripts(on: controller)
        urlObserver = view.observe(\.url, options: [.new]) { [weak self] _, _ in
            self?.failure = nil
            self?.wake()
        }
        loadingObserver = view.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            guard let self else { return }
            if view.isLoading { self.document = nil; self.failure = nil }
            else { Self.installScripts(on: view.configuration.userContentController); self.wake() }
        }
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.wake() }
    }
    func detach() {
        if let view = webView {
            let c = view.configuration.userContentController
            c.removeScriptMessageHandler(forName: "nativeReadEvidence", contentWorld: .page)
            c.removeScriptMessageHandler(forName: "nativeConversation", contentWorld: Self.world)
        }
        urlObserver = nil; loadingObserver = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil; proxy = nil; webView = nil; document = nil; failure = nil
    }
    deinit {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }
    private func trusted(_ message: WKScriptMessage) -> Bool {
        message.webView === webView && message.frameInfo.isMainFrame &&
            message.frameInfo.securityOrigin.protocol == "https" &&
            message.frameInfo.securityOrigin.host == "chatgpt.com" &&
            webView?.url?.host == "chatgpt.com" && webView?.url?.scheme == "https"
    }
    private func wake() {
        guard let webView, webView.url?.host == "chatgpt.com" else { return }
        webView.evaluateJavaScript("globalThis.__IOS_NATIVE_RESILIENCE__?.wake?.()", in: nil, in: Self.world) { _ in }
    }
    fileprivate func readEvidence(_ message: WKScriptMessage) {
        guard trusted(message), let body = message.body as? [String: Any],
              body["method"] as? String == "GET", body["type"] as? String == "saved-read",
              let id = body["id"] as? String,
              id == ConversationResilienceStore.conversationID(webView?.url),
              let doc = body["document"] as? String, doc == document,
              let code = body["status"] as? Int, (0...599).contains(code) else { return }
        let category = ConversationResilienceStore.failureCategory(code: code,
            networkError: body["networkError"] as? Bool == true)
        failureCode = code
        if let category {
            failure = .init(id: id, category: category, at: store.now(), document: doc)
        } else { failure = nil }
        wake()
    }
    fileprivate func handle(_ message: WKScriptMessage, reply: @escaping (Any?, String?) -> Void) {
        guard trusted(message), let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let doc = body["document"] as? String, !doc.isEmpty, doc.count <= 100 else {
            reply(nil,"untrusted_or_malformed"); return
        }
        if type == "boot" {
            if document != doc { document = doc; failure = nil }
            reply(["ok":true,"version":Self.version,"states":store.exported()],nil); return
        }
        guard document == doc else { reply(nil,"stale_document"); return }
        let current = ConversationResilienceStore.conversationID(webView?.url)
        if type == "observe", let value = body["observation"] as? [String: Any] {
            let rec = store.observe(value,currentID:current)
            reply(["ok":true,"record":rec?.json ?? [:]],nil)
        } else if type == "import", let items = body["items"] as? [[String:Any]] {
            let count = store.importLegacy(items)
            reply(["ok":true,"imported":count,"states":store.exported()],nil)
        } else if type == "refresh" {
            reply(["ok":true,"states":store.exported()],nil)
        } else if type == "recover", let snapshot = body["snapshot"] as? [String: Any] {
            let delay = store.reserveRetry(snapshot,failure:failure,currentID:current,document:doc,
                appActive:UIApplication.shared.applicationState == .active)
            reply(["ok":true,"retryAfter":delay ?? -1,"category":failure?.category ?? "no_read_failure"],nil)
        } else if type == "audit" {
            reply(["ok":true,"version":Self.version,"storage":"native UserDefaults",
                   "stateCount":store.records.count,"budgetCount":store.budgets.count,
                   "failure":failure?.category ?? "none","lastHTTPStatus":failureCode],nil)
        } else { reply(nil,"unknown_operation") }
    }
}
