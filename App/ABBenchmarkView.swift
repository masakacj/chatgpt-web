#if DEBUG
import SwiftUI
import UIKit
import WebKit
import SafariServices

enum ABBenchmarkMode: String {
    case safari
    case wk
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

        var request =
            URLRequest(url: url)

        request.cachePolicy =
            .reloadIgnoringLocalCacheData

        webView.load(request)

        return webView
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {}
}
#endif
