import SwiftUI
import UIKit
import WebKit

struct ChatGPTWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(scriptStore: .shared)
    }

    func makeUIView(context: Context) -> WKWebView {
        let scriptStore = UnifiedScriptStore.shared
        let controller = WKUserContentController()
        let initialScript = scriptStore.bestLocalScript()

        installUserScripts(
            on: controller,
            payload: initialScript,
            status: initialScript?.origin == "cached" ? "cached" : "bundled"
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        context.coordinator.attach(
            webView: webView,
            contentController: controller,
            initialScript: initialScript
        )

        var request = URLRequest(url: URL(string: "https://chatgpt.com/")!)
        request.cachePolicy = .useProtocolCachePolicy
        webView.load(request)

        context.coordinator.startHotUpdate()

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func installUserScripts(
        on controller: WKUserContentController,
        payload: UnifiedScriptPayload?,
        status: String
    ) {
        let store = UnifiedScriptStore.shared
        let version = payload?.version ?? "missing"
        let origin = payload?.origin ?? "none"

        controller.addUserScript(
            WKUserScript(
                source: store.nativeBootstrap(
                    scriptVersion: version,
                    scriptOrigin: origin,
                    updateStatus: "checking"
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        guard let payload else { return }

        controller.addUserScript(
            WKUserScript(
                source: payload.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        controller.addUserScript(
            WKUserScript(
                source: store.runtimeStatusJavaScript(
                    scriptVersion: payload.version,
                    scriptOrigin: payload.origin,
                    updateStatus: status
                ),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let scriptStore: UnifiedScriptStore
        private var contentController: WKUserContentController?
        private var activeScript: UnifiedScriptPayload?
        weak var webView: WKWebView?

        init(scriptStore: UnifiedScriptStore) {
            self.scriptStore = scriptStore
        }

        func attach(
            webView: WKWebView,
            contentController: WKUserContentController,
            initialScript: UnifiedScriptPayload?
        ) {
            self.webView = webView
            self.contentController = contentController
            self.activeScript = initialScript
        }

        func startHotUpdate() {
            Task { [weak self] in
                guard let self else { return }

                do {
                    let latest = try await self.scriptStore.fetchLatest()
                    DispatchQueue.main.async { [weak self] in
                        self?.applyHotUpdate(latest)
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.updateRuntimeStatus("offline")
                    }
                }
            }
        }

        private func applyHotUpdate(_ latest: UnifiedScriptPayload) {
            let changed =
                activeScript?.version != latest.version ||
                activeScript?.source != latest.source

            activeScript = latest
            installForFutureNavigations(latest)

            if changed {
                injectIntoCurrentPage(
                    latest,
                    updateStatus: "updated"
                )
            } else {
                updateRuntimeStatus("latest")
            }
        }

        private func installForFutureNavigations(
            _ payload: UnifiedScriptPayload
        ) {
            guard let controller = contentController else { return }

            controller.removeAllUserScripts()

            controller.addUserScript(
                WKUserScript(
                    source: scriptStore.nativeBootstrap(
                        scriptVersion: payload.version,
                        scriptOrigin: "cached",
                        updateStatus: "latest"
                    ),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )

            controller.addUserScript(
                WKUserScript(
                    source: payload.source,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }

        private func injectIntoCurrentPage(
            _ payload: UnifiedScriptPayload,
            updateStatus: String
        ) {
            guard let webView else { return }

            let bootstrap = scriptStore.nativeBootstrap(
                scriptVersion: payload.version,
                scriptOrigin: payload.origin,
                updateStatus: updateStatus
            )

            webView.evaluateJavaScript(
                bootstrap + "\n" + payload.source
            ) { [weak self] _, error in
                if error != nil {
                    self?.updateRuntimeStatus("error")
                }
            }
        }

        private func updateRuntimeStatus(_ status: String) {
            guard let webView else { return }

            let version = activeScript?.version ?? "missing"
            let origin = activeScript?.origin ?? "none"

            webView.evaluateJavaScript(
                scriptStore.runtimeStatusJavaScript(
                    scriptVersion: version,
                    scriptOrigin: origin,
                    updateStatus: status
                )
            )
        }

        private func ensureScriptIsRunning() {
            guard let webView, let activeScript else { return }

            webView.evaluateJavaScript(
                "typeof window.ChatGPTWeb === 'object'"
            ) { [weak self] result, _ in
                guard
                    let self,
                    (result as? Bool) != true
                else {
                    return
                }

                self.injectIntoCurrentPage(
                    activeScript,
                    updateStatus: activeScript.origin == "cached"
                        ? "cached"
                        : "bundled"
                )
            }
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            ensureScriptIsRunning()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            presentAlert(title: nil, message: message, actions: [
                UIAlertAction(title: "OK", style: .default) { _ in
                    completionHandler()
                }
            ])
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            presentAlert(title: nil, message: message, actions: [
                UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    completionHandler(false)
                },
                UIAlertAction(title: "OK", style: .default) { _ in
                    completionHandler(true)
                }
            ])
        }

        private func presentAlert(
            title: String?,
            message: String,
            actions: [UIAlertAction]
        ) {
            guard let presenter = topViewController() else { return }

            let alert = UIAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )

            actions.forEach(alert.addAction)
            presenter.present(alert, animated: true)
        }

        private func topViewController() -> UIViewController? {
            guard
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: {
                        $0.activationState == .foregroundActive
                    }),
                let root = scene.windows
                    .first(where: { $0.isKeyWindow })?
                    .rootViewController
            else {
                return nil
            }

            var current = root
            while let presented = current.presentedViewController {
                current = presented
            }
            return current
        }
    }
}
