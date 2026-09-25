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

        let initialScript =
            scriptStore.bestLocalScript()

        let initialGestureScript =
            scriptStore.bestLocalGestureScript()

        controller.add(
            context.coordinator,
            name: Coordinator.nativeMessageHandler
        )

        installUserScripts(
            on: controller,
            payload: initialScript,
            gesturePayload: initialGestureScript,
            status:
                initialScript?.origin == "cached"
                ? "cached"
                : "bundled",
            gestureStatus:
                initialGestureScript?.origin == "cached"
                ? "cached"
                : "bundled"
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences
            .allowsContentJavaScript = true
        configuration.preferences
            .javaScriptCanOpenWindowsAutomatically = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // History navigation gestures stay disabled.
        // Sidebar gestures are provided only by the iOS gesture userscript.
        webView.allowsBackForwardNavigationGestures = false

        webView.allowsLinkPreview = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        context.coordinator.attach(
            webView: webView,
            contentController: controller,
            initialScript: initialScript,
            initialGestureScript: initialGestureScript
        )

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
        uiView.configuration.userContentController
            .removeScriptMessageHandler(
                forName: Coordinator.nativeMessageHandler
            )
    }

    private func installUserScripts(
        on controller: WKUserContentController,
        payload: UnifiedScriptPayload?,
        gesturePayload: UnifiedScriptPayload?,
        status: String,
        gestureStatus: String
    ) {
        let store = UnifiedScriptStore.shared

        controller.addUserScript(
            WKUserScript(
                source: store.nativeBootstrap(
                    scriptVersion:
                        payload?.version ?? "missing",
                    scriptOrigin:
                        payload?.origin ?? "none",
                    updateStatus: "checking",
                    gestureVersion:
                        gesturePayload?.version,
                    gestureOrigin:
                        gesturePayload?.origin,
                    gestureUpdateStatus: "checking"
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        if let payload {
            controller.addUserScript(
                WKUserScript(
                    source: payload.source,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }

        if let gesturePayload {
            controller.addUserScript(
                WKUserScript(
                    source: gesturePayload.source,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }

        controller.addUserScript(
            WKUserScript(
                source: store.runtimeStatusJavaScript(
                    scriptVersion:
                        payload?.version ?? "missing",
                    scriptOrigin:
                        payload?.origin ?? "none",
                    updateStatus: status,
                    gestureVersion:
                        gesturePayload?.version,
                    gestureOrigin:
                        gesturePayload?.origin,
                    gestureUpdateStatus:
                        gestureStatus
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
        WKScriptMessageHandler
    {
        static let nativeMessageHandler = "chatGPTNative"

        private let scriptStore: UnifiedScriptStore
        private var contentController: WKUserContentController?

        private var activeScript: UnifiedScriptPayload?
        private var activeGestureScript: UnifiedScriptPayload?

        private var updateStatus = "bundled"
        private var gestureUpdateStatus = "bundled"
        private var checkingUpdate = false

        weak var webView: WKWebView?

        init(scriptStore: UnifiedScriptStore) {
            self.scriptStore = scriptStore
        }

        func attach(
            webView: WKWebView,
            contentController: WKUserContentController,
            initialScript: UnifiedScriptPayload?,
            initialGestureScript: UnifiedScriptPayload?
        ) {
            self.webView = webView
            self.contentController = contentController
            self.activeScript = initialScript
            self.activeGestureScript =
                initialGestureScript

            self.updateStatus =
                initialScript?.origin == "cached"
                ? "cached"
                : "bundled"

            self.gestureUpdateStatus =
                initialGestureScript?.origin == "cached"
                ? "cached"
                : "bundled"
        }

        func startHotUpdate() {
            guard !checkingUpdate else {
                updateStatus = "checking"
                gestureUpdateStatus = "checking"
                updateRuntimeStatus()
                return
            }

            checkingUpdate = true
            updateStatus = "checking"
            gestureUpdateStatus = "checking"
            updateRuntimeStatus()

            Task { [weak self] in
                guard let self else {
                    return
                }

                var latestScript: UnifiedScriptPayload?
                var latestGesture: UnifiedScriptPayload?

                var scriptFailed = false
                var gestureFailed = false

                do {
                    latestScript =
                        try await self.scriptStore.fetchLatest()
                } catch {
                    scriptFailed = true
                }

                do {
                    latestGesture =
                        try await self.scriptStore
                            .fetchLatestGestureScript()
                } catch {
                    gestureFailed = true
                }

                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }

                    self.checkingUpdate = false

                    let scriptChanged =
                        self.applyScriptResult(
                            latestScript,
                            failed: scriptFailed
                        )

                    let gestureChanged =
                        self.applyGestureResult(
                            latestGesture,
                            failed: gestureFailed
                        )

                    self.installForFutureNavigations()
                    self.updateRuntimeStatus()

                    if scriptChanged,
                       let activeScript =
                           self.activeScript {
                        self.injectScriptIntoCurrentPage(
                            activeScript
                        )
                    }

                    if gestureChanged,
                       let activeGestureScript =
                           self.activeGestureScript {
                        self.injectGestureIntoCurrentPage(
                            activeGestureScript
                        )
                    }
                }
            }
        }

        private func applyScriptResult(
            _ latest: UnifiedScriptPayload?,
            failed: Bool
        ) -> Bool {
            guard let latest else {
                updateStatus =
                    failed ? "offline" : updateStatus
                return false
            }

            let changed =
                activeScript?.version != latest.version ||
                activeScript?.source != latest.source

            activeScript = latest
            updateStatus =
                changed ? "updated" : "latest"

            return changed
        }

        private func applyGestureResult(
            _ latest: UnifiedScriptPayload?,
            failed: Bool
        ) -> Bool {
            guard let latest else {
                gestureUpdateStatus =
                    failed
                    ? "offline"
                    : gestureUpdateStatus
                return false
            }

            let changed =
                activeGestureScript?.version !=
                    latest.version ||
                activeGestureScript?.source !=
                    latest.source

            activeGestureScript = latest
            gestureUpdateStatus =
                changed ? "updated" : "latest"

            return changed
        }

        func userContentController(
            _ userContentController:
                WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard
                message.name ==
                    Self.nativeMessageHandler,
                let body =
                    message.body as? [String: Any],
                body["type"] as? String ==
                    "check-update"
            else {
                return
            }

            startHotUpdate()
        }

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor
                origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler:
                @escaping (WKPermissionDecision) -> Void
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
                decisionHandler(.deny)

            @unknown default:
                decisionHandler(.deny)
            }
        }

        private func installForFutureNavigations() {
            guard let controller = contentController else {
                return
            }

            controller.removeAllUserScripts()

            controller.addUserScript(
                WKUserScript(
                    source: scriptStore.nativeBootstrap(
                        scriptVersion:
                            activeScript?.version ??
                                "missing",
                        scriptOrigin:
                            activeScript?.origin ??
                                "none",
                        updateStatus: updateStatus,
                        gestureVersion:
                            activeGestureScript?.version,
                        gestureOrigin:
                            activeGestureScript?.origin,
                        gestureUpdateStatus:
                            gestureUpdateStatus
                    ),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )

            if let activeScript {
                controller.addUserScript(
                    WKUserScript(
                        source: activeScript.source,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )
            }

            if let activeGestureScript {
                controller.addUserScript(
                    WKUserScript(
                        source:
                            activeGestureScript.source,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )
            }

            controller.addUserScript(
                WKUserScript(
                    source:
                        scriptStore
                            .runtimeStatusJavaScript(
                                scriptVersion:
                                    activeScript?.version ??
                                        "missing",
                                scriptOrigin:
                                    activeScript?.origin ??
                                        "none",
                                updateStatus:
                                    updateStatus,
                                gestureVersion:
                                    activeGestureScript?
                                        .version,
                                gestureOrigin:
                                    activeGestureScript?
                                        .origin,
                                gestureUpdateStatus:
                                    gestureUpdateStatus
                            ),
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }

        private func injectScriptIntoCurrentPage(
            _ payload: UnifiedScriptPayload
        ) {
            guard let webView else {
                return
            }

            webView.evaluateJavaScript(
                payload.source
            ) { [weak self] _, error in
                if error != nil {
                    self?.updateStatus = "error"
                    self?.updateRuntimeStatus()
                }
            }
        }

        private func injectGestureIntoCurrentPage(
            _ payload: UnifiedScriptPayload
        ) {
            guard let webView else {
                return
            }

            webView.evaluateJavaScript(
                payload.source
            ) { [weak self] _, error in
                if error != nil {
                    self?.gestureUpdateStatus =
                        "error"
                    self?.updateRuntimeStatus()
                }
            }
        }

        private func updateRuntimeStatus() {
            guard let webView else {
                return
            }

            webView.evaluateJavaScript(
                scriptStore.runtimeStatusJavaScript(
                    scriptVersion:
                        activeScript?.version ??
                            "missing",
                    scriptOrigin:
                        activeScript?.origin ??
                            "none",
                    updateStatus: updateStatus,
                    gestureVersion:
                        activeGestureScript?.version,
                    gestureOrigin:
                        activeGestureScript?.origin,
                    gestureUpdateStatus:
                        gestureUpdateStatus
                )
            )
        }

        private func ensureScriptsAreRunning() {
            guard let webView else {
                return
            }

            if let activeScript {
                webView.evaluateJavaScript(
                    "typeof window.ChatGPTWeb === 'object'"
                ) { [weak self] result, _ in
                    guard
                        let self,
                        (result as? Bool) != true
                    else {
                        return
                    }

                    self.injectScriptIntoCurrentPage(
                        activeScript
                    )
                }
            }

            if let activeGestureScript {
                webView.evaluateJavaScript(
                    """
                    typeof window.ChatGPTIOSGestures ===
                      'object'
                    """
                ) { [weak self] result, _ in
                    guard
                        let self,
                        (result as? Bool) != true
                    else {
                        return
                    }

                    self.injectGestureIntoCurrentPage(
                        activeGestureScript
                    )
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            ensureScriptsAreRunning()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration:
                WKWebViewConfiguration,
            for navigationAction:
                WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(
                    navigationAction.request
                )
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
            didFailProvisionalNavigation
                navigation: WKNavigation!,
            withError error: Error
        ) {
            let nsError = error as NSError

            guard
                nsError.code !=
                    NSURLErrorCancelled
            else {
                return
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage
                message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler:
                @escaping () -> Void
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
            runJavaScriptConfirmPanelWithMessage
                message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler:
                @escaping (Bool) -> Void
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
            guard let presenter =
                topViewController()
            else {
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

        private func topViewController()
            -> UIViewController?
        {
            guard
                let scene =
                    UIApplication.shared
                        .connectedScenes
                        .compactMap({
                            $0 as? UIWindowScene
                        })
                        .first(where: {
                            $0.activationState ==
                                .foregroundActive
                        }),
                let root =
                    scene.windows
                        .first(where: {
                            $0.isKeyWindow
                        })?
                        .rootViewController
            else {
                return nil
            }

            var current = root

            while let presented =
                current.presentedViewController {
                current = presented
            }

            return current
        }
    }
}
