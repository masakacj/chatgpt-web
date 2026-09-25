import SwiftUI
import UIKit
import WebKit

struct ChatGPTWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()

        if let scriptURL = Bundle.main.url(forResource: "chatgpt-safari.user", withExtension: "js"),
           let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
            controller.addUserScript(
                WKUserScript(
                    source: source,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }

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

        context.coordinator.webView = webView

        var request = URLRequest(url: URL(string: "https://chatgpt.com/")!)
        request.cachePolicy = .useProtocolCachePolicy
        webView.load(request)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?

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
                UIAlertAction(title: "OK", style: .default) { _ in completionHandler() }
            ])
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            presentAlert(title: nil, message: message, actions: [
                UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) },
                UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) }
            ])
        }

        private func presentAlert(title: String?, message: String, actions: [UIAlertAction]) {
            guard let presenter = topViewController() else {
                actions.first?.handler?(actions.first!)
                return
            }

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            actions.forEach(alert.addAction)
            presenter.present(alert, animated: true)
        }

        private func topViewController() -> UIViewController? {
            guard
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            else { return nil }

            var current = root
            while let presented = current.presentedViewController {
                current = presented
            }
            return current
        }
    }
}
