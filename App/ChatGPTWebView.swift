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

        private var browserControlsExpanded = false

        private weak var externalWebView: WKWebView?
        private weak var browserControlButton: UIButton?
        private weak var browserMenuView: UIVisualEffectView?
        private weak var browserBackButton: UIButton?
        private weak var browserForwardButton: UIButton?

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

                async let sharedResult =
                    self.fetchSharedUpdateResult()

                async let gestureResult =
                    self.fetchGestureUpdateResult()

                let results = await (
                    sharedResult,
                    gestureResult
                )

                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }

                    self.checkingUpdate = false

                    let scriptChanged =
                        self.applyScriptResult(
                            results.0
                        )

                    let gestureChanged =
                        self.applyGestureResult(
                            results.1
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

        private func fetchSharedUpdateResult()
            async -> Result<UnifiedScriptPayload, Error>
        {
            do {
                return .success(
                    try await scriptStore.fetchLatest()
                )
            } catch {
                return .failure(error)
            }
        }

        private func fetchGestureUpdateResult()
            async -> Result<UnifiedScriptPayload, Error>
        {
            do {
                return .success(
                    try await scriptStore
                        .fetchLatestGestureScript()
                )
            } catch {
                return .failure(error)
            }
        }

        private func failureStatus(
            _ error: Error
        ) -> String {
            if let urlError = error as? URLError,
               urlError.code == .timedOut {
                return "timeout"
            }

            return "offline"
        }

        private func applyScriptResult(
            _ result:
                Result<UnifiedScriptPayload, Error>
        ) -> Bool {
            switch result {
            case .success(let latest):
                let changed =
                    activeScript?.version != latest.version ||
                    activeScript?.source != latest.source

                activeScript = latest
                updateStatus =
                    changed ? "updated" : "latest"

                return changed

            case .failure(let error):
                updateStatus =
                    failureStatus(error)
                return false
            }
        }

        private func applyGestureResult(
            _ result:
                Result<UnifiedScriptPayload, Error>
        ) -> Bool {
            switch result {
            case .success(let latest):
                let changed =
                    activeGestureScript?.version !=
                        latest.version ||
                    activeGestureScript?.source !=
                        latest.source

                activeGestureScript = latest
                gestureUpdateStatus =
                    changed ? "updated" : "latest"

                return changed

            case .failure(let error):
                gestureUpdateStatus =
                    failureStatus(error)
                return false
            }
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

        private func makeBrowserActionButton(
            systemName: String,
            accessibilityLabel: String,
            action: Selector
        ) -> UIButton {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false

            button.setImage(
                UIImage(systemName: systemName),
                for: .normal
            )

            button.tintColor = .label
            button.accessibilityLabel =
                accessibilityLabel

            button.addTarget(
                self,
                action: action,
                for: .touchUpInside
            )

            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(
                    equalToConstant: 40
                ),
                button.heightAnchor.constraint(
                    equalToConstant: 40
                )
            ])

            return button
        }

        private func installExternalBrowserControls(
            on webView: WKWebView
        ) {
            guard browserControlButton == nil else {
                return
            }

            let control = UIButton(type: .system)
            control.translatesAutoresizingMaskIntoConstraints = false
            control.setImage(
                UIImage(systemName: "safari"),
                for: .normal
            )
            control.tintColor = .label
            control.backgroundColor =
                UIColor.secondarySystemBackground
                    .withAlphaComponent(0.94)

            control.layer.cornerRadius = 22
            control.layer.shadowColor =
                UIColor.black.cgColor
            control.layer.shadowOpacity = 0.18
            control.layer.shadowRadius = 8
            control.layer.shadowOffset =
                CGSize(width: 0, height: 3)

            control.accessibilityLabel =
                "网页控制"

            control.addTarget(
                self,
                action:
                    #selector(toggleExternalBrowserMenu),
                for: .touchUpInside
            )

            let back = makeBrowserActionButton(
                systemName: "chevron.backward",
                accessibilityLabel: "后退",
                action: #selector(browserBack)
            )

            let forward = makeBrowserActionButton(
                systemName: "chevron.forward",
                accessibilityLabel: "前进",
                action: #selector(browserForward)
            )

            let reload = makeBrowserActionButton(
                systemName: "arrow.clockwise",
                accessibilityLabel: "刷新",
                action: #selector(browserReload)
            )

            let close = makeBrowserActionButton(
                systemName: "xmark",
                accessibilityLabel: "关闭并返回 ChatGPT",
                action: #selector(browserClose)
            )

            let stack = UIStackView(
                arrangedSubviews: [
                    back,
                    forward,
                    reload,
                    close
                ]
            )

            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .horizontal
            stack.alignment = .center
            stack.distribution = .fillEqually
            stack.spacing = 2

            let blur = UIVisualEffectView(
                effect: UIBlurEffect(
                    style: .systemMaterial
                )
            )

            blur.translatesAutoresizingMaskIntoConstraints = false
            blur.layer.cornerRadius = 22
            blur.clipsToBounds = true
            blur.isHidden = true

            blur.contentView.addSubview(stack)
            webView.addSubview(blur)
            webView.addSubview(control)

            NSLayoutConstraint.activate([
                control.widthAnchor.constraint(
                    equalToConstant: 44
                ),
                control.heightAnchor.constraint(
                    equalToConstant: 44
                ),
                control.trailingAnchor.constraint(
                    equalTo:
                        webView.safeAreaLayoutGuide
                            .trailingAnchor,
                    constant: -10
                ),
                control.topAnchor.constraint(
                    equalTo:
                        webView.safeAreaLayoutGuide
                            .topAnchor,
                    constant: 10
                ),

                blur.trailingAnchor.constraint(
                    equalTo: control.leadingAnchor,
                    constant: -8
                ),
                blur.centerYAnchor.constraint(
                    equalTo: control.centerYAnchor
                ),
                blur.widthAnchor.constraint(
                    equalToConstant: 176
                ),
                blur.heightAnchor.constraint(
                    equalToConstant: 44
                ),

                stack.leadingAnchor.constraint(
                    equalTo: blur.contentView.leadingAnchor,
                    constant: 4
                ),
                stack.trailingAnchor.constraint(
                    equalTo: blur.contentView.trailingAnchor,
                    constant: -4
                ),
                stack.topAnchor.constraint(
                    equalTo: blur.contentView.topAnchor,
                    constant: 2
                ),
                stack.bottomAnchor.constraint(
                    equalTo: blur.contentView.bottomAnchor,
                    constant: -2
                )
            ])

            browserControlButton = control
            browserMenuView = blur
            browserBackButton = back
            browserForwardButton = forward

            control.isHidden = false
        }

        private func collapseExternalBrowserMenu() {
            browserControlsExpanded = false
            browserMenuView?.isHidden = true
        }

        private func updateExternalBrowserControls() {
            guard
                let externalWebView,
                externalWebView.superview != nil
            else {
                return
            }

            browserControlButton?.isHidden = false

            browserBackButton?.isEnabled =
                externalWebView.canGoBack

            browserBackButton?.alpha =
                externalWebView.canGoBack ? 1.0 : 0.35

            browserForwardButton?.isEnabled =
                externalWebView.canGoForward

            browserForwardButton?.alpha =
                externalWebView.canGoForward ? 1.0 : 0.35

            if let menu = browserMenuView {
                externalWebView.bringSubviewToFront(menu)
            }

            if let button = browserControlButton {
                externalWebView.bringSubviewToFront(button)
            }
        }

        @objc private func toggleExternalBrowserMenu() {
            browserControlsExpanded.toggle()
            browserMenuView?.isHidden =
                !browserControlsExpanded

            updateExternalBrowserControls()
        }

        @objc private func browserBack() {
            guard
                let externalWebView,
                externalWebView.canGoBack
            else {
                return
            }

            collapseExternalBrowserMenu()
            externalWebView.goBack()
        }

        @objc private func browserForward() {
            guard
                let externalWebView,
                externalWebView.canGoForward
            else {
                return
            }

            collapseExternalBrowserMenu()
            externalWebView.goForward()
        }

        @objc private func browserReload() {
            collapseExternalBrowserMenu()
            externalWebView?.reload()
        }

        @objc private func browserClose() {
            guard let externalWebView else {
                return
            }

            browserControlsExpanded = false
            externalWebView.stopLoading()
            externalWebView.navigationDelegate = nil
            externalWebView.uiDelegate = nil
            externalWebView.removeFromSuperview()

            self.externalWebView = nil
            browserControlButton = nil
            browserMenuView = nil
            browserBackButton = nil
            browserForwardButton = nil
        }

        private func presentExternalWebView(
            configuration: WKWebViewConfiguration
        ) -> WKWebView? {
            guard
                externalWebView == nil,
                let webView
            else {
                return nil
            }

            let external = WKWebView(
                frame: .zero,
                configuration: configuration
            )

            external.translatesAutoresizingMaskIntoConstraints = false
            external.navigationDelegate = self
            external.uiDelegate = self
            external.allowsBackForwardNavigationGestures = false
            external.allowsLinkPreview = true
            external.scrollView.keyboardDismissMode = .interactive
            external.scrollView.contentInsetAdjustmentBehavior = .automatic
            external.backgroundColor = .systemBackground
            external.isOpaque = true

            webView.addSubview(external)

            NSLayoutConstraint.activate([
                external.leadingAnchor.constraint(
                    equalTo: webView.leadingAnchor
                ),
                external.trailingAnchor.constraint(
                    equalTo: webView.trailingAnchor
                ),
                external.topAnchor.constraint(
                    equalTo: webView.topAnchor
                ),
                external.bottomAnchor.constraint(
                    equalTo: webView.bottomAnchor
                )
            ])

            self.externalWebView = external
            installExternalBrowserControls(on: external)
            updateExternalBrowserControls()

            return external
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
            didStartProvisionalNavigation
                navigation: WKNavigation!
        ) {
            if webView === externalWebView {
                collapseExternalBrowserMenu()
            }
        }

        func webView(
            _ webView: WKWebView,
            didCommit navigation: WKNavigation!
        ) {
            if webView === externalWebView {
                updateExternalBrowserControls()
            }
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            if webView === externalWebView {
                updateExternalBrowserControls()
                return
            }

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
            guard navigationAction.targetFrame == nil else {
                return nil
            }

            if let externalWebView {
                externalWebView.load(
                    navigationAction.request
                )
                return nil
            }

            return presentExternalWebView(
                configuration: configuration
            )
        }

        func webViewWebContentProcessDidTerminate(
            _ webView: WKWebView
        ) {
            webView.reload()

            if webView === externalWebView {
                updateExternalBrowserControls()
            }
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
