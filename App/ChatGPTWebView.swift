import SwiftUI
import UIKit
import WebKit

final class ChatGPTFloatingAnchorButton: UIButton {
    var onTap: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragChanged:
        ((CGPoint) -> CGPoint)?
    var onDragEnded: (() -> Void)?

    private var trackingStartPoint =
        CGPoint.zero
    private var trackingStartCenter =
        CGPoint.zero
    private var trackingDidDrag = false

    override func beginTracking(
        _ touch: UITouch,
        with event: UIEvent?
    ) -> Bool {
        guard
            isEnabled,
            let superview
        else {
            return false
        }

        trackingStartPoint =
            touch.location(in: superview)
        trackingStartCenter = center
        trackingDidDrag = false
        isHighlighted = true
        return true
    }

    override func continueTracking(
        _ touch: UITouch,
        with event: UIEvent?
    ) -> Bool {
        guard let superview else {
            return false
        }

        let point =
            touch.location(in: superview)
        let dx =
            point.x -
            trackingStartPoint.x
        let dy =
            point.y -
            trackingStartPoint.y

        if
            !trackingDidDrag,
            sqrt(dx * dx + dy * dy) >= 6
        {
            trackingDidDrag = true
            isHighlighted = false
            onDragBegan?()
        }

        if trackingDidDrag {
            let proposed =
                CGPoint(
                    x:
                        trackingStartCenter.x +
                        dx,
                    y:
                        trackingStartCenter.y +
                        dy
                )

            center =
                onDragChanged?(proposed) ??
                proposed
        }

        return true
    }

    override func endTracking(
        _ touch: UITouch?,
        with event: UIEvent?
    ) {
        isHighlighted = false

        if trackingDidDrag {
            onDragEnded?()
        } else {
            onTap?()
        }

        trackingDidDrag = false
    }

    override func cancelTracking(
        with event: UIEvent?
    ) {
        isHighlighted = false

        if trackingDidDrag {
            onDragEnded?()
        }

        trackingDidDrag = false
    }
}

final class ChatGPTWebContainerView: UIView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)

        backgroundColor = .systemBackground

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(
                equalTo: leadingAnchor
            ),
            webView.trailingAnchor.constraint(
                equalTo: trailingAnchor
            ),
            webView.topAnchor.constraint(
                equalTo: topAnchor
            ),
            webView.bottomAnchor.constraint(
                equalTo: bottomAnchor
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct ChatGPTWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(scriptStore: .shared)
    }

    func makeUIView(
        context: Context
    ) -> ChatGPTWebContainerView {
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

        let container =
            ChatGPTWebContainerView(
                webView: webView
            )

        context.coordinator.attach(
            rootView: container,
            webView: webView,
            contentController: controller,
            initialScript: initialScript,
            initialGestureScript: initialGestureScript
        )

        context.coordinator.installMainAnchor(
            in: container
        )

        let isUITesting =
            ProcessInfo.processInfo.arguments
                .contains("--ui-testing")

        if isUITesting {
            webView.loadHTMLString(
                """
                <!doctype html>
                <html>
                  <head>
                    <meta name="viewport"
                          content="width=device-width,initial-scale=1">
                  </head>
                  <body></body>
                </html>
                """,
                baseURL: URL(
                    string: "https://chatgpt.com/"
                )
            )
        } else {
            var request = URLRequest(
                url: URL(
                    string: "https://chatgpt.com/"
                )!
            )
            request.cachePolicy =
                .useProtocolCachePolicy
            webView.load(request)

            context.coordinator.startHotUpdate()
        }

        return container
    }

    func updateUIView(
        _ uiView: ChatGPTWebContainerView,
        context: Context
    ) {
        context.coordinator.refreshMainAnchor()
    }

    static func dismantleUIView(
        _ uiView: ChatGPTWebContainerView,
        coordinator: Coordinator
    ) {
        uiView.webView.configuration.userContentController
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
        private var contentTerminationTimes: [Date] = []
        private var recoveryAlertPresented = false

        private var latestKnownVersion: String?

        private weak var mainAnchorButton:
            ChatGPTFloatingAnchorButton?

        private static let mainAnchorPositionXKey =
            "ChatGPTWeb.mainAnchorPositionX"
        private static let mainAnchorPositionYKey =
            "ChatGPTWeb.mainAnchorPositionY"

        private weak var externalWebView: WKWebView?
        private weak var browserControlButton: UIButton?
        private weak var browserMenuView: UIVisualEffectView?
        private weak var browserBackButton: UIButton?
        private weak var browserForwardButton: UIButton?
        private var browserControlDragStartTransform =
            CGAffineTransform.identity

        private static let browserControlPositionXKey =
            "ChatGPTWeb.browserControlPositionX"
        private static let browserControlPositionYKey =
            "ChatGPTWeb.browserControlPositionY"

        weak var rootView:
            ChatGPTWebContainerView?
        weak var webView: WKWebView?

        init(scriptStore: UnifiedScriptStore) {
            self.scriptStore = scriptStore
        }

        func attach(
            rootView: ChatGPTWebContainerView,
            webView: WKWebView,
            contentController: WKUserContentController,
            initialScript: UnifiedScriptPayload?,
            initialGestureScript: UnifiedScriptPayload?
        ) {
            self.rootView = rootView
            self.webView = webView
            self.contentController = contentController
            self.activeScript = initialScript
            self.activeGestureScript =
                initialGestureScript
            self.latestKnownVersion =
                initialScript?.version

            self.updateStatus =
                initialScript?.origin == "cached"
                ? "cached"
                : "bundled"

            self.gestureUpdateStatus =
                initialGestureScript?.origin == "cached"
                ? "cached"
                : "bundled"
        }

        func installMainAnchor(
            in rootView: ChatGPTWebContainerView
        ) {
            guard mainAnchorButton == nil else {
                return
            }

            let control =
                ChatGPTFloatingAnchorButton(
                    type: .system
                )
            control.translatesAutoresizingMaskIntoConstraints = true
            control.frame = CGRect(
                x: 0,
                y: 0,
                width: 44,
                height: 44
            )

            control.setTitle("S", for: .normal)
            control.titleLabel?.font =
                UIFont.systemFont(
                    ofSize: 14,
                    weight: .bold
                )
            control.tintColor = .label
            control.backgroundColor =
                UIColor.secondarySystemBackground
                    .withAlphaComponent(0.98)

            control.layer.cornerRadius = 22
            control.layer.shadowColor =
                UIColor.black.cgColor
            control.layer.shadowOpacity = 0.22
            control.layer.shadowRadius = 8
            control.layer.shadowOffset =
                CGSize(width: 0, height: 3)

            control.accessibilityLabel =
                "ChatGPT Web 控制，可拖动"
            control.accessibilityIdentifier =
                "chatgpt.web.floatingAnchor"
            control.isAccessibilityElement = true

            control.onTap = {
                [weak self, weak control] in
                guard
                    let self,
                    let control
                else {
                    return
                }

                control.accessibilityValue =
                    "panel-requested"

                self.toggleScriptPanel(
                    from: control,
                    retry: true
                )
            }

            control.onDragBegan = {
                [weak self] in
                self?.closeScriptPanel()
            }

            control.onDragChanged = {
                [weak self, weak rootView]
                proposed in
                guard
                    let self,
                    let rootView
                else {
                    return proposed
                }

                return self.clampedMainAnchorCenter(
                    proposed,
                    in: rootView
                )
            }

            control.onDragEnded = {
                [weak self, weak control, weak rootView] in
                guard
                    let self,
                    let control,
                    let rootView
                else {
                    return
                }

                self.clampMainAnchor(
                    control,
                    in: rootView
                )
                self.saveMainAnchorPosition(
                    control,
                    in: rootView
                )
            }

            rootView.addSubview(control)
            mainAnchorButton = control

            DispatchQueue.main.async {
                [weak self, weak rootView] in
                guard
                    let self,
                    let rootView
                else {
                    return
                }

                rootView.layoutIfNeeded()
                self.restoreMainAnchorPosition(
                    in: rootView
                )
                rootView.bringSubviewToFront(
                    control
                )
            }
        }

        func refreshMainAnchor() {
            guard
                let rootView,
                let control = mainAnchorButton
            else {
                return
            }

            control.isHidden = false
            control.alpha = 1
            control.isUserInteractionEnabled = true

            clampMainAnchor(
                control,
                in: rootView
            )
            rootView.bringSubviewToFront(
                control
            )
        }

        private func mainAnchorCenterBounds(
            in rootView: UIView
        ) -> (
            minX: CGFloat,
            maxX: CGFloat,
            minY: CGFloat,
            maxY: CGFloat
        ) {
            rootView.layoutIfNeeded()

            var safe =
                rootView.safeAreaLayoutGuide
                    .layoutFrame

            if safe.width <= 0 ||
               safe.height <= 0 {
                safe = rootView.bounds
            }

            let half: CGFloat = 22
            let padding: CGFloat = 6

            let minX =
                safe.minX + half + padding
            let maxX =
                max(
                    minX,
                    safe.maxX - half - padding
                )
            let minY =
                safe.minY + half + padding
            let maxY =
                max(
                    minY,
                    safe.maxY - half - padding
                )

            return (
                minX,
                maxX,
                minY,
                maxY
            )
        }

        private func clampedMainAnchorCenter(
            _ center: CGPoint,
            in rootView: UIView
        ) -> CGPoint {
            let bounds =
                mainAnchorCenterBounds(
                    in: rootView
                )

            return CGPoint(
                x:
                    min(
                        bounds.maxX,
                        max(
                            bounds.minX,
                            center.x
                        )
                    ),
                y:
                    min(
                        bounds.maxY,
                        max(
                            bounds.minY,
                            center.y
                        )
                    )
            )
        }

        private func clampMainAnchor(
            _ control: UIButton,
            in rootView: UIView
        ) {
            control.center =
                clampedMainAnchorCenter(
                    control.center,
                    in: rootView
                )
        }

        private func saveMainAnchorPosition(
            _ control: UIButton,
            in rootView: UIView
        ) {
            let bounds =
                mainAnchorCenterBounds(
                    in: rootView
                )

            let width =
                max(
                    1,
                    bounds.maxX -
                    bounds.minX
                )
            let height =
                max(
                    1,
                    bounds.maxY -
                    bounds.minY
                )

            let x =
                min(
                    1,
                    max(
                        0,
                        (control.center.x -
                            bounds.minX) /
                            width
                    )
                )
            let y =
                min(
                    1,
                    max(
                        0,
                        (control.center.y -
                            bounds.minY) /
                            height
                    )
                )

            UserDefaults.standard.set(
                Double(x),
                forKey:
                    Self.mainAnchorPositionXKey
            )
            UserDefaults.standard.set(
                Double(y),
                forKey:
                    Self.mainAnchorPositionYKey
            )
        }

        private func restoreMainAnchorPosition(
            in rootView: UIView
        ) {
            guard
                let control = mainAnchorButton
            else {
                return
            }

            let bounds =
                mainAnchorCenterBounds(
                    in: rootView
                )
            let defaults =
                UserDefaults.standard

            if
                defaults.object(
                    forKey:
                        Self.mainAnchorPositionXKey
                ) != nil,
                defaults.object(
                    forKey:
                        Self.mainAnchorPositionYKey
                ) != nil
            {
                let x =
                    min(
                        1,
                        max(
                            0,
                            CGFloat(
                                defaults.double(
                                    forKey:
                                        Self.mainAnchorPositionXKey
                                )
                            )
                        )
                    )
                let y =
                    min(
                        1,
                        max(
                            0,
                            CGFloat(
                                defaults.double(
                                    forKey:
                                        Self.mainAnchorPositionYKey
                                )
                            )
                        )
                    )

                control.center = CGPoint(
                    x:
                        bounds.minX +
                        (
                            bounds.maxX -
                            bounds.minX
                        ) * x,
                    y:
                        bounds.minY +
                        (
                            bounds.maxY -
                            bounds.minY
                        ) * y
                )
            } else {
                control.center = CGPoint(
                    x: bounds.maxX,
                    y: bounds.minY
                )
            }

            clampMainAnchor(
                control,
                in: rootView
            )
        }


        private func toggleScriptPanel(
            from sender: UIButton,
            retry: Bool
        ) {
            guard let webView else {
                return
            }

            let rect =
                sender.convert(
                    sender.bounds,
                    to: webView
                )

            let payload:
                [String: Double] = [
                    "left": Double(rect.minX),
                    "top": Double(rect.minY),
                    "right": Double(rect.maxX),
                    "bottom": Double(rect.maxY),
                    "width": Double(rect.width),
                    "height": Double(rect.height)
                ]

            guard
                let data =
                    try? JSONSerialization.data(
                        withJSONObject: payload
                    ),
                let json =
                    String(
                        data: data,
                        encoding: .utf8
                    )
            else {
                return
            }

            let source =
                """
                (() => {
                  const api =
                    window.ChatGPTWeb ||
                    window.ChatGPTSafari;
                  return (
                    api?.toggleNativePanel?.(\(json)) ??
                    {
                      ok: false,
                      open: false,
                      ready: false
                    }
                  );
                })()
                """

            webView.evaluateJavaScript(
                source
            ) { [weak self, weak sender] result, _ in
                guard
                    let self,
                    let sender
                else {
                    return
                }

                if
                    let state =
                        result as? [String: Any],
                    let ok =
                        state["ok"] as? Bool,
                    ok
                {
                    let open =
                        state["open"] as? Bool ??
                        false
                    let ready =
                        state["ready"] as? Bool ??
                        false

                    if !open {
                        sender.accessibilityValue =
                            "panel-closed"
                    } else if ready {
                        sender.accessibilityValue =
                            "panel-ready"
                    } else {
                        sender.accessibilityValue =
                            "panel-open-not-ready"
                    }
                    return
                }

                if (result as? Bool) == true {
                    sender.accessibilityValue =
                        "panel-open"
                    return
                }

                guard retry else {
                    sender.accessibilityValue =
                        "panel-unavailable"
                    return
                }

                self.ensureScriptsAreRunning()

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.18
                ) { [weak self, weak sender] in
                    guard
                        let self,
                        let sender
                    else {
                        return
                    }

                    self.toggleScriptPanel(
                        from: sender,
                        retry: false
                    )
                }
            }
        }

        private func closeScriptPanel() {
            mainAnchorButton?.accessibilityValue =
                "panel-closed"

            webView?.evaluateJavaScript(
                """
                window.ChatGPTWeb?.closeNativePanel?.();
                window.ChatGPTSafari?.closeNativePanel?.();
                """
            )
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

                latestKnownVersion =
                    latest.version
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
                let type =
                    body["type"] as? String
            else {
                return
            }

            switch type {
            case "check-update":
                startHotUpdate()

            case "install-app-update":
                if
                    let raw = body["url"] as? String,
                    let url = URL(string: raw),
                    url.scheme == "itms-services"
                {
                    DispatchQueue.main.async {
                        UIApplication.shared.open(
                            url,
                            options: [:],
                            completionHandler: nil
                        )
                    }
                }

            case "clear-cache":
                clearWebCacheKeepingLogin()

            default:
                break
            }
        }


        private func clearWebCacheKeepingLogin() {
            let dataTypes: Set<String> = [
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache,
            ]

            URLCache.shared
                .removeAllCachedResponses()

            WKWebsiteDataStore.default()
                .removeData(
                    ofTypes: dataTypes,
                    modifiedSince: .distantPast
                ) { [weak self] in
                    DispatchQueue.main.async {
                        self?.sendNativeActionResult(
                            type: "clear-cache",
                            ok: true
                        )
                    }
                }
        }

        private func sendNativeActionResult(
            type: String,
            ok: Bool
        ) {
            guard
                let webView,
                let data =
                    try? JSONSerialization.data(
                        withJSONObject: [
                            "type": type,
                            "ok": ok
                        ]
                    ),
                let json =
                    String(
                        data: data,
                        encoding: .utf8
                    )
            else {
                return
            }

            webView.evaluateJavaScript(
                """
                window.ChatGPTWeb?.nativeActionResult?.(\(json));
                window.ChatGPTSafari?.nativeActionResult?.(\(json));
                """
            )
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
                "网页控制，可拖动"

            control.showsMenuAsPrimaryAction = true

            let pan = UIPanGestureRecognizer(
                target: self,
                action:
                    #selector(
                        handleBrowserControlPan(_:)
                    )
            )
            pan.cancelsTouchesInView = true
            control.addGestureRecognizer(pan)

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
                )
            ])

            browserControlButton = control
            control.menu = makeBrowserControlMenu()
            control.isHidden = false

            DispatchQueue.main.async {
                [weak self, weak webView] in
                guard
                    let self,
                    let webView
                else {
                    return
                }

                webView.layoutIfNeeded()
                self.restoreBrowserControlPosition(
                    in: webView
                )
            }
        }

        private func makeBrowserControlMenu()
            -> UIMenu
        {
            let canGoBack =
                externalWebView?.canGoBack == true
            let canGoForward =
                externalWebView?.canGoForward == true

            let back = UIAction(
                title: "后退",
                image: UIImage(
                    systemName: "chevron.backward"
                ),
                attributes:
                    canGoBack ? [] : [.disabled]
            ) { [weak self] _ in
                self?.browserBack()
            }

            let forward = UIAction(
                title: "前进",
                image: UIImage(
                    systemName: "chevron.forward"
                ),
                attributes:
                    canGoForward ? [] : [.disabled]
            ) { [weak self] _ in
                self?.browserForward()
            }

            let reload = UIAction(
                title: "刷新",
                image: UIImage(
                    systemName: "arrow.clockwise"
                )
            ) { [weak self] _ in
                self?.browserReload()
            }

            let close = UIAction(
                title: "关闭并返回 ChatGPT",
                image: UIImage(
                    systemName: "xmark"
                )
            ) { [weak self] _ in
                self?.browserClose()
            }

            return UIMenu(
                title: "",
                children: [
                    back,
                    forward,
                    reload,
                    close
                ]
            )
        }

        private func browserControlSafeFrame(
            in webView: WKWebView
        ) -> CGRect {
            var frame =
                webView.safeAreaLayoutGuide
                    .layoutFrame

            if frame.width <= 0 ||
               frame.height <= 0 {
                frame = webView.bounds
            }

            return frame.insetBy(
                dx: 6,
                dy: 6
            )
        }

        private func clampBrowserControl(
            _ control: UIButton,
            in webView: WKWebView
        ) {
            webView.layoutIfNeeded()

            let safeFrame =
                browserControlSafeFrame(
                    in: webView
                )

            var dx: CGFloat = 0
            var dy: CGFloat = 0
            let frame = control.frame

            if frame.minX < safeFrame.minX {
                dx = safeFrame.minX - frame.minX
            } else if frame.maxX > safeFrame.maxX {
                dx = safeFrame.maxX - frame.maxX
            }

            if frame.minY < safeFrame.minY {
                dy = safeFrame.minY - frame.minY
            } else if frame.maxY > safeFrame.maxY {
                dy = safeFrame.maxY - frame.maxY
            }

            if dx != 0 || dy != 0 {
                control.transform =
                    control.transform.translatedBy(
                        x: dx,
                        y: dy
                    )
            }
        }

        private func saveBrowserControlPosition(
            _ control: UIButton,
            in webView: WKWebView
        ) {
            let safeFrame =
                browserControlSafeFrame(
                    in: webView
                )

            guard
                safeFrame.width > 0,
                safeFrame.height > 0
            else {
                return
            }

            let x = min(
                1,
                max(
                    0,
                    (control.center.x -
                        safeFrame.minX) /
                        safeFrame.width
                )
            )

            let y = min(
                1,
                max(
                    0,
                    (control.center.y -
                        safeFrame.minY) /
                        safeFrame.height
                )
            )

            UserDefaults.standard.set(
                Double(x),
                forKey:
                    Self.browserControlPositionXKey
            )

            UserDefaults.standard.set(
                Double(y),
                forKey:
                    Self.browserControlPositionYKey
            )
        }

        private func restoreBrowserControlPosition(
            in webView: WKWebView
        ) {
            guard
                let control = browserControlButton
            else {
                return
            }

            let defaults = UserDefaults.standard

            guard
                defaults.object(
                    forKey:
                        Self.browserControlPositionXKey
                ) != nil,
                defaults.object(
                    forKey:
                        Self.browserControlPositionYKey
                ) != nil
            else {
                clampBrowserControl(
                    control,
                    in: webView
                )
                return
            }

            let safeFrame =
                browserControlSafeFrame(
                    in: webView
                )

            let x = CGFloat(
                defaults.double(
                    forKey:
                        Self.browserControlPositionXKey
                )
            )

            let y = CGFloat(
                defaults.double(
                    forKey:
                        Self.browserControlPositionYKey
                )
            )

            webView.layoutIfNeeded()
            control.transform = .identity
            webView.layoutIfNeeded()

            let baseCenter = control.center
            let targetCenter = CGPoint(
                x:
                    safeFrame.minX +
                    safeFrame.width *
                    min(1, max(0, x)),
                y:
                    safeFrame.minY +
                    safeFrame.height *
                    min(1, max(0, y))
            )

            control.transform =
                CGAffineTransform(
                    translationX:
                        targetCenter.x -
                        baseCenter.x,
                    y:
                        targetCenter.y -
                        baseCenter.y
                )

            clampBrowserControl(
                control,
                in: webView
            )
        }

        @objc private func handleBrowserControlPan(
            _ gesture: UIPanGestureRecognizer
        ) {
            guard
                let control = browserControlButton,
                let externalWebView
            else {
                return
            }

            switch gesture.state {
            case .began:
                browserControlDragStartTransform =
                    control.transform

            case .changed:
                let translation =
                    gesture.translation(
                        in: externalWebView
                    )

                var transform =
                    browserControlDragStartTransform

                transform.tx += translation.x
                transform.ty += translation.y
                control.transform = transform

                clampBrowserControl(
                    control,
                    in: externalWebView
                )

            case .ended, .cancelled, .failed:
                clampBrowserControl(
                    control,
                    in: externalWebView
                )

                saveBrowserControlPosition(
                    control,
                    in: externalWebView
                )

            default:
                break
            }
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

            if let button = browserControlButton {
                button.menu = makeBrowserControlMenu()
                externalWebView.bringSubviewToFront(button)
                clampBrowserControl(
                    button,
                    in: externalWebView
                )
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
            case .microphone, .camera, .cameraAndMicrophone:
                decisionHandler(.grant)

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
                    latestScriptVersion:
                        latestKnownVersion,
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
                    return
            }

        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            if webView === externalWebView {
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

        private func recoverFromContentProcessTermination(
            _ webView: WKWebView
        ) {
            if webView === externalWebView {
                browserClose()
                return
            }

            let now = Date()

            contentTerminationTimes =
                contentTerminationTimes.filter {
                    now.timeIntervalSince($0) < 20
                }

            contentTerminationTimes.append(now)

            if contentTerminationTimes.count == 1 {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.7
                ) { [weak webView] in
                    webView?.reload()
                }
                return
            }

            guard !recoveryAlertPresented else {
                return
            }

            recoveryAlertPresented = true

            presentAlert(
                title: "长对话占用过高",
                message:
                    "这个对话在短时间内连续触发了网页进程内存回收。已停止自动刷新，避免进入刷新死循环。",
                actions: [
                    UIAlertAction(
                        title: "返回 ChatGPT 首页",
                        style: .default
                    ) { [weak self, weak webView] _ in
                        self?.recoveryAlertPresented = false
                        self?.contentTerminationTimes.removeAll()

                        guard
                            let url = URL(
                                string:
                                    "https://chatgpt.com/"
                            )
                        else {
                            return
                        }

                        webView?.load(
                            URLRequest(url: url)
                        )
                    },
                    UIAlertAction(
                        title: "重新加载一次",
                        style: .default
                    ) { [weak self, weak webView] _ in
                        self?.recoveryAlertPresented = false
                        self?.contentTerminationTimes = [
                            Date()
                        ]
                        webView?.reload()
                    }
                ]
            )
        }

        func webViewWebContentProcessDidTerminate(
            _ webView: WKWebView
        ) {
            recoverFromContentProcessTermination(
                webView
            )
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
