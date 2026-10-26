import SwiftUI
import UIKit
import WebKit

struct OptimizedWebView: UIViewRepresentable {
    @ObservedObject var model: OptimizedAppModel
    @ObservedObject var owner: ConversationManagerOwner
    let telemetry: OptimizedTelemetry
    let supervisor: NativeOptimizationSupervisor?
    let resourceGate: NativeResourceGate
    let liveDebug: OptimizedLiveDebug
    let pcHistoryEnabled: Bool

    init(model: OptimizedAppModel,
         owner: ConversationManagerOwner,
         telemetry: OptimizedTelemetry,
         supervisor: NativeOptimizationSupervisor? = nil,
         resourceGate: NativeResourceGate,
         liveDebug: OptimizedLiveDebug,
         pcHistoryEnabled: Bool) {
        self.model = model
        self.owner = owner
        self.telemetry = telemetry
        self.supervisor = supervisor
        self.resourceGate = resourceGate
        self.liveDebug = liveDebug
        self.pcHistoryEnabled = pcHistoryEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, owner: owner, telemetry: telemetry,
                    supervisor: supervisor, liveDebug: liveDebug)
    }

    func makeUIView(context: Context) -> WKWebView {
        let handler = context.coordinator.handler
        let configuration = WebConfigurationFactory.make(owner: owner, handler: handler,
                                                         pcHistoryEnabled: pcHistoryEnabled && supervisor?.isSafeModeActive != true)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.accessibilityIdentifier = "optimized.webview"
        handler.webView = webView
        context.coordinator.webView = webView
        liveDebug.attach(webView)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isInspectable = model.diagnosticsEnabled
        model.retryHandler = { [weak webView] document, sequence in
            guard let webView else { return false }
            do {
                let result = try await webView.callAsyncJavaScript(
                    "return globalThis.__CHATGPT_WEB_OPTIMIZED_OBSERVER__?.retry(document, sequence) === true;",
                    arguments: ["document": document, "sequence": sequence],
                    in: nil,
                    contentWorld: WebConfigurationFactory.observationWorld)
                return result as? Bool ?? false
            } catch { return false }
        }
        let coordinator = context.coordinator
        let request = URLRequest(url: model.targetURL,
                                 cachePolicy: .useProtocolCachePolicy,
                                 timeoutInterval: 45)
        WebConfigurationFactory.installResourceGate(resourceGate, in: configuration,
                                                     safeMode: supervisor?.isSafeModeActive == true) { _ in
            // Do not navigate a retired web view if the user entered native safe mode.
            guard coordinator.webView === webView, !model.processTerminated else { return }
            webView.load(request)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isInspectable = model.diagnosticsEnabled
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.liveDebug.detach(webView)
        coordinator.owner.invalidateDocument()
        coordinator.model.retryHandler = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: WebConfigurationFactory.handlerName,
            contentWorld: WebConfigurationFactory.observationWorld)
        coordinator.webView = nil
        coordinator.handler.webView = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        let model: OptimizedAppModel
        let owner: ConversationManagerOwner
        let telemetry: OptimizedTelemetry
        let liveDebug: OptimizedLiveDebug
        weak var supervisor: NativeOptimizationSupervisor?
        let handler: WeakOptimizedObservationHandler
        weak var webView: WKWebView?
        private var destinations: [ObjectIdentifier: URL] = [:]
        private var hasTerminated = false

        init(model: OptimizedAppModel,
             owner: ConversationManagerOwner,
             telemetry: OptimizedTelemetry,
             supervisor: NativeOptimizationSupervisor?,
             liveDebug: OptimizedLiveDebug) {
            self.model = model
            self.owner = owner
            self.telemetry = telemetry
            self.liveDebug = liveDebug
            self.supervisor = supervisor
            handler = WeakOptimizedObservationHandler(owner: owner)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            owner.invalidateDocument()
            model.status = "正在加载"
            telemetry.record(.navigationStart, route: routeCategory(for: webView))
            liveDebug.navigationStart()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.markReady()
            telemetry.record(.navigationFinish, route: routeCategory(for: webView))
            liveDebug.navigationFinish()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.status = "页面加载失败"
            recordNavigationError(error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.status = "无法打开页面"
            recordNavigationError(error, webView: webView)
        }

        /// On WebContent termination:
        /// Invalidate ConversationManagerOwner generation, detach old handlers,
        /// call supervisor exactly once, record content-free telemetry,
        /// and show native Safe Mode without automatically regenerating WKWebView.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard self.webView === webView, !hasTerminated else { return }
            hasTerminated = true
            let route = routeCategory(for: webView)
            telemetry.record(.contentTerminated, route: route, urgent: true)
            liveDebug.processTerminated()
            owner.invalidateDocument(processTerminated: true)
            handler.webView = nil
            model.retryHandler = nil
            model.markProcessTerminated(route: route, isSynthetic: false)
            if let sup = supervisor ?? model.supervisor, sup.isCircuitOpen {
                telemetry.record(.recoveryPaused, route: route, urgent: true)
            }
        }

        private func recordNavigationError(_ error: Error, webView: WKWebView) {
            let code = (error as NSError).code
            // -999 is cancellation during ordinary navigation, not a page failure.
            guard code != NSURLErrorCancelled else { return }
            telemetry.record(.navigationError, route: routeCategory(for: webView),
                             errorCode: code, urgent: true)
            liveDebug.navigationError()
        }

        private func routeCategory(for webView: WKWebView) -> String {
            guard let url = webView.url, url.host == "chatgpt.com" else { return "other" }
            let path = url.path
            if path.contains("/g/") { return "project" }
            if path.hasPrefix("/c/") { return "conversation" }
            return "home"
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            guard let scheme = url.scheme?.lowercased() else { decisionHandler(.cancel); return }
            if scheme == "https" || scheme == "http" {
                if navigationAction.navigationType == .linkActivated,
                   let host = url.host?.lowercased(),
                   host != "chatgpt.com" && !host.hasSuffix(".chatgpt.com") &&
                   host != "openai.com" && !host.hasSuffix(".openai.com") {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
                return
            }
            if UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let response = navigationResponse.response as? HTTPURLResponse
            let disposition = response?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
            if !navigationResponse.canShowMIMEType || disposition.contains("attachment") {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                if url.scheme == "https" { webView.load(URLRequest(url: url)) }
                else if UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
            }
            return nil
        }

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let host = origin.host.lowercased()
            decisionHandler(host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") ? .prompt : .deny)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let controller = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            present(controller)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let controller = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            controller.addAction(UIAlertAction(title: "继续", style: .default) { _ in completionHandler(true) })
            present(controller)
        }

        func webView(_ webView: WKWebView,
                     navigationAction: WKNavigationAction,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView,
                     navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let safe = suggestedFilename
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\\", with: "-")
                .prefix(120)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ChatGPTWebOptimized-\(UUID().uuidString)-\(safe)")
            destinations[ObjectIdentifier(download)] = url
            completionHandler(url)
        }

        func downloadDidFinish(_ download: WKDownload) {
            model.downloadedFile = destinations.removeValue(forKey: ObjectIdentifier(download))
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            destinations.removeValue(forKey: ObjectIdentifier(download))
            model.status = "下载失败"
            telemetry.record(.downloadError, errorCode: (error as NSError).code, urgent: true)
        }

        private func present(_ controller: UIViewController) {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
                  let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
            var visible = root
            while let next = visible.presentedViewController { visible = next }
            visible.present(controller, animated: true)
        }
    }
}
