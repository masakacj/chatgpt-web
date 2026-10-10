import Foundation
import UIKit
import WebKit
import QuartzCore

// Opt-in, privacy-minimal diagnostics for the real WKWebView process.
// This intentionally uses the existing Cloudflare telemetry endpoint/schema.
// No chat text, URL, conversation identifier, cookies or device identifier
// is sampled or uploaded. No extra polling when diagnostics is disabled.
final class ChatGPTNativePerformanceProbe {
    private static let consentKey = "ChatGPTWeb.nativePerfConsent.v1"
    private static let installKey = "ChatGPTWeb.nativePerfInstall.v1"

    private let endpoint = URL(
        string: "https://chatgpt-web-telemetry.masakacj.workers.dev/v1/telemetry"
    )!
    private let sessionId = "ns_" + UUID().uuidString.replacingOccurrences(
        of: "-", with: ""
    )
    private let installId: String
    private var isEnabled: Bool
    private weak var currentWebView: WKWebView?
    private var navigationSerial = 0
    private var navigationStartedAt = CACurrentMediaTime()
    private var pendingProbes = Set<String>()

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.consentKey)
        if let saved = defaults.string(forKey: Self.installKey),
           saved.range(of: #"^[A-Za-z0-9_-]{8,64}$"#,
                       options: .regularExpression) != nil {
            installId = saved
        } else {
            let id = "ni_" + UUID().uuidString.replacingOccurrences(
                of: "-", with: ""
            )
            installId = id
            defaults.set(id, forKey: Self.installKey)
        }
    }

    private var allowedToCollect: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return isEnabled && !arguments.contains("--ui-testing")
            && !arguments.contains("--webkit-stress")
    }

    func setEnabled(_ enabled: Bool) {
        let changed = isEnabled != enabled
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.consentKey)
        // The hot-update userscript synchronizes consent on every navigation.
        // Do not re-arm timers when the preference has not changed.
        guard changed else { return }
        pendingProbes.removeAll()
        if allowedToCollect, let view = currentWebView {
            send("ios_opt_in", for: view)
            scheduleProbes(for: view, serial: navigationSerial)
        }
    }

    func navigationStarted(_ webView: WKWebView) {
        currentWebView = webView
        navigationSerial += 1
        navigationStartedAt = CACurrentMediaTime()
        pendingProbes.removeAll()
        guard allowedToCollect else { return }
        // didStart may run before WKWebView.url resolves to the new URL.
        // Individual probes check the origin after navigation commits.
        send("ios_nav_start", for: webView)
        scheduleProbes(for: webView, serial: navigationSerial)
    }

    func navigationCommitted(_ webView: WKWebView) {
        guard allowedToCollect, isChatGPT(webView) else { return }
        send("ios_nav_commit", for: webView)
    }

    func navigationFinished(_ webView: WKWebView) {
        guard allowedToCollect, isChatGPT(webView) else { return }
        send("ios_nav_finish", for: webView)
    }

    func webContentTerminated(_ webView: WKWebView) {
        guard allowedToCollect, isChatGPT(webView) else { return }
        send("ios_web_terminated", for: webView)
        pendingProbes.removeAll()
    }

    private func isChatGPT(_ view: WKWebView) -> Bool {
        guard let host = view.url?.host?.lowercased() else { return false }
        return host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
    }

    private func routeKind(for view: WKWebView) -> String {
        guard isChatGPT(view) else { return "other" }
        return view.url?.path.contains("/c/") == true ? "conversation" : "home"
    }

    private func elapsedMs() -> Int {
        return max(0, min(86_400_000, Int(
            (CACurrentMediaTime() - navigationStartedAt) * 1000
        )))
    }

    private func scheduleProbes(for webView: WKWebView, serial: Int) {
        for seconds in [3, 8, 15, 30, 60] {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .seconds(seconds)
            ) { [weak self, weak webView] in
                guard let self, let webView,
                    self.allowedToCollect,
                    self.navigationSerial == serial,
                    UIApplication.shared.applicationState == .active,
                    self.isChatGPT(webView)
                else { return }
                self.probe(webView, seconds: seconds, serial: serial)
            }
        }
    }

    private func probe(
        _ webView: WKWebView,
        seconds: Int,
        serial: Int
    ) {
        let label = String(format: "%02d", seconds)
        let key = "\(serial)-\(label)"
        guard pendingProbes.insert(key).inserted else { return }
        let beganAt = CACurrentMediaTime()

        // A CDP-style page query isn't available in WKWebView. This tiny
        // evaluateJavaScript call instead measures whether the content
        // process can answer promptly and whether the last DOM answer exists.
        // No text is returned, no history is mutated, no navigation is added.
        let expression = """
        (() => {
          const transcript = document.querySelector(
            'main [class*="transcriptContent"]'
          );
          const turns = transcript?.querySelectorAll('[data-turn-key]') || [];
          const turn = turns.length ? turns[turns.length - 1] : null;
          const roots = turn?.querySelectorAll('[class*="DilResponseRoot"]') || [];
          const answer = roots.length ? roots[roots.length - 1] : null;
          const rect = answer?.getBoundingClientRect();
          const textReady = (answer?.textContent || '').trim().length >= 24;
          const lastStates = turn?.querySelectorAll('[data-talvt-turn-state]') || [];
          const state = lastStates.length
            ? lastStates[lastStates.length - 1].getAttribute('data-talvt-turn-state')
            : null;
          return {
            turns: turns.length,
            textReady,
            inViewport: !!(textReady && rect && rect.height > 0 &&
              rect.width > 0 && rect.bottom > 0 && rect.top < innerHeight),
            aboveViewport: !!(textReady && rect && rect.bottom < -20),
            belowViewport: !!(textReady && rect && rect.top > innerHeight + 20),
            streaming: state === 'in_progress' || state === 'running'
          };
        })()
        """

        // Native timeout still fires even when the WebKit JS thread is frozen.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(7)
        ) { [weak self, weak webView] in
            guard let self, let webView,
                self.navigationSerial == serial,
                self.pendingProbes.remove(key) != nil
            else { return }
            self.send(
                "ios_\(label)_timeout",
                for: webView,
                queryMs: Int((CACurrentMediaTime() - beganAt) * 1000)
            )
        }

        webView.evaluateJavaScript(expression) { [weak self, weak webView] result, error in
            guard let self, let webView,
                self.navigationSerial == serial,
                self.pendingProbes.remove(key) != nil
            else { return }

            let duration = Int((CACurrentMediaTime() - beganAt) * 1000)
            guard error == nil,
                  let snapshot = result as? [String: Any]
            else {
                self.send("ios_\(label)_error", for: webView, queryMs: duration)
                return
            }

            let ready = snapshot["textReady"] as? Bool == true
            let visible = snapshot["inViewport"] as? Bool == true
            let above = snapshot["aboveViewport"] as? Bool == true
            let below = snapshot["belowViewport"] as? Bool == true
            // Distinguishes an actual blank/missing answer from the previous
            // bug where turn.scrollIntoView positioned the final reply
            // above an oversized virtual spacer.
            let stage = visible ? "visible"
                : (ready ? (above ? "above" : (below ? "below" : "text"))
                         : "empty")
            self.send(
                "ios_\(label)_\(stage)",
                for: webView,
                queryMs: duration,
                mountedTurns: snapshot["turns"] as? Int ?? 0,
                streaming: snapshot["streaming"] as? Bool ?? false
            )
        }
    }

    private func send(
        _ reason: String,
        for view: WKWebView,
        queryMs: Int = 0,
        mountedTurns: Int = 0,
        streaming: Bool = false
    ) {
        guard allowedToCollect, isChatGPT(view) else { return }

        let latency = max(0, min(60_000, queryMs))
        let sample: [String: Any] = [
            "mode": "native",
            "routeKind": routeKind(for: view),
            "reason": String(reason.prefix(24)),
            "uptimeMs": elapsedMs(),
            "mountedTurns": max(0, min(mountedTurns, 100_000)),
            "streaming": streaming,
            "loopCount": queryMs > 0 ? 1 : 0,
            "loopMaxMs": latency,
            "loopGt50": queryMs > 50 ? 1 : 0,
            "loopGt100": queryMs > 100 ? 1 : 0,
            "loopGt250": queryMs > 250 ? 1 : 0
        ]
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let payload: [String: Any] = [
            "schema": 1,
            "installId": installId,
            "sessionId": sessionId,
            "scriptVersion": version,
            "appVersion": version,
            "samples": [sample]
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload
        ), data.count < 64 * 1024 else { return }

        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = data
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-ChatGPT-Web-Telemetry")
        URLSession.shared.dataTask(with: request).resume()
    }
}
