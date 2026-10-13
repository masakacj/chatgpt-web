import Foundation
import WebKit

final class WeakOptimizedObservationHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var owner: ConversationManagerOwner?
    weak var webView: WKWebView?

    init(owner: ConversationManagerOwner) {
        self.owner = owner
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let owner, let webView,
              message.webView === webView,
              message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "chatgpt.com",
              webView.url?.scheme == "https",
              webView.url?.host == "chatgpt.com",
              let body = message.body as? [String: Any] else {
            replyHandler(nil, "untrusted_or_malformed")
            return
        }
        Task { @MainActor in
            let result = await owner.handle(body)
            replyHandler(result, nil)
        }
    }
}

enum WebConfigurationFactory {
    static let observationWorld = WKContentWorld.world(name: "ChatGPTWebOptimized.Observation.v1")
    static let handlerName = "optimizedConversation"

    static func make(owner: ConversationManagerOwner,
                     handler: WeakOptimizedObservationHandler) -> WKWebViewConfiguration {
        let controller = WKUserContentController()
        controller.addScriptMessageHandler(handler, contentWorld: observationWorld, name: handlerName)
        if let url = Bundle.main.url(forResource: "conversation-observer", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd,
                                                  forMainFrameOnly: true, in: observationWorld))
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        configuration.processPool = WKProcessPool()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        return configuration
    }
}
