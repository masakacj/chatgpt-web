#if DEBUG
import SwiftUI
import UIKit
import WebKit
import SafariServices

enum ABBenchmarkMode: String {
    case safari
    case wk
}

private enum ABBenchmarkMarker {
    static func markURL(
        for fixtureURL: URL
    ) -> URL? {
        guard
            var components =
                URLComponents(
                    url: fixtureURL,
                    resolvingAgainstBaseURL:
                        false
                )
        else {
            return nil
        }

        let run =
            components.queryItems?
                .first(where: {
                    $0.name == "run"
                })?
                .value

        components.path = "/mark"
        components.queryItems =
            run.map {
                [
                    URLQueryItem(
                        name: "run",
                        value: $0
                    )
                ]
            } ?? []

        return components.url
    }

    static func perform(
        fixtureURL: URL,
        completion:
            @escaping () -> Void
    ) {
        guard
            let markURL =
                markURL(
                    for: fixtureURL
                )
        else {
            completion()
            return
        }

        var request =
            URLRequest(
                url: markURL
            )

        request.cachePolicy =
            .reloadIgnoringLocalCacheData
        request.timeoutInterval = 2

        URLSession.shared
            .dataTask(
                with: request
            ) { _, _, _ in }
            .resume()

        completion()
    }
}

struct ABBenchmarkConfig {
    let mode: ABBenchmarkMode
    let url: URL

    static var current: ABBenchmarkConfig? {
        let args =
            ProcessInfo.processInfo.arguments

        func value(after flag: String)
            -> String?
        {
            guard
                let index =
                    args.firstIndex(
                        of: flag
                    ),
                args.indices.contains(
                    index + 1
                )
            else {
                return nil
            }

            return args[index + 1]
        }

        guard
            let rawMode =
                value(
                    after:
                        "--ab-benchmark-mode"
                ),
            let mode =
                ABBenchmarkMode(
                    rawValue:
                        rawMode
                ),
            let rawURL =
                value(
                    after:
                        "--ab-benchmark-url"
                ),
            let url =
                URL(
                    string:
                        rawURL
                )
        else {
            return nil
        }

        return .init(
            mode: mode,
            url: url
        )
    }
}

struct ABBenchmarkView: View {
    let config: ABBenchmarkConfig

    var body: some View {
        switch config.mode {
        case .safari:
            ABBenchmarkSafariView(
                url: config.url
            )
            .ignoresSafeArea()

        case .wk:
            ABBenchmarkWKView(
                url: config.url
            )
            .ignoresSafeArea()
        }
    }
}

private struct ABBenchmarkSafariView:
    UIViewControllerRepresentable
{
    let url: URL

    func makeUIViewController(
        context: Context
    ) -> ABBenchmarkSafariHost {
        ABBenchmarkSafariHost(
            url: url
        )
    }

    func updateUIViewController(
        _ uiViewController:
            ABBenchmarkSafariHost,
        context: Context
    ) {}
}

private final class ABBenchmarkSafariHost:
    UIViewController,
    SFSafariViewControllerDelegate
{
    private let url: URL
    private var didPresent = false

    init(url: URL) {
        self.url = url
        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    required init?(
        coder: NSCoder
    ) {
        fatalError(
            "init(coder:) has not been implemented"
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor =
            .systemBackground

        SFSafariViewController
            .prewarmConnections(
                to: [url]
            )
    }

    override func viewDidAppear(
        _ animated: Bool
    ) {
        super.viewDidAppear(
            animated
        )

        guard !didPresent else {
            return
        }

        didPresent = true

        ABBenchmarkMarker.perform(
            fixtureURL: url
        ) { [weak self] in
            self?.presentSafari()
        }
    }

    private func presentSafari() {
        let configuration =
            SFSafariViewController
                .Configuration()

        configuration
            .entersReaderIfAvailable =
                false

        configuration
            .barCollapsingEnabled =
                true

        let safari =
            SFSafariViewController(
                url: url,
                configuration:
                    configuration
            )

        safari.delegate = self
        safari.dismissButtonStyle =
            .close
        safari.modalPresentationStyle =
            .fullScreen

        present(
            safari,
            animated: false
        )
    }
}

private struct ABBenchmarkWKView:
    UIViewRepresentable
{
    let url: URL

    func makeUIView(
        context: Context
    ) -> WKWebView {
        let configuration =
            WKWebViewConfiguration()

        configuration.websiteDataStore =
            .default()

        configuration
            .defaultWebpagePreferences
            .allowsContentJavaScript =
                true

        let webView =
            WKWebView(
                frame: .zero,
                configuration:
                    configuration
            )

        webView.isInspectable = true
        webView.scrollView
            .contentInsetAdjustmentBehavior =
                .automatic

        ABBenchmarkMarker.perform(
            fixtureURL: url
        ) {
            var request =
                URLRequest(url: url)

            request.cachePolicy =
                .reloadIgnoringLocalCacheData

            webView.load(request)
        }

        return webView
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {}
}

struct ABBenchmarkSequenceConfig {
    let baseURL: URL

    static var current:
        ABBenchmarkSequenceConfig?
    {
        let args =
            ProcessInfo.processInfo.arguments

        guard
            args.contains(
                "--ab-benchmark-sequence"
            )
        else {
            return nil
        }

        var raw =
            "http://127.0.0.1:8765/fixture"

        if
            let index =
                args.firstIndex(
                    of:
                        "--ab-benchmark-base-url"
                ),
            args.indices.contains(
                index + 1
            )
        {
            raw = args[index + 1]
        }

        guard
            let url =
                URL(string: raw)
        else {
            return nil
        }

        return .init(
            baseURL: url
        )
    }
}

struct ABBenchmarkSequenceView:
    UIViewControllerRepresentable
{
    let config:
        ABBenchmarkSequenceConfig

    func makeUIViewController(
        context: Context
    ) -> ABBenchmarkSequenceController {
        ABBenchmarkSequenceController(
            baseURL:
                config.baseURL
        )
    }

    func updateUIViewController(
        _ uiViewController:
            ABBenchmarkSequenceController,
        context: Context
    ) {}
}

final class ABBenchmarkSequenceController:
    UIViewController,
    SFSafariViewControllerDelegate,
    WKNavigationDelegate
{
    private struct Run {
        let mode: ABBenchmarkMode
        let scenario: String
        let iteration: Int
    }

    private let baseURL: URL

    private lazy var runs: [Run] = {
        var items: [Run] = []

        for scenario in [
            "raw",
            "pruned"
        ] {
            for mode in [
                ABBenchmarkMode.safari,
                ABBenchmarkMode.wk
            ] {
                for iteration in 0..<3 {
                    items.append(
                        .init(
                            mode: mode,
                            scenario:
                                scenario,
                            iteration:
                                iteration
                        )
                    )
                }
            }
        }

        return items
    }()

    private var index = 0
    private var advancing = false
    private var timeoutWorkItem:
        DispatchWorkItem?

    private weak var activeSafari:
        SFSafariViewController?
    private weak var activeWebView:
        WKWebView?

    private let statusLabel =
        UILabel()

    init(baseURL: URL) {
        self.baseURL = baseURL

        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    required init?(
        coder: NSCoder
    ) {
        fatalError(
            "init(coder:) has not been implemented"
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor =
            .systemBackground

        statusLabel
            .translatesAutoresizingMaskIntoConstraints =
                false
        statusLabel.font =
            UIFont.monospacedSystemFont(
                ofSize: 11,
                weight: .semibold
            )
        statusLabel.numberOfLines = 3
        statusLabel
            .accessibilityIdentifier =
                "ab.sequence.status"
        statusLabel
            .isAccessibilityElement =
                true

        view.addSubview(
            statusLabel
        )

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(
                equalTo:
                    view.safeAreaLayoutGuide
                        .leadingAnchor,
                constant: 10
            ),
            statusLabel.topAnchor.constraint(
                equalTo:
                    view.safeAreaLayoutGuide
                        .topAnchor,
                constant: 10
            ),
            statusLabel.trailingAnchor.constraint(
                lessThanOrEqualTo:
                    view.safeAreaLayoutGuide
                        .trailingAnchor,
                constant: -10
            )
        ])

        SFSafariViewController
            .prewarmConnections(
                to: [baseURL]
            )

        DispatchQueue.main.async {
            [weak self] in
            self?.runNext()
        }
    }

    private func makeURL(
        run: Run
    ) -> URL? {
        guard
            var components =
                URLComponents(
                    url: baseURL,
                    resolvingAgainstBaseURL:
                        false
                )
        else {
            return nil
        }

        let runID =
            (
                run.mode.rawValue +
                "-" +
                run.scenario +
                "-" +
                String(
                    run.iteration
                ) +
                "-" +
                String(
                    Int(
                        Date()
                            .timeIntervalSince1970 *
                        1000
                    )
                )
            )

        components.queryItems = [
            URLQueryItem(
                name: "mode",
                value:
                    run.mode.rawValue
            ),
            URLQueryItem(
                name: "scenario",
                value:
                    run.scenario
            ),
            URLQueryItem(
                name: "run",
                value:
                    runID
            )
        ]

        return components.url
    }

    private func runNext() {
        guard
            !advancing
        else {
            return
        }

        if index >= runs.count {
            statusLabel.text =
                "DONE 12/12"
            statusLabel
                .accessibilityLabel =
                    "DONE 12/12"
            return
        }

        let run =
            runs[index]

        guard
            let url =
                makeURL(run: run)
        else {
            finishCurrent(
                status:
                    "BAD_URL"
            )
            return
        }

        let text =
            (
                String(
                    index + 1
                ) +
                "/12 " +
                run.mode.rawValue +
                " " +
                run.scenario +
                " #" +
                String(
                    run.iteration + 1
                )
            )

        statusLabel.text = text
        statusLabel
            .accessibilityLabel =
                text

        ABBenchmarkMarker.perform(
            fixtureURL: url
        ) { [weak self] in
            guard let self else {
                return
            }

            switch run.mode {
            case .safari:
                self
                    .startSafari(
                        url: url
                    )

            case .wk:
                self
                    .startWK(
                        url: url
                    )
            }
        }

        scheduleTimeout(
            seconds: 11.0
        )
    }

    private func startSafari(
        url: URL
    ) {
        let configuration =
            SFSafariViewController
                .Configuration()

        configuration
            .entersReaderIfAvailable =
                false
        configuration
            .barCollapsingEnabled =
                true

        let safari =
            SFSafariViewController(
                url: url,
                configuration:
                    configuration
            )

        safari.delegate = self
        safari.modalPresentationStyle =
            .fullScreen
        safari.dismissButtonStyle =
            .close

        activeSafari = safari

        present(
            safari,
            animated: false
        ) { [weak self] in
            DispatchQueue.main
                .asyncAfter(
                    deadline:
                        .now() + 7.0
                ) {
                    self?
                        .finishCurrent(
                            status:
                                "safari-done"
                        )
                }
        }
    }

    private func startWK(
        url: URL
    ) {
        let configuration =
            WKWebViewConfiguration()

        configuration.websiteDataStore =
            .nonPersistent()

        configuration
            .defaultWebpagePreferences
            .allowsContentJavaScript =
                true

        let webView =
            WKWebView(
                frame: .zero,
                configuration:
                    configuration
            )

        webView.navigationDelegate =
            self
        webView
            .translatesAutoresizingMaskIntoConstraints =
                false

        activeWebView = webView

        view.insertSubview(
            webView,
            belowSubview:
                statusLabel
        )

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(
                equalTo:
                    view.leadingAnchor
            ),
            webView.trailingAnchor.constraint(
                equalTo:
                    view.trailingAnchor
            ),
            webView.topAnchor.constraint(
                equalTo:
                    view.topAnchor
            ),
            webView.bottomAnchor.constraint(
                equalTo:
                    view.bottomAnchor
            )
        ])

        var request =
            URLRequest(url: url)

        request.cachePolicy =
            .reloadIgnoringLocalCacheData

        webView.load(request)
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation:
            WKNavigation!
    ) {
        DispatchQueue.main
            .asyncAfter(
                deadline:
                    .now() + 7.0
            ) { [weak self, weak webView] in
                guard
                    let self,
                    webView ===
                        self.activeWebView
                else {
                    return
                }

                self.finishCurrent(
                    status:
                        "wk-done"
                )
            }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation
            navigation:
                WKNavigation!,
        withError error: Error
    ) {
        finishCurrent(
            status:
                "wk-provisional-fail"
        )
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation:
            WKNavigation!,
        withError error: Error
    ) {
        finishCurrent(
            status:
                "wk-fail"
        )
    }

    func webViewWebContentProcessDidTerminate(
        _ webView: WKWebView
    ) {
        finishCurrent(
            status:
                "wk-terminated"
        )
    }

    private func scheduleTimeout(
        seconds: TimeInterval
    ) {
        timeoutWorkItem?
            .cancel()

        let work =
            DispatchWorkItem {
                [weak self] in
                self?.finishCurrent(
                    status:
                        "timeout"
                )
            }

        timeoutWorkItem = work

        DispatchQueue.main
            .asyncAfter(
                deadline:
                    .now() + seconds,
                execute: work
            )
    }

    private func finishCurrent(
        status: String
    ) {
        guard
            !advancing
        else {
            return
        }

        advancing = true

        timeoutWorkItem?
            .cancel()
        timeoutWorkItem = nil

        let cleanup = {
            [weak self] in
            guard let self else {
                return
            }

            if
                let webView =
                    self.activeWebView
            {
                webView
                    .stopLoading()
                webView
                    .navigationDelegate =
                        nil
                webView
                    .removeFromSuperview()
            }

            self.activeWebView =
                nil
            self.activeSafari =
                nil

            self.index += 1
            self.advancing =
                false

            DispatchQueue.main
                .asyncAfter(
                    deadline:
                        .now() + 0.35
                ) {
                    self.runNext()
                }
        }

        if presentedViewController
            != nil
        {
            dismiss(
                animated: false
            ) {
                cleanup()
            }
        } else {
            cleanup()
        }
    }

    func safariViewControllerDidFinish(
        _ controller:
            SFSafariViewController
    ) {
        finishCurrent(
            status:
                "safari-finished"
        )
    }
}

#endif
