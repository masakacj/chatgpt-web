import SwiftUI
// v0.4.9 unified floating menu build trigger
import UIKit
import WebKit

final class ChatGPTFloatingAnchorButton: UIButton {
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        addTarget(
            self,
            action: #selector(handleTap),
            for: .touchUpInside
        )
    }

    required init?(coder: NSCoder) {
        fatalError(
            "init(coder:) has not been implemented"
        )
    }

    @objc
    private func handleTap() {
        onTap?()
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
                equalTo:
                    safeAreaLayoutGuide
                        .topAnchor
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
    private static func webKitStressHTML()
        -> String
    {
        var blocks: [String] = []

        let mcpPayload =
            String(
                repeating:
                    "<span class=\"payload\">mcp-payload</span>",
                count: 12
            )

        for index in 0..<96 {
            blocks.append(
                """
                <section class="activity-block mcp-block">
                  <div class="group/activity-header">MCP · mcpoffice</div>
                  <div class="group/mcp-app">
                    <iframe
                      title="mcp-mcpoffice"
                      src="about:blank">
                    </iframe>
                    <div class="payload-grid">\(mcpPayload)</div>
                    <div class="payload-label">mcp-\(index)</div>
                  </div>
                </section>
                """
            )
        }

        let thinkingPayload =
            String(
                repeating:
                    "<span class=\"thinking-token\">reasoning-token</span>",
                count: 120
            )

        for index in 0..<3 {
            blocks.append(
                """
                <section class="activity-block thinking-block">
                  <div class="group/activity-header">Thinking \(index + 1)s</div>
                  <div class="thinking-body">\(thinkingPayload)</div>
                </section>
                """
            )
        }

        for index in 0..<10 {
            blocks.append(
                """
                <section class="activity-block keep-activity">
                  <div class="group/activity-header">Reference event \(index)</div>
                  <div class="keep-marker">KEEP_ACTIVITY_\(index)</div>
                </section>
                """
            )
        }

        let normalPayload =
            String(
                repeating:
                    "<span class=\"normal-token\">answer-token</span>",
                count: 24
            )

        for index in 0..<28 {
            blocks.append(
                """
                <section class="normal-content">
                  <p>Normal answer block \(index)</p>
                  <div>\(normalPayload)</div>
                </section>
                """
            )
        }

        let stream =
            blocks.joined(
                separator: "\n"
            )

        return
            """
            <!doctype html>
            <html>
              <head>
                <meta
                  name="viewport"
                  content="width=device-width,initial-scale=1">
                <style>
                  body {
                    margin: 0;
                    font-family: -apple-system, system-ui, sans-serif;
                  }
                  #conversation-stream {
                    max-width: 760px;
                    margin: 0 auto;
                    padding: 20px;
                  }
                  .activity-block,
                  .normal-content {
                    padding: 8px 0;
                  }
                  .payload-grid,
                  .thinking-body {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 2px;
                  }
                  iframe {
                    width: 280px;
                    height: 60px;
                  }
                </style>
              </head>
              <body>
                <main class="WorkspaceContent-stress">
                  <div id="conversation-stream">
                    \(stream)
                    <section id="final-answer">
                      FINAL_ANSWER_SENTINEL · final answer must survive Result Only pruning.
                    </section>
                  </div>
                </main>
                <script>
                  (() => {
                    const headers = [
                      ...document.querySelectorAll(
                        '[class*="group/activity-header"]'
                      )
                    ];
                    window.__CGPT_STRESS_BASELINE__ = {
                      nodes:
                        document.getElementsByTagName('*').length,
                      activity:
                        headers.length,
                      mcp:
                        document.querySelectorAll(
                          'iframe[title*="mcp" i],iframe[aria-label*="mcp" i]'
                        ).length,
                      thinking:
                        headers.filter((node) =>
                          /^(?:Thinking|Thought for|正在思考|思考了)/i.test(
                            String(node.textContent || '').trim()
                          )
                        ).length
                    };
                  })();
                </script>
              </body>
            </html>
            """
    }

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

        controller.add(
            context.coordinator,
            name: Coordinator.nativeMessageHandler
        )

        installUserScripts(
            on: controller,
            payload: initialScript,
            status:
                initialScript?.origin == "cached"
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

        // Developer shell: expose this WKWebView to Safari Web Inspector.
        // The deployment target is iOS 17, where isInspectable is available.
        webView.isInspectable = true

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Keep WebKit's navigation swipe gestures disabled.
        // This shell intentionally adds no custom gestures.
        webView.allowsBackForwardNavigationGestures = false

        webView.allowsLinkPreview = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        let container =
            ChatGPTWebContainerView(
                webView: webView
            )

        let arguments =
            ProcessInfo.processInfo.arguments

        let isUITesting =
            arguments.contains(
                "--ui-testing"
            )

        let isWebKitStress =
            arguments.contains(
                "--webkit-stress"
            )

        context.coordinator.attach(
            rootView: container,
            webView: webView,
            contentController: controller,
            initialScript: initialScript,
            webKitStressMode:
                isWebKitStress
        )

        if !isUITesting {
            context.coordinator
                .installMainAnchor(
                    in: container
                )
        }

        if isWebKitStress {
            webView.loadHTMLString(
                Self.webKitStressHTML(),
                baseURL: URL(
                    string:
                        "https://chatgpt.com/"
                )
            )
        } else if isUITesting {
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
        status: String
    ) {
        let store = UnifiedScriptStore.shared

        controller.addUserScript(
            WKUserScript(
                source: store.nativeBootstrap(
                    scriptVersion:
                        payload?.version ?? "missing",
                    scriptOrigin:
                        payload?.origin ?? "none",
                    updateStatus: "checking"
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

        controller.addUserScript(
            WKUserScript(
                source: store.runtimeStatusJavaScript(
                    scriptVersion:
                        payload?.version ?? "missing",
                    scriptOrigin:
                        payload?.origin ?? "none",
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
        WKScriptMessageHandler
    {
        static let nativeMessageHandler = "chatGPTNative"

        private let scriptStore: UnifiedScriptStore
        private let nativePerformance = ChatGPTNativePerformanceProbe()
        private var contentController: WKUserContentController?

        private var activeScript: UnifiedScriptPayload?

        private var updateStatus = "bundled"
        private var checkingUpdate = false
        private var hasStartedInitialHotUpdate = false
        private var lifecycleObserversInstalled = false
        private var lastForegroundHotUpdateAt =
            Date.distantPast
        private let sendFeedbackGenerator =
            UIImpactFeedbackGenerator(
                style: .light
            )

        private var browserControlsExpanded = false
        private var contentTerminationTimes: [Date] = []
        private var recoveryAlertPresented = false

        private var latestKnownVersion: String?

        private var webKitStressMode =
            false
        private var webKitStressStartedAt =
            Date.distantPast
        private var webKitStressPollAttempt =
            0
        private var webKitStressTerminated =
            false
        private weak var webKitStressLabel:
            UILabel?

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

        deinit {
            NotificationCenter.default
                .removeObserver(self)
        }

        func attach(
            rootView: ChatGPTWebContainerView,
            webView: WKWebView,
            contentController: WKUserContentController,
            initialScript: UnifiedScriptPayload?,
            webKitStressMode: Bool
        ) {
            self.rootView = rootView
            self.webView = webView
            self.contentController = contentController
            self.activeScript = initialScript
            self.latestKnownVersion =
                initialScript?.version
            self.webKitStressMode =
                webKitStressMode

            if webKitStressMode {
                self.webKitStressStartedAt =
                    Date()
                installWebKitStressStatus(
                    in: rootView
                )
            }

            self.updateStatus =
                initialScript?.origin == "cached"
                ? "cached"
                : "bundled"

            installNativeLifecycleBridge()
            sendFeedbackGenerator.prepare()
        }

        private func installWebKitStressStatus(
            in rootView: UIView
        ) {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints =
                false
            label.text = "RUNNING"
            label.font =
                UIFont.monospacedSystemFont(
                    ofSize: 11,
                    weight: .semibold
                )
            label.textColor = .label
            label.backgroundColor =
                UIColor.systemBackground
                    .withAlphaComponent(
                        0.94
                    )
            label.numberOfLines = 3
            label.accessibilityIdentifier =
                "webkit.stress.result"
            label.isAccessibilityElement =
                true

            rootView.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(
                    equalTo:
                        rootView.safeAreaLayoutGuide
                            .leadingAnchor,
                    constant: 8
                ),
                label.topAnchor.constraint(
                    equalTo:
                        rootView.safeAreaLayoutGuide
                            .topAnchor,
                    constant: 8
                ),
                label.widthAnchor.constraint(
                    lessThanOrEqualToConstant:
                        360
                )
            ])

            webKitStressLabel = label
            rootView.bringSubviewToFront(
                label
            )
        }

        private func setWebKitStressStatus(
            _ text: String
        ) {
            webKitStressLabel?.text =
                text
            webKitStressLabel?
                .accessibilityLabel =
                    text
        }

        private func scheduleWebKitStressEvaluation(
            delay: TimeInterval = 0.35
        ) {
            guard
                webKitStressMode,
                !webKitStressTerminated
            else {
                return
            }

            DispatchQueue.main
                .asyncAfter(
                    deadline:
                        .now() + delay
                ) { [weak self] in
                    self?
                        .evaluateWebKitStressResult()
                }
        }

        private func evaluateWebKitStressResult() {
            guard
                webKitStressMode,
                !webKitStressTerminated,
                let webView
            else {
                return
            }

            let script =
                """
                (() => {
                  const baseline =
                    window.__CGPT_STRESS_BASELINE__ ||
                    {};
                  const headers = [
                    ...document.querySelectorAll(
                      '[class*="group/activity-header"]'
                    )
                  ];
                  const thinking =
                    headers.filter((node) =>
                      /^(?:Thinking|Thought for|正在思考|思考了)/i.test(
                        String(node.textContent || '').trim()
                      )
                    ).length;
                  return {
                    baselineNodes:
                      Number(baseline.nodes || 0),
                    baselineActivity:
                      Number(baseline.activity || 0),
                    baselineMcp:
                      Number(baseline.mcp || 0),
                    baselineThinking:
                      Number(baseline.thinking || 0),
                    nodes:
                      document.getElementsByTagName('*').length,
                    activity:
                      headers.length,
                    mcp:
                      document.querySelectorAll(
                        'iframe[title*="mcp" i],iframe[aria-label*="mcp" i]'
                      ).length,
                    thinking,
                    sentinel:
                      Boolean(
                        document.getElementById('final-answer')
                          ?.textContent
                          ?.includes('FINAL_ANSWER_SENTINEL')
                      ),
                    runtime:
                      document.documentElement.getAttribute(
                        'data-cgpt-runtime-version'
                      ) || '',
                    pruned:
                      document.querySelectorAll(
                        '[data-cgpt-modern-process-pruned="1"]'
                      ).length
                  };
                })()
                """

            webView.evaluateJavaScript(
                script
            ) { [weak self] result, error in
                guard let self else {
                    return
                }

                self.webKitStressPollAttempt +=
                    1

                guard
                    error == nil,
                    let values =
                        result as?
                            [String: Any]
                else {
                    if self
                        .webKitStressPollAttempt <
                        32
                    {
                        self.scheduleWebKitStressEvaluation()
                    } else {
                        self.setWebKitStressStatus(
                            "FAIL evaluate"
                        )
                    }
                    return
                }

                func integer(
                    _ key: String
                ) -> Int {
                    (
                        values[key] as?
                            NSNumber
                    )?.intValue ??
                    0
                }

                let baselineNodes =
                    integer(
                        "baselineNodes"
                    )
                let nodes =
                    integer("nodes")
                let baselineActivity =
                    integer(
                        "baselineActivity"
                    )
                let activity =
                    integer("activity")
                let baselineMcp =
                    integer(
                        "baselineMcp"
                    )
                let mcp =
                    integer("mcp")
                let baselineThinking =
                    integer(
                        "baselineThinking"
                    )
                let thinking =
                    integer(
                        "thinking"
                    )
                let pruned =
                    integer(
                        "pruned"
                    )
                let sentinel =
                    values["sentinel"]
                        as? Bool ??
                    false
                let runtime =
                    values["runtime"]
                        as? String ??
                    ""

                let reduction =
                    baselineNodes > 0
                    ? (
                        Double(
                            baselineNodes -
                            nodes
                        ) /
                        Double(
                            baselineNodes
                        )
                    )
                    : 0

                let pass =
                    baselineActivity >= 109 &&
                    baselineMcp >= 96 &&
                    baselineThinking >= 3 &&
                    activity == 10 &&
                    mcp == 0 &&
                    thinking == 0 &&
                    sentinel &&
                    !runtime.isEmpty &&
                    pruned >= 99 &&
                    reduction >= 0.40

                let elapsed =
                    Date().timeIntervalSince(
                        self
                            .webKitStressStartedAt
                    )

                if pass {
                    self.setWebKitStressStatus(
                        String(
                            format:
                                "PASS %.2fs nodes=%d→%d activity=%d mcp=%d thinking=%d pruned=%d v%@",
                            elapsed,
                            baselineNodes,
                            nodes,
                            activity,
                            mcp,
                            thinking,
                            pruned,
                            runtime
                        )
                    )
                    return
                }

                if self
                    .webKitStressPollAttempt <
                    32
                {
                    self.scheduleWebKitStressEvaluation()
                    return
                }

                self.setWebKitStressStatus(
                    String(
                        format:
                            "FAIL nodes=%d→%d activity=%d/%d mcp=%d/%d thinking=%d/%d pruned=%d v%@",
                        baselineNodes,
                        nodes,
                        activity,
                        baselineActivity,
                        mcp,
                        baselineMcp,
                        thinking,
                        baselineThinking,
                        pruned,
                        runtime
                    )
                )
            }
        }

        private func installNativeLifecycleBridge() {
            guard !lifecycleObserversInstalled else {
                return
            }

            lifecycleObserversInstalled = true

            let center =
                NotificationCenter.default

            center.addObserver(
                self,
                selector:
                    #selector(
                        appDidEnterBackground(_:)
                    ),
                name:
                    UIApplication
                        .didEnterBackgroundNotification,
                object: nil
            )

            center.addObserver(
                self,
                selector:
                    #selector(
                        appDidBecomeActive(_:)
                    ),
                name:
                    UIApplication
                        .didBecomeActiveNotification,
                object: nil
            )

            center.addObserver(
                self,
                selector:
                    #selector(
                        powerStateDidChange(_:)
                    ),
                name:
                    .NSProcessInfoPowerStateDidChange,
                object: nil
            )

            center.addObserver(
                self,
                selector:
                    #selector(
                        thermalStateDidChange(_:)
                    ),
                name:
                    ProcessInfo
                        .thermalStateDidChangeNotification,
                object: nil
            )
        }

        @objc
        private func appDidEnterBackground(
            _ notification: Notification
        ) {
            sendNativeLifecycle(
                "background"
            )
        }

        @objc
        private func appDidBecomeActive(
            _ notification: Notification
        ) {
            sendNativeLifecycle(
                "active"
            )

            // During development, returning to the app is also a cheap
            // script-refresh gesture. Throttle rapid foreground changes.
            let now = Date()
            if now.timeIntervalSince(
                lastForegroundHotUpdateAt
            ) >= 12 {
                lastForegroundHotUpdateAt = now
                startHotUpdate(
                    injectCurrentPage: true
                )
            }
        }

        @objc
        private func powerStateDidChange(
            _ notification: Notification
        ) {
            sendNativeLifecycle(
                "power"
            )
        }

        @objc
        private func thermalStateDidChange(
            _ notification: Notification
        ) {
            sendNativeLifecycle(
                "thermal"
            )
        }

        private func sendNativeLifecycle(
            _ phase: String
        ) {
            guard
                let webView,
                !webView.isLoading ||
                    phase != "background"
            else {
                return
            }

            let source =
                scriptStore
                    .nativeLifecycleJavaScript(
                        phase: phase
                    )

            guard !source.isEmpty else {
                return
            }

            webView.evaluateJavaScript(
                source
            )
        }

        func installMainAnchor(
            in rootView: ChatGPTWebContainerView
        ) {
            guard mainAnchorButton == nil else {
                return
            }

            let control =
                ChatGPTFloatingAnchorButton(
                    frame: .zero
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
                "ChatGPT Web 控制"
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

                if self.externalWebView != nil {
                    self.closeScriptPanel()
                    self.toggleExternalBrowserMenu()
                    return
                }

                let currentState =
                    control.accessibilityValue ??
                    ""

                if [
                    "panel-ready",
                    "panel-open",
                    "panel-open-not-ready"
                ].contains(currentState) {
                    self.closeScriptPanel()
                    return
                }

                control.accessibilityValue =
                    "panel-requested"

                self.toggleScriptPanel(
                    from: control,
                    retriesRemaining: 12
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
            if browserControlsExpanded {
                positionExternalBrowserMenu()
                if let menu = browserMenuView {
                    rootView.bringSubviewToFront(menu)
                }
            }

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
            retriesRemaining: Int
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

                        self.pollScriptPanelReady(
                            from: sender,
                            retriesRemaining:
                                retriesRemaining
                        )
                    }
                    return
                }

                if (result as? Bool) == true {
                    sender.accessibilityValue =
                        "panel-open"
                    return
                }

                guard retriesRemaining > 0 else {
                    sender.accessibilityValue =
                        "panel-unavailable"
                    return
                }

                self.ensureScriptsAreRunning()

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.20
                ) { [weak self, weak sender] in
                    guard
                        let self,
                        let sender
                    else {
                        return
                    }

                    self.toggleScriptPanel(
                        from: sender,
                        retriesRemaining:
                            retriesRemaining - 1
                    )
                }
            }
        }

        private func pollScriptPanelReady(
            from sender: UIButton,
            retriesRemaining: Int
        ) {
            guard
                retriesRemaining > 0,
                let webView
            else {
                return
            }

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.20
            ) { [weak self, weak sender] in
                guard
                    let self,
                    let sender
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
                        api?.nativePanelRenderState?.() ??
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
                            return
                        }

                        if ready {
                            sender.accessibilityValue =
                                "panel-ready"
                            return
                        }
                    }

                    self.ensureScriptsAreRunning()

                    self.pollScriptPanelReady(
                        from: sender,
                        retriesRemaining:
                            retriesRemaining - 1
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

        func startHotUpdate(
            injectCurrentPage: Bool = true
        ) {
            guard !checkingUpdate else {
                if injectCurrentPage {
                    updateRuntimeStatus()
                }
                return
            }

            checkingUpdate = true
            updateStatus = "checking"
            updateRuntimeStatus()

            Task { [weak self] in
                guard let self else {
                    return
                }

                let result =
                    await self.fetchSharedUpdateResult()

                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }

                    self.checkingUpdate = false

                    let didChange =
                        self.applyScriptResult(
                            result
                        )

                    self.installForFutureNavigations()
                    self.updateRuntimeStatus()

                    // Reinjection destroys and recreates observers and
                    // Result Only presentation. It is only appropriate for
                    // a genuinely changed script; returning from background
                    // should NOT cause another full long-chat DOM pass.
                    if
                        injectCurrentPage,
                        didChange,
                        let activeScript =
                            self.activeScript
                    {
                        self.injectScriptIntoCurrentPage(
                            activeScript
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

            case "send-touch-ack":
                sendFeedbackGenerator
                    .impactOccurred(
                        intensity: 0.55
                    )
                sendFeedbackGenerator.prepare()

            case "perf-debug-opt-in":
                // Only the authenticated ChatGPT top frame may change
                // native telemetry consent. No session information is read.
                if message.frameInfo.isMainFrame,
                   message.frameInfo.securityOrigin.host.lowercased() == "chatgpt.com",
                   let enabled = body["enabled"] as? Bool {
                    nativePerformance.setEnabled(enabled)
                }

            case "telemetry":
                if
                    let batchId =
                        body["batchId"] as? String,
                    let payload =
                        body["payload"] as? [String: Any]
                {
                    uploadTelemetry(
                        batchId: batchId,
                        payload: payload
                    )
                }

            default:
                break
            }
        }


        private func uploadTelemetry(
            batchId: String,
            payload: [String: Any]
        ) {
            guard
                let url = URL(
                    string:
                        "https://chatgpt-web-telemetry.masakacj.workers.dev/v1/telemetry"
                ),
                JSONSerialization.isValidJSONObject(
                    payload
                ),
                let data =
                    try? JSONSerialization.data(
                        withJSONObject: payload
                    ),
                data.count <= 64 * 1024
            else {
                sendTelemetryResult(
                    batchId: batchId,
                    ok: false,
                    status: "invalid_payload"
                )
                return
            }

            var request =
                URLRequest(
                    url: url,
                    timeoutInterval: 15
                )

            request.httpMethod = "POST"
            request.httpBody = data
            request.cachePolicy =
                .reloadIgnoringLocalCacheData
            request.setValue(
                "application/json",
                forHTTPHeaderField:
                    "Content-Type"
            )
            request.setValue(
                "1",
                forHTTPHeaderField:
                    "X-ChatGPT-Web-Telemetry"
            )
            request.setValue(
                "ChatGPTWeb-iOS/telemetry",
                forHTTPHeaderField:
                    "User-Agent"
            )

            URLSession.shared.dataTask(
                with: request
            ) { [weak self] _, response, error in
                let statusCode =
                    (
                        response as?
                            HTTPURLResponse
                    )?.statusCode

                let ok =
                    error == nil &&
                    statusCode.map {
                        (200..<300).contains($0)
                    } == true

                let detail: String

                if let error =
                    error as? URLError
                {
                    detail =
                        "url_" +
                        String(
                            error.code.rawValue
                        )
                } else if let statusCode {
                    detail =
                        "http_" +
                        String(statusCode)
                } else {
                    detail = "no_response"
                }

                DispatchQueue.main.async {
                    self?.sendTelemetryResult(
                        batchId: batchId,
                        ok: ok,
                        status: detail
                    )
                }
            }.resume()
        }

        private func sendTelemetryResult(
            batchId: String,
            ok: Bool,
            status: String
        ) {
            guard
                let webView,
                let data =
                    try? JSONSerialization.data(
                        withJSONObject: [
                            "type": "telemetry",
                            "ok": ok,
                            "batchId": batchId,
                            "status": status
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

            control.showsMenuAsPrimaryAction = true

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

        private func ensureExternalBrowserMenu() {
            guard
                browserMenuView == nil,
                let rootView
            else {
                return
            }

            let blur =
                UIBlurEffect(
                    style: .systemMaterialDark
                )
            let menu =
                UIVisualEffectView(
                    effect: blur
                )

            menu.frame = CGRect(
                x: 0,
                y: 0,
                width: 196,
                height: 50
            )
            menu.layer.cornerRadius = 14
            menu.clipsToBounds = true
            menu.isHidden = true

            let stack = UIStackView()
            stack.axis = .horizontal
            stack.alignment = .fill
            stack.distribution = .fillEqually
            stack.spacing = 0
            stack.frame = menu.bounds
            stack.autoresizingMask = [
                .flexibleWidth,
                .flexibleHeight
            ]

            let back =
                makeBrowserActionButton(
                    systemName:
                        "chevron.backward",
                    accessibilityLabel:
                        "后退",
                    action:
                        #selector(browserBack)
                )

            let forward =
                makeBrowserActionButton(
                    systemName:
                        "chevron.forward",
                    accessibilityLabel:
                        "前进",
                    action:
                        #selector(browserForward)
                )

            let reload =
                makeBrowserActionButton(
                    systemName:
                        "arrow.clockwise",
                    accessibilityLabel:
                        "刷新",
                    action:
                        #selector(browserReload)
                )

            let close =
                makeBrowserActionButton(
                    systemName: "xmark",
                    accessibilityLabel:
                        "关闭",
                    action:
                        #selector(browserClose)
                )

            stack.addArrangedSubview(back)
            stack.addArrangedSubview(forward)
            stack.addArrangedSubview(reload)
            stack.addArrangedSubview(close)

            menu.contentView.addSubview(stack)
            rootView.addSubview(menu)

            browserMenuView = menu
            browserBackButton = back
            browserForwardButton = forward

            positionExternalBrowserMenu()
        }

        private func positionExternalBrowserMenu() {
            guard
                let menu = browserMenuView,
                let rootView,
                let anchor = mainAnchorButton
            else {
                return
            }

            rootView.layoutIfNeeded()

            let anchorFrame =
                anchor.convert(
                    anchor.bounds,
                    to: rootView
                )

            let safe =
                rootView.safeAreaLayoutGuide
                    .layoutFrame

            let width: CGFloat = 196
            let height: CGFloat = 50
            let gap: CGFloat = 8

            let x =
                min(
                    max(
                        safe.minX + 6,
                        anchorFrame.maxX -
                            width
                    ),
                    safe.maxX -
                        width -
                        6
                )

            let below =
                anchorFrame.maxY +
                gap

            let y =
                below + height <=
                    safe.maxY - 6
                ? below
                : max(
                    safe.minY + 6,
                    anchorFrame.minY -
                        gap -
                        height
                )

            menu.frame = CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
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
                collapseExternalBrowserMenu()
                return
            }

            browserBackButton?.isEnabled =
                externalWebView.canGoBack
            browserBackButton?.alpha =
                externalWebView.canGoBack
                ? 1.0
                : 0.35

            browserForwardButton?.isEnabled =
                externalWebView.canGoForward
            browserForwardButton?.alpha =
                externalWebView.canGoForward
                ? 1.0
                : 0.35

            positionExternalBrowserMenu()

            if
                let rootView,
                let menu = browserMenuView
            {
                rootView.bringSubviewToFront(menu)
            }

            if
                let rootView,
                let anchor = mainAnchorButton
            {
                rootView.bringSubviewToFront(anchor)
            }
        }

        @objc private func toggleExternalBrowserMenu() {
            guard externalWebView != nil else {
                return
            }

            ensureExternalBrowserMenu()

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

            externalWebView.goBack()

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.15
            ) { [weak self] in
                self?.updateExternalBrowserControls()
            }
        }

        @objc private func browserForward() {
            guard
                let externalWebView,
                externalWebView.canGoForward
            else {
                return
            }

            externalWebView.goForward()

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.15
            ) { [weak self] in
                self?.updateExternalBrowserControls()
            }
        }

        @objc private func browserReload() {
            externalWebView?.reload()
        }

        @objc private func browserClose() {
            guard let externalWebView else {
                return
            }

            collapseExternalBrowserMenu()
            browserMenuView?.removeFromSuperview()

            externalWebView.stopLoading()
            externalWebView.navigationDelegate = nil
            externalWebView.uiDelegate = nil
            externalWebView.removeFromSuperview()

            self.externalWebView = nil
            browserControlButton = nil
            browserMenuView = nil
            browserBackButton = nil
            browserForwardButton = nil

            if
                let rootView,
                let anchor = mainAnchorButton
            {
                rootView.bringSubviewToFront(anchor)
            }
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
            closeScriptPanel()

            if
                let rootView,
                let anchor = mainAnchorButton
            {
                rootView.bringSubviewToFront(anchor)
            }

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
                        updateStatus: updateStatus
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
                                    updateStatus
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
                        latestKnownVersion
                )
            )
        }

        private func ensureScriptsAreRunning() {
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

                self.injectScriptIntoCurrentPage(
                    activeScript
                )
            }
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation
                navigation: WKNavigation!
        ) {
            if webView === externalWebView {
                updateExternalBrowserControls()
                return
            }
            nativePerformance.navigationStarted(webView)
        }

        func webView(
            _ webView: WKWebView,
            didCommit navigation: WKNavigation!
        ) {
            if webView === externalWebView {
                return
            }
            nativePerformance.navigationCommitted(webView)
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            if webView === externalWebView {
                updateExternalBrowserControls()
                return
            }

            nativePerformance.navigationFinished(webView)
            ensureScriptsAreRunning()

            if webKitStressMode {
                scheduleWebKitStressEvaluation(
                    delay: 0.8
                )
                return
            }

            if !hasStartedInitialHotUpdate {
                hasStartedInitialHotUpdate = true
                lastForegroundHotUpdateAt =
                    Date()
                startHotUpdate(
                    injectCurrentPage: true
                )
            }
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

        private func reloadAfterMemoryPressure(
            _ webView: WKWebView,
            delay: TimeInterval
        ) {
            // Preserve website cache and login/session data. Emptying the
            // global cache before every recovery makes the same huge chat
            // hydrate from scratch and can encourage a reload loop.
            let expectedURL = webView.url
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay
            ) { [weak webView] in
                guard let webView,
                      webView.url == expectedURL
                else { return }
                webView.reload()
            }
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
                    now.timeIntervalSince($0) < 180
                }

            contentTerminationTimes.append(now)

            let recentCount =
                contentTerminationTimes.count

            // One automatic recovery only within a three-minute window.
            // Repeated silent reloads make a heavy conversation flicker
            // indefinitely while also moving the scroll position.
            if recentCount == 1 {
                reloadAfterMemoryPressure(
                    webView,
                    delay: 0.6
                )
                return
            }

            guard !recoveryAlertPresented else {
                return
            }

            recoveryAlertPresented = true

            presentAlert(
                title: "网页内容进程反复退出",
                message:
                    "已经自动恢复过一次。继续自动重载可能造成页面反复闪烁或滚动位置错乱。可以返回首页，或选择手动再试一次。",
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
                        title: "再重载一次",
                        style: .default
                    ) { [weak self, weak webView] _ in
                        self?.recoveryAlertPresented = false
                        self?.contentTerminationTimes = [
                            Date()
                        ]

                        guard let webView else {
                            return
                        }

                        self?.reloadAfterMemoryPressure(
                            webView,
                            delay: 0.35
                        )
                    }
                ]
            )
        }

        func webViewWebContentProcessDidTerminate(
            _ webView: WKWebView
        ) {
            if webView === self.webView {
                nativePerformance.webContentTerminated(webView)
            }

            if (
                webKitStressMode &&
                webView === self.webView
            ) {
                webKitStressTerminated =
                    true
                setWebKitStressStatus(
                    "TERMINATED WebContent"
                )
                return
            }

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
