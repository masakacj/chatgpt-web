import Foundation
import SwiftUI
import UIKit
import WebKit

@MainActor
final class WebViewStore: NSObject, ObservableObject {
    let webView: WKWebView

    @Published private(set) var metrics = PerfMetrics()
    @Published private(set) var isLoading = false
    @Published private(set) var pageTitle = "ChatGPT"
    @Published private(set) var processRestarts = 0
    @Published private(set) var lastError: String?

    private let userContentController: WKUserContentController
    private var performanceScript: String
    private var engineVersion: String
    private var remoteConfig: RemotePerfConfig
    private var mode: OptimizationMode
    private var keepRecentTurns: Int
    private var weakMessageHandler: WeakScriptMessageHandler?

    init(
        performanceScript: String,
        engineVersion: String,
        remoteConfig: RemotePerfConfig,
        mode: OptimizationMode,
        keepRecentTurns: Int
    ) {
        self.performanceScript = performanceScript
        self.engineVersion = engineVersion
        self.remoteConfig = remoteConfig
        self.mode = mode
        self.keepRecentTurns = keepRecentTurns

        let controller = WKUserContentController()
        self.userContentController = controller

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.mediaTypesRequiringUserActionForPlayback = [.audio, .video]

        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        let weakHandler = WeakScriptMessageHandler(target: self)
        self.weakMessageHandler = weakHandler
        controller.add(weakHandler, name: "perf")

        installUserScripts()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        loadHome()
    }

    func loadHome() {
        webView.load(URLRequest(url: AppConfig.homeURL))
    }

    func reload() {
        if webView.url == nil {
            loadHome()
        } else {
            webView.reload()
        }
    }

    func hardReload() {
        if webView.url == nil {
            loadHome()
        } else {
            webView.reloadFromOrigin()
        }
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    func setOptimizationMode(_ newMode: OptimizationMode) {
        mode = newMode
        let value = jsonString(newMode.rawValue)
        webView.evaluateJavaScript("window.ChatGPTPerf?.setMode?.(\(value));")
    }

    func setKeepRecentTurns(_ value: Int) {
        keepRecentTurns = min(max(value, 8), 40)
        webView.evaluateJavaScript("window.ChatGPTPerf?.setKeepRecent?.(\(keepRecentTurns));")
    }

    func handleMemoryWarning() {
        webView.evaluateJavaScript("window.ChatGPTPerf?.onMemoryWarning?.();")
    }

    func installPerformanceScript(
        _ script: String,
        engineVersion: String,
        remoteConfig: RemotePerfConfig,
        reload: Bool
    ) {
        self.performanceScript = script
        self.engineVersion = engineVersion
        self.remoteConfig = remoteConfig
        installUserScripts()

        if reload {
            hardReload()
        }
    }

    func clearWebCaches() async {
        let dataStore = WKWebsiteDataStore.default()
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]

        await withCheckedContinuation { continuation in
            dataStore.removeData(
                ofTypes: types,
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) {
                continuation.resume()
            }
        }
    }

    func openCurrentInSafari() {
        guard let url = webView.url else { return }
        UIApplication.shared.open(url)
    }

    private func installUserScripts() {
        userContentController.removeAllUserScripts()

        let configScript = WKUserScript(
            source: injectedConfigJavaScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(configScript)

        let perfScript = WKUserScript(
            source: performanceScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(perfScript)
    }

    private func injectedConfigJavaScript() -> String {
        let payload: [String: Any] = [
            "appVersion": AppConfig.appVersion,
            "engineVersion": engineVersion,
            "mode": mode.rawValue,
            "keepRecent": keepRecentTurns,
            "remote": [
                "balancedThreshold": remoteConfig.balancedThreshold,
                "aggressiveThreshold": remoteConfig.aggressiveThreshold,
                "extremeThreshold": remoteConfig.extremeThreshold,
                "coldViewportDistance": remoteConfig.coldViewportDistance,
                "extremeViewportDistance": remoteConfig.extremeViewportDistance,
                "unloadMedia": remoteConfig.unloadMedia,
                "packExtreme": remoteConfig.packExtreme,
                "disableAnimations": remoteConfig.disableAnimations,
                "disableBackdropFilters": remoteConfig.disableBackdropFilters
            ]
        ]

        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else {
            return "window.__CHATGPT_WEB_NATIVE__ = {};"
        }

        return "window.__CHATGPT_WEB_NATIVE__ = \(json);"
    }

    private func jsonString(_ value: String) -> String {
        guard
            let data = try? JSONEncoder().encode(value),
            let json = String(data: data, encoding: .utf8)
        else {
            return "\"\(value)\""
        }
        return json
    }

    private func isInternalHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }

        let allowed = [
            "chatgpt.com",
            "openai.com",
            "auth.openai.com",
            "login.openai.com",
            "accounts.google.com",
            "appleid.apple.com",
            "auth0.com"
        ]

        return allowed.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private func updateMetrics(from body: [String: Any]) {
        guard (body["type"] as? String) == "metrics" else { return }

        metrics = PerfMetrics(
            turns: body["turns"] as? Int ?? 0,
            hot: body["hot"] as? Int ?? 0,
            warm: body["warm"] as? Int ?? 0,
            cold: body["cold"] as? Int ?? 0,
            packed: body["packed"] as? Int ?? 0,
            domNodes: body["domNodes"] as? Int ?? 0,
            longTaskMs: body["longTaskMs"] as? Double ?? 0,
            streaming: body["streaming"] as? Bool ?? false,
            effectiveMode: body["effectiveMode"] as? String ?? "off",
            engineVersion: body["engineVersion"] as? String ?? engineVersion
        )
    }
}

extension WebViewStore: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "perf", let body = message.body as? [String: Any] else { return }
        Task { @MainActor [weak self] in
            self?.updateMetrics(from: body)
        }
    }
}

extension WebViewStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        lastError = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        pageTitle = webView.title ?? "ChatGPT"
        setOptimizationMode(mode)
        setKeepRecentTurns(keepRecentTurns)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        isLoading = false
        lastError = error.localizedDescription
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        isLoading = false
        lastError = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        processRestarts += 1
        lastError = "WebKit 进程被系统回收，已自动恢复"
        webView.reload()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            decisionHandler(.allow)
            return
        }

        if isInternalHost(url.host) {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
            return
        }

        if navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

extension WebViewStore: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        if isInternalHost(url.host) {
            webView.load(navigationAction.request)
        } else {
            UIApplication.shared.open(url)
        }
        return nil
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
