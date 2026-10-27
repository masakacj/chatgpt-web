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
    let proxySettings: OptimizerProxySettings

    init(model: OptimizedAppModel,
         owner: ConversationManagerOwner,
         telemetry: OptimizedTelemetry,
         supervisor: NativeOptimizationSupervisor? = nil,
         resourceGate: NativeResourceGate,
         liveDebug: OptimizedLiveDebug,
         pcHistoryEnabled: Bool,
         proxySettings: OptimizerProxySettings) {
        self.model = model
        self.owner = owner
        self.telemetry = telemetry
        self.supervisor = supervisor
        self.resourceGate = resourceGate
        self.liveDebug = liveDebug
        self.pcHistoryEnabled = pcHistoryEnabled
        self.proxySettings = proxySettings
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, owner: owner, telemetry: telemetry,
                    supervisor: supervisor, liveDebug: liveDebug)
    }

    func makeUIView(context: Context) -> WKWebView {
        let handler = context.coordinator.handler
        let (configuration, proxyReady) = WebConfigurationFactory.make(
            owner: owner, handler: handler,
            pcHistoryEnabled: pcHistoryEnabled && supervisor?.isSafeModeActive != true,
            proxySettings: proxySettings)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.accessibilityIdentifier = "optimized.webview"
        handler.webView = webView
        context.coordinator.webView = webView
        context.coordinator.observeBackHistory(of: webView)
        liveDebug.attach(webView)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // ChatGPT owns its sidebar edge gesture; external pages use WebKit history.
        webView.allowsBackForwardNavigationGestures = false
        model.goBackHandler = { [weak webView] in
            guard let webView, webView.canGoBack else { return }
            webView.goBack()
        }
        model.goForwardHandler = { [weak webView] in
            guard let webView, webView.canGoForward else { return }
            webView.goForward()
        }
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
        guard proxyReady else {
            model.status = "代理未就绪：为防止直连，网页没有发起任何请求"
            return webView
        }
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
        coordinator.stopObservingBackHistory()
        coordinator.liveDebug.detach(webView)
        coordinator.owner.invalidateDocument()
        coordinator.model.retryHandler = nil
        coordinator.model.goBackHandler = nil
        coordinator.model.goForwardHandler = nil
        coordinator.model.setCanGoBack(false)
        coordinator.model.setCanGoForward(false)
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
        private var backHistoryObservation: NSKeyValueObservation?
        private var forwardHistoryObservation: NSKeyValueObservation?
        private var currentURLObservation: NSKeyValueObservation?
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

        func observeBackHistory(of webView: WKWebView) {
            let changed: (WKWebView) -> Void = { [weak self] view in
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view, self.webView === view, !self.hasTerminated else { return }
                    self.syncNavigationState(for: view)
                }
            }
            // Same-document ChatGPT SPA history can change without a navigation delegate callback.
            backHistoryObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { view, _ in changed(view) }
            forwardHistoryObservation = webView.observe(\.canGoForward, options: [.initial, .new]) { view, _ in changed(view) }
            currentURLObservation = webView.observe(\.url, options: [.initial, .new]) { view, _ in changed(view) }
        }

        private func syncNavigationState(for webView: WKWebView) {
            model.setCanGoBack(webView.canGoBack)
            model.setCanGoForward(webView.canGoForward)
            // Disable native edge history on chatgpt.com so its sidebar can receive the swipe.
            let host = webView.url?.host?.lowercased() ?? ""
            let external = !host.isEmpty && host != "chatgpt.com" && !host.hasSuffix(".chatgpt.com")
            webView.allowsBackForwardNavigationGestures = external
        }

        func stopObservingBackHistory() {
            backHistoryObservation?.invalidate()
            forwardHistoryObservation?.invalidate()
            currentURLObservation?.invalidate()
            backHistoryObservation = nil
            forwardHistoryObservation = nil
            currentURLObservation = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            syncNavigationState(for: webView)
            owner.invalidateDocument()
            model.status = "正在加载"
            telemetry.record(.navigationStart, route: routeCategory(for: webView))
            liveDebug.navigationStart()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncNavigationState(for: webView)
            model.markReady()
            telemetry.record(.navigationFinish, route: routeCategory(for: webView))
            liveDebug.navigationFinish()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            syncNavigationState(for: webView)
            model.status = "页面加载失败"
            recordNavigationError(error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            syncNavigationState(for: webView)
            recordNavigationError(error, webView: webView)
            model.status = "代理连接失败（不会自动直连或重放请求）"
        }

        /// On WebContent termination:
        /// Invalidate ConversationManagerOwner generation, detach old handlers,
        /// call supervisor exactly once, record content-free telemetry,
        /// and show native Safe Mode without automatically regenerating WKWebView.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard self.webView === webView, !hasTerminated else { return }
            hasTerminated = true
            stopObservingBackHistory()
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

        private func isChatGPTHost(_ url: URL?) -> Bool {
            let host = url?.host?.lowercased() ?? ""
            return host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
        }

        private func shouldConfirmExternalLink(_ url: URL, from webView: WKWebView) -> Bool {
            guard isChatGPTHost(webView.url), let host = url.host?.lowercased() else { return false }
            return host != "chatgpt.com" && !host.hasSuffix(".chatgpt.com") &&
                   host != "openai.com" && !host.hasSuffix(".openai.com")
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            guard let scheme = url.scheme?.lowercased() else { decisionHandler(.cancel); return }
            if scheme == "https" || scheme == "http" {
                if navigationAction.navigationType == .linkActivated,
                   navigationAction.targetFrame != nil,
                   shouldConfirmExternalLink(url, from: webView) {
                    // Target-blank is handled by createWebViewWith; never prompt twice.
                    askBeforeOpeningOutsideProxy(url, in: webView)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
                return
            }
            if UIApplication.shared.canOpenURL(url) { askBeforeOpeningOutsideProxy(url) }
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
                let scheme = url.scheme?.lowercased()
                if scheme == "https" || scheme == "http" {
                    if shouldConfirmExternalLink(url, from: webView) {
                        askBeforeOpeningOutsideProxy(url, in: webView)
                    } else {
                        webView.load(URLRequest(url: url))
                    }
                } else if UIApplication.shared.canOpenURL(url) {
                    askBeforeOpeningOutsideProxy(url)
                }
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

        private func askBeforeOpeningOutsideProxy(_ url: URL, in webView: WKWebView? = nil) {
            let destination = url.host ?? (url.scheme ?? "其他应用")
            let prompt = UIAlertController(
                title: "打开外部链接",
                message: "\(destination) 可在 Optimizer 中通过现有代理打开，滑动或点返回即可回到对话；交给外部应用则不受 Optimizer 代理保护，可能使用手机直连。",
                preferredStyle: .alert)
            prompt.addAction(UIAlertAction(title: "取消", style: .cancel))
            if url.scheme?.lowercased() == "https", let webView {
                prompt.addAction(UIAlertAction(title: "在 Optimizer 内打开（可返回）", style: .default) { [weak webView] _ in
                    guard let webView, self.webView === webView, !self.hasTerminated else { return }
                    webView.load(URLRequest(url: url))
                })
            }
            prompt.addAction(UIAlertAction(title: "仍要在外部应用打开", style: .default) { _ in
                UIApplication.shared.open(url)
            })
            present(prompt)
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
