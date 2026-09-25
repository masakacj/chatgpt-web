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

        controller.add(
            context.coordinator,
            name: Coordinator.nativeMessageHandler
        )

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
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Disable WebKit history swipes. Left edge is reserved for Chat sidebar.
        webView.allowsBackForwardNavigationGestures = false

        webView.allowsLinkPreview = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        context.coordinator.attach(
            webView: webView,
            contentController: controller,
            initialScript: initialScript
        )

        let sidebarGesture = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLeftEdgePan(_:))
        )
        sidebarGesture.edges = .left
        sidebarGesture.maximumNumberOfTouches = 1
        sidebarGesture.cancelsTouchesInView = true
        webView.addGestureRecognizer(sidebarGesture)

        let closeSidebarGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCloseSidebarPan(_:))
        )
        closeSidebarGesture.name = "closeSidebarGesture"
        closeSidebarGesture.maximumNumberOfTouches = 1
        closeSidebarGesture.cancelsTouchesInView = false
        closeSidebarGesture.delegate = context.coordinator
        webView.addGestureRecognizer(closeSidebarGesture)

        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/")!
        )
        request.cachePolicy = .useProtocolCachePolicy
        webView.load(request)

        context.coordinator.startHotUpdate()

        return webView
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {}

    static func dismantleUIView(
        _ uiView: WKWebView,
        coordinator: Coordinator
    ) {
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.nativeMessageHandler
        )
    }

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

        guard let payload else {
            return
        }

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

    final class Coordinator:
        NSObject,
        WKNavigationDelegate,
        WKUIDelegate,
        WKScriptMessageHandler,
        UIGestureRecognizerDelegate
    {
        static let nativeMessageHandler = "chatGPTNative"

        private let scriptStore: UnifiedScriptStore
        private var contentController: WKUserContentController?
        private var activeScript: UnifiedScriptPayload?
        private var checkingUpdate = false
        private var sidebarGestureOpened = false
        private var sidebarGestureClosed = false

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
            guard !checkingUpdate else {
                updateRuntimeStatus("checking")
                return
            }

            checkingUpdate = true
            updateRuntimeStatus("checking")

            Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    let latest = try await self.scriptStore.fetchLatest()

                    await MainActor.run { [weak self] in
                        guard let self else {
                            return
                        }

                        self.checkingUpdate = false
                        self.applyHotUpdate(latest)
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        guard let self else {
                            return
                        }

                        self.checkingUpdate = false
                        self.updateRuntimeStatus("offline")
                    }
                }
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard
                message.name == Self.nativeMessageHandler,
                let body = message.body as? [String: Any],
                body["type"] as? String == "check-update"
            else {
                return
            }

            startHotUpdate()
        }

        @objc func handleLeftEdgePan(
            _ gesture: UIScreenEdgePanGestureRecognizer
        ) {
            guard let webView else {
                return
            }

            switch gesture.state {
            case .began:
                sidebarGestureOpened = false

            case .changed:
                guard !sidebarGestureOpened else {
                    return
                }

                let translation = gesture.translation(in: webView)
                let velocity = gesture.velocity(in: webView)

                let horizontalEnough =
                    translation.x >= 46 &&
                    translation.x > abs(translation.y) * 1.15

                guard
                    horizontalEnough,
                    velocity.x >= 0
                else {
                    return
                }

                sidebarGestureOpened = true

                webView.evaluateJavaScript(
                    "window.ChatGPTWeb?.openSidebar?.() ?? false"
                )

            case .ended, .cancelled, .failed:
                sidebarGestureOpened = false

            default:
                break
            }
        }

        @objc func handleCloseSidebarPan(
            _ gesture: UIPanGestureRecognizer
        ) {
            guard let webView else {
                return
            }

            switch gesture.state {
            case .began:
                sidebarGestureClosed = false

            case .changed:
                guard !sidebarGestureClosed else {
                    return
                }

                let translation = gesture.translation(in: webView)
                let velocity = gesture.velocity(in: webView)

                let horizontalEnough =
                    translation.x >= 56 &&
                    translation.x > abs(translation.y) * 1.2

                guard
                    horizontalEnough,
                    velocity.x > 0
                else {
                    return
                }

                sidebarGestureClosed = true

                webView.evaluateJavaScript(
                    """
                    (() => {
                      if (!window.ChatGPTWeb?.isSidebarOpen?.()) {
                        return false;
                      }
                      return window.ChatGPTWeb?.closeSidebar?.() ?? false;
                    })()
                    """
                )

            case .ended, .cancelled, .failed:
                sidebarGestureClosed = false

            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard
                gestureRecognizer.name == "closeSidebarGesture",
                let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let webView
            else {
                return true
            }

            // Keep the leftmost edge exclusively for the sidebar-open gesture.
            let location = pan.location(in: webView)
            if location.x <= 28 {
                return false
            }

            let velocity = pan.velocity(in: webView)

            return velocity.x > 0 &&
                abs(velocity.x) > abs(velocity.y) * 1.2
        }

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            let host = origin.host.lowercased()
            let trusted =
                host == "chatgpt.com" ||
                host.hasSuffix(".chatgpt.com")

            guard trusted else {
                decisionHandler(.deny)
                return
            }

            switch type {
            case .microphone:
                decisionHandler(.grant)
            case .camera, .cameraAndMicrophone:
                decisionHandler(.prompt)
            @unknown default:
                decisionHandler(.prompt)
            }
        }

        private func applyHotUpdate(
            _ latest: UnifiedScriptPayload
        ) {
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
            guard let controller = contentController else {
                return
            }

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
            guard let webView else {
                return
            }

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

        private func updateRuntimeStatus(
            _ status: String
        ) {
            guard let webView else {
                return
            }

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
            guard
                let webView,
                let activeScript
            else {
                return
            }

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
                    updateStatus:
                        activeScript.origin == "cached"
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

        func webViewWebContentProcessDidTerminate(
            _ webView: WKWebView
        ) {
            webView.reload()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else {
                return
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            presentAlert(
                title: nil,
                message: message,
                actions: [
                    UIAlertAction(
                        title: "OK",
                        style: .default
                    ) { _ in
                        completionHandler()
                    }
                ]
            )
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            presentAlert(
                title: nil,
                message: message,
                actions: [
                    UIAlertAction(
                        title: "Cancel",
                        style: .cancel
                    ) { _ in
                        completionHandler(false)
                    },
                    UIAlertAction(
                        title: "OK",
                        style: .default
                    ) { _ in
                        completionHandler(true)
                    }
                ]
            )
        }

        private func presentAlert(
            title: String?,
            message: String,
            actions: [UIAlertAction]
        ) {
            guard let presenter = topViewController() else {
                return
            }

            let alert = UIAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )

            actions.forEach(alert.addAction)
            presenter.present(
                alert,
                animated: true
            )
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
