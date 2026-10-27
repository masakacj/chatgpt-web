import Combine
import Foundation
import UIKit
import WebKit

/// Opt-in ephemeral remote diagnostics. No chat text, URLs, credentials or arbitrary remote JS.
@MainActor
final class OptimizedLiveDebug: ObservableObject {
    private static let base = "https://chatgpt-web-telemetry.masakacj.workers.dev/v1/live/"
    private static let enabledKey = "optimized.liveDebug.enabled.v1"
    private static let roomKey = "optimized.liveDebug.room.v1"
    private static let secretKey = "optimized.liveDebug.secret.v1"
    private let defaults: UserDefaults
    let room: String
    private let secret: String
    weak var webView: WKWebView?
    weak var resourceGate: NativeResourceGate?
    weak var supervisor: NativeOptimizationSupervisor?
    private var navigationStarted: CFAbsoluteTime?
    private var navigationMs = 0.0
    private var loop: Task<Void, Never>?
    private var foreground = true
    private var activeUntil = Date.distantPast
    private let activeInterval: TimeInterval = 3.0
    private let idleInterval: TimeInterval = 20.0

    var pollInterval: TimeInterval {
        Date() < activeUntil ? activeInterval : idleInterval
    }

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { start() } else { stop() }
        }
    }
    @Published private(set) var state = "关闭"
    @Published private(set) var lastProbe = "—"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func randomString() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "") }
        let room = defaults.string(forKey: Self.roomKey) ?? "ios_" + randomString()
        let secret = defaults.string(forKey: Self.secretKey) ?? randomString() + randomString()
        self.room = room
        self.secret = secret
        defaults.set(room, forKey: Self.roomKey)
        defaults.set(secret, forKey: Self.secretKey)
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// Only disclose via explicit local user action; never write the pairing secret to telemetry.
    var pairingCode: String { room + ":" + secret }

    func attach(_ view: WKWebView) {
        webView = view
        start()
    }

    func detach(_ view: WKWebView) {
        if webView === view {
            webView = nil
            stop()
        }
    }

    func setForeground(_ value: Bool) {
        foreground = value
        if value { start() } else { stop() }
    }

    func navigationStart() {
        navigationStarted = CFAbsoluteTimeGetCurrent()
        report(kind: "nav_start")
    }

    func navigationFinish() {
        if let started = navigationStarted {
            navigationMs = max(0, (CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        navigationStarted = nil
        report(kind: "nav_finish", values: ["navMs": navigationMs])
    }

    func navigationError() { report(kind: "nav_error") }
    func processTerminated() { report(kind: "web_terminated") }
    func memoryWarning() { report(kind: "memory_warning") }

    private func start() {
        guard isEnabled, foreground, webView != nil, supervisor?.isSafeModeActive != true, loop == nil else { return }
        state = "实时连接中"
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.isEnabled, self.foreground, self.webView != nil, self.supervisor?.isSafeModeActive != true else {
                    self.stop()
                    return
                }
                await self.poll()
                let interval = self.pollInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        activeUntil = .distantPast
        if !isEnabled {
            state = "关闭"
        } else if supervisor?.isSafeModeActive == true {
            state = "安全模式暂停"
        } else if !foreground {
            state = "后台暂停"
        } else if webView == nil {
            state = "网页未就绪暂停"
        } else {
            state = "暂停"
        }
    }

    private func request(_ action: String, method: String = "GET",
                         payload: [String: Any]? = nil) async throws -> [String: Any] {
        guard let url = URL(string: Self.base + room + "/" + action) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 6
        req.setValue(secret, forHTTPHeaderField: "X-Optimizer-Debug-Key")
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let payload {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (body, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let result = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        return result
    }

    private func report(kind: String, values: [String: Double] = [:]) {
        guard isEnabled, foreground else { return }
        var event: [String: Any] = ["kind": kind]
        values.forEach { event[$0.key] = $0.value }
        Task { [weak self] in
            _ = try? await self?.request("events", method: "POST", payload: ["events": [event]])
        }
    }

    private func poll() async {
        guard isEnabled, foreground, webView != nil, supervisor?.isSafeModeActive != true else {
            stop()
            return
        }
        do {
            let result = try await request("poll")
            state = "实时连接正常"
            guard let commands = result["requests"] as? [[String: Any]] else { return }
            for command in commands {
                guard isEnabled && foreground && webView != nil && supervisor?.isSafeModeActive != true else { return }
                guard let id = command["id"] as? String,
                      UUID(uuidString: id) != nil,
                      command["kind"] as? String == "snapshot" else { continue }
                let sample = await snapshot()
                guard isEnabled && foreground && webView != nil && supervisor?.isSafeModeActive != true else { return }
                _ = try await request("response", method: "POST",
                                      payload: ["id": id, "measurement": sample])
                lastProbe = Date().formatted(date: .omitted, time: .standard)
                activeUntil = Date().addingTimeInterval(60)
            }
        } catch {
            state = "联机失败，自动重试"
        }
    }

    func activateActiveIntervalForTesting(seconds: TimeInterval = 60) {
        activeUntil = Date().addingTimeInterval(seconds)
    }

    /// A fixed numeric-only DOM probe. No textContent, HTML, URL, cookies or site state exposed.
    private func snapshot() async -> [String: Any] {
        var result: [String: Any] = [
            "kind": "snapshot",
            "navMs": navigationMs,
            "resourceRuleCount": NativeResourceGate.approvedRuleCount,
            "resourceGateEnabled": resourceGate?.isEnabled == true ? 1 : 0,
            "safeMode": supervisor?.isSafeModeActive == true ? 1 : 0,
            "webviewAttached": webView == nil ? 0 : 1,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue
        ]
        guard let view = webView else { return result }
        result["webLoading"] = view.isLoading ? 1 : 0
        result["progress"] = view.estimatedProgress * 100
        let js = """
        const nodes = document.querySelectorAll('*');
        const turns = document.querySelectorAll('[data-turn-key],[data-testid^="conversation-turn-"]');
        const last = turns.length ? turns[turns.length - 1] : null;
        const box = last?.getBoundingClientRect();
        return {
            domNodes: nodes.length,
            turns: turns.length,
            imageNodes: document.images.length,
            lastTurnVisible: box && box.bottom > 0 && box.top < innerHeight ? 1 : 0
        };
        """
        do {
            if let values = try await view.callAsyncJavaScript(js, arguments: [:],
                          in: nil, contentWorld: WebConfigurationFactory.observationWorld) as? [String: Any] {
                for key in ["domNodes", "turns", "imageNodes", "lastTurnVisible"] {
                    if let n = values[key] as? NSNumber { result[key] = n.doubleValue }
                }
            }
        } catch { /* Dead WebContent: native status remains available. */ }
        return result
    }
}
