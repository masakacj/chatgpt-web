import Foundation
import SwiftUI

/// Native-only, content-free events sent through the existing CF/D1 telemetry endpoint.
/// The WebKit page and injected JavaScript never see the endpoint or install identifier.
@MainActor
final class OptimizedTelemetry: ObservableObject {
    enum Event: String {
        case launch
        case foreground
        case background
        case heartbeat
        case navigationStart = "nav_start"
        case navigationFinish = "nav_finish"
        case navigationError = "nav_error"
        case contentTerminated = "web_terminated"
        case automaticRecovery = "auto_recovery"
        case recoveryPaused = "recovery_paused"
        case manualRecovery = "manual_recovery"
        case memoryWarning = "memory_warning"
        case downloadError = "download_error"
        case enabled = "logging_enabled"
        case thermalChange = "thermal_change"
    }

    private struct QueuedEvent: Codable {
        let eventId: String
        let sessionId: String
        let reason: String
        let routeKind: String
        let uptimeMs: Int
        let streaming: Bool
    }

    private struct TelemetrySample: Encodable {
        let debugId: String
        let mode: String
        let routeKind: String
        let reason: String
        let uptimeMs: Int
        let streaming: Bool
    }

    private struct TelemetryBatch: Encodable {
        let schema: Int
        let installId: String
        let sessionId: String
        let scriptVersion: String
        let appVersion: String
        let gestureVersion: String
        let samples: [TelemetrySample]
    }

    private struct Acknowledgement: Decodable {
        let ok: Bool
        let accepted: Int
    }

    private static let endpoint = URL(
        string: "https://chatgpt-web-telemetry.masakacj.workers.dev/v1/telemetry"
    )!
    private static let installKey = "optimized.telemetry.installId.v1"
    private static let enabledKey = "optimized.telemetry.enabled.v1"
    private static let pendingKey = "optimized.telemetry.pending.v1"
    private static let queueLimit = 80
    private static let batchLimit = 12

    private let defaults: UserDefaults
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var queued: [QueuedEvent] = []
    private var lastSendAttempt = Date.distantPast
    private var nextSendAllowed = Date.distantPast
    private var lastHeartbeat = Date.distantPast
    private var consecutiveErrors = 0
    private var isSending = false
    private var counter = 0
    private var lastThermalState: ProcessInfo.ThermalState?
    private var lastLifecycleEvent: Event?

    let installId: String
    let sessionId: String
    let appVersion: String

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                record(.enabled, urgent: true)
            } else {
                queued.removeAll()
                persist()
                state = "已关闭"
            }
        }
    }

    @Published private(set) var pendingCount = 0
    @Published private(set) var state = "尚未上报"
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var lastEvent = "—"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let existing = defaults.string(forKey: Self.installKey),
           existing.range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil {
            installId = existing
        } else {
            let newId = "ios_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            installId = newId
            defaults.set(newId, forKey: Self.installKey)
        }
        sessionId = "s_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        appVersion = String("\(version)+\(build)".prefix(24))
        isEnabled = (defaults.object(forKey: Self.enabledKey) as? Bool) ?? true
        if let data = defaults.data(forKey: Self.pendingKey),
           let recovered = try? JSONDecoder().decode([QueuedEvent].self, from: data) {
            queued = Array(recovered.suffix(Self.queueLimit))
        }
        pendingCount = queued.count
        if !isEnabled {
            queued.removeAll()
            defaults.removeObject(forKey: Self.pendingKey)
            pendingCount = 0
            state = "已关闭"
        }
    }

    /// Only an enumerated event, a route category and an integer error code are allowed.
    /// No URL, message, input, cookie, token, project ID or conversation ID is accepted.
    func record(_ event: Event, route: String = "other",
                errorCode: Int? = nil, streaming: Bool = false,
                urgent: Bool = false) {
        guard isEnabled else { return }
        if (event == .background && lastLifecycleEvent == .background) ||
           (event == .foreground && lastLifecycleEvent == .foreground) {
            return
        }
        if event == .background || event == .foreground {
            lastLifecycleEvent = event
        }
        counter += 1
        let routeKind = Self.safeRoute(route, errorCode: errorCode)
        let item = QueuedEvent(
            eventId: "i\(Int(Date().timeIntervalSince1970 * 1000))_\(counter)",
            sessionId: sessionId,
            reason: event.rawValue,
            routeKind: routeKind,
            uptimeMs: max(0, Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)),
            streaming: streaming
        )
        queued.append(item)
        if queued.count > Self.queueLimit {
            queued.removeFirst(queued.count - Self.queueLimit)
        }
        lastEvent = "\(event.rawValue) · \(routeKind)"
        persist()
        if urgent || queued.count >= Self.batchLimit {
            flush()
        }
    }

    func recordThermalStateChange(_ state: ProcessInfo.ThermalState) {
        guard isEnabled else { return }
        guard lastThermalState != state else { return }
        lastThermalState = state
        let stateName: String
        switch state {
        case .nominal: stateName = "nominal"
        case .fair: stateName = "fair"
        case .serious: stateName = "serious"
        case .critical: stateName = "critical"
        @unknown default: stateName = "unknown"
        }
        record(.thermalChange, route: "thermal_\(stateName)", urgent: state == .serious || state == .critical)
    }

    func periodicTick(isActive: Bool) {
        guard isEnabled, isActive else { return }
        if Date().timeIntervalSince(lastHeartbeat) >= 120 {
            lastHeartbeat = Date()
            record(.heartbeat)
        }
        flush()
    }

    /// No work on the WebContent process; failures are retained for the next retry/launch.
    func flush(force: Bool = false) {
        guard isEnabled, !isSending, !queued.isEmpty else { return }
        let now = Date()
        guard now >= nextSendAllowed || force else { return }
        if !force && now.timeIntervalSince(lastSendAttempt) < 12 {
            return
        }
        let headSession = queued[0].sessionId
        let items = Array(queued.prefix(while: { $0.sessionId == headSession })
            .prefix(Self.batchLimit))
        let batch = TelemetryBatch(
            schema: 1,
            installId: installId,
            sessionId: headSession,
            scriptVersion: "optimized-native-1",
            appVersion: appVersion,
            gestureVersion: "",
            samples: items.map {
                TelemetrySample(debugId: $0.eventId, mode: "ios-optimized",
                                routeKind: $0.routeKind, reason: $0.reason,
                                uptimeMs: $0.uptimeMs, streaming: $0.streaming)
            }
        )
        guard let data = try? JSONEncoder().encode(batch) else { return }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios-optimized", forHTTPHeaderField: "X-ChatGPT-Web-Telemetry")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        lastSendAttempt = now
        isSending = true
        state = "正在上报"

        Task {
            do {
                let (responseData, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 202,
                      let receipt = try? JSONDecoder().decode(Acknowledgement.self,
                                                              from: responseData),
                      receipt.ok, receipt.accepted == items.count else {
                    throw URLError(.badServerResponse)
                }
                // If logging was disabled mid-request, do not restore the cleared queue.
                let transmitted = Set(items.map(\.eventId))
                queued.removeAll { transmitted.contains($0.eventId) }
                consecutiveErrors = 0
                nextSendAllowed = .distantPast
                lastSuccess = Date()
                state = isEnabled ? "已上报" : "已关闭"
                persist()
                isSending = false
                // Send following batches gradually, without spawning overlapping tasks.
                if !queued.isEmpty { flush() }
            } catch {
                consecutiveErrors = min(6, consecutiveErrors + 1)
                let delay = min(300.0, 15.0 * pow(2.0, Double(consecutiveErrors - 1)))
                nextSendAllowed = Date().addingTimeInterval(delay)
                state = isEnabled ? "上传失败，待重试" : "已关闭"
                isSending = false
            }
        }
    }

    static func safeRoute(_ raw: String, errorCode: Int? = nil) -> String {
        let category: String
        switch raw {
        case "home", "conversation", "project", "other",
             "thermal_nominal", "thermal_fair", "thermal_serious", "thermal_critical":
            category = raw
        default:
            category = "other"
        }
        guard let errorCode else { return category }
        return String("\(category)_e\(errorCode)".prefix(24))
    }

    var localReport: String {
        let thermalDesc = Self.thermalStateString(ProcessInfo.processInfo.thermalState)
        return """
        ChatGPT Web Optimized · 原生诊断
        版本: \(appVersion)
        iOS: \(UIDevice.current.systemVersion)
        会话: \(sessionId)
        安装标识: \(installId)
        热状态: \(thermalDesc)
        远程采集: \(isEnabled ? "开启" : "关闭")
        状态: \(state)
        待上传事件: \(pendingCount)
        最近事件: \(lastEvent)

        只收集事件类别、页面类型和数字错误码；不采集对话内容或请求凭证。
        """
    }

    static func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "正常"
        case .fair: return "温热"
        case .serious: return "较热"
        case .critical: return "严重过热"
        @unknown default: return "未知"
        }
    }

    private func persist() {
        pendingCount = queued.count
        if queued.isEmpty {
            defaults.removeObject(forKey: Self.pendingKey)
        } else if let data = try? JSONEncoder().encode(queued) {
            defaults.set(data, forKey: Self.pendingKey)
        }
    }
}
