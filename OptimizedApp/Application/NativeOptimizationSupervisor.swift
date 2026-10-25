import Foundation
import Combine

/// NativeOptimizationSupervisor
/// Independent of WKWebView/JS and SwiftUI app process.
/// Manages durable bounded failure journal in Optimized-only UserDefaults,
/// enforces 2 verified terminations / 10-minute fail-closed threshold (circuit breaker),
/// and manages safe mode state across lifecycles.
@MainActor
public final class NativeOptimizationSupervisor: ObservableObject {
    public struct JournalEntry: Codable, Equatable {
        public let timestamp: Date
        public let kind: String
        public let route: String
        public let isVerified: Bool

        public init(timestamp: Date = Date(), kind: String, route: String = "other", isVerified: Bool = false) {
            self.timestamp = timestamp
            self.kind = kind
            self.route = route
            self.isVerified = isVerified
        }
    }

    // Keys strictly isolated to Optimized app sandbox
    public static let journalKey = "optimized.supervisor.journal.v1"
    public static let circuitOpenKey = "optimized.supervisor.circuitOpen.v1"
    public static let sessionActiveKey = "optimized.supervisor.sessionActive.v1"
    public static let lastExitKindKey = "optimized.supervisor.lastExitKind.v1"

    public static let maxJournalEntries = 40
    public static let failClosedThreshold = 2
    public static let failClosedWindowSeconds: TimeInterval = 600 // 10 minutes

    private let defaults: UserDefaults

    @Published public private(set) var isSafeModeActive: Bool = false
    @Published public private(set) var isCircuitOpen: Bool = false
    @Published public private(set) var verifiedTerminationCount: Int = 0
    @Published public private(set) var journal: [JournalEntry] = []
    @Published public private(set) var lastFailureReason: String?

    public init(defaults: UserDefaults = .standard) {
        // UI-test injected circuit uses a separate preference domain, never the user's durable journal.
        let fixture = ProcessInfo.processInfo.arguments.contains("-uitest-circuit-open")
        self.defaults = (fixture ? UserDefaults(suiteName: "optimized.native.ui-test-circuit.v1") : nil) ?? defaults
        loadPersistedState()
    }

    // MARK: - Lifecycle

    public func recordLaunch() {
        let wasActive = defaults.bool(forKey: Self.sessionActiveKey)
        if wasActive {
            // Unclean exit from previous session.
            // Under contract: after an unknown whole-app death do NOT claim jetsam/OOM proven.
            appendEntry(JournalEntry(timestamp: Date(), kind: "unknown_shutdown", route: "other", isVerified: false))
        }

        defaults.set(true, forKey: Self.sessionActiveKey)
        defaults.set("running", forKey: Self.lastExitKindKey)

        appendEntry(JournalEntry(timestamp: Date(), kind: "launch", route: "other", isVerified: false))

        recalculateCircuitState()
        if isCircuitOpen {
            isSafeModeActive = true
            lastFailureReason = "熔断保护已开启：10分钟内发生多次异常退出，已进入安全模式。"
        }
        persistState()
    }

    public func recordForeground() {
        defaults.set(true, forKey: Self.sessionActiveKey)
        defaults.set("foreground", forKey: Self.lastExitKindKey)
    }

    public func recordBackground() {
        // Scene background alone does not count as crash
        defaults.set(false, forKey: Self.sessionActiveKey)
        defaults.set("background", forKey: Self.lastExitKindKey)
        appendEntry(JournalEntry(timestamp: Date(), kind: "background", route: "other", isVerified: false))
        persistState()
    }

    // MARK: - WebContent Process Termination

    public func recordWebContentTermination(route: String = "other", isSynthetic: Bool = false) {
        let safeRoute = Self.sanitizeRoute(route)
        if isSynthetic {
            // User-initiated synthetic test fixture.
            // MUST be explicitly labeled SIMULATED, not fake memory OOM;
            // exercises Supervisor and safe UI without counting as a verified hardware termination.
            appendEntry(JournalEntry(timestamp: Date(), kind: "simulated_termination", route: safeRoute, isVerified: false))
            isSafeModeActive = true
            lastFailureReason = "已触发模拟 WebContent 进程终止演练（SIMULATED）。"
        } else {
            // Real verified WebContent process termination from WKNavigationDelegate.
            appendEntry(JournalEntry(timestamp: Date(), kind: "verified_termination", route: safeRoute, isVerified: true))
            recalculateCircuitState(recordingNewTermination: true)
            isSafeModeActive = true
            if isCircuitOpen {
                lastFailureReason = "10分钟内发生 \(verifiedTerminationCount) 次网页崩溃，已触发熔断保护。"
            } else {
                lastFailureReason = "网页进程异常停止，已进入安全模式。"
            }
        }
        persistState()
    }

    // MARK: - User-confirmed Actions

    public func confirmRebuild() {
        appendEntry(JournalEntry(timestamp: Date(), kind: "user_rebuild", route: "home", isVerified: false))
        isSafeModeActive = false
        isCircuitOpen = false
        defaults.set(false, forKey: Self.circuitOpenKey)
        lastFailureReason = nil
        persistState()
    }

    public func stayInSafeMode() {
        isSafeModeActive = true
    }

    public func resetCircuit() {
        isCircuitOpen = false
        isSafeModeActive = false
        defaults.set(false, forKey: Self.circuitOpenKey)
        persistState()
    }

    // MARK: - Diagnostics & Export

    public func exportReport(telemetryReport: String? = nil) -> String {
        let dateStr = ISO8601DateFormatter().string(from: Date())
        var lines = [
            "=== ChatGPT Web Optimized 原生安全诊断 ===",
            "时间: \(dateStr)",
            "安全模式: \(isSafeModeActive ? "已激活" : "未激活")",
            "熔断保护: \(isCircuitOpen ? "开启 (Fail-Closed)" : "关闭")",
            "近期已验证终止次数 (10分钟内): \(verifiedTerminationCount)",
            "最后状态: \(lastFailureReason ?? "正常")",
            "",
            "--- 故障与生命周期日志 (最近 \(journal.count) 条) ---"
        ]

        for (idx, entry) in journal.suffix(15).enumerated() {
            let entryTime = ISO8601DateFormatter().string(from: entry.timestamp)
            lines.append("[\(idx + 1)] \(entryTime) · 类型: \(entry.kind) · 路径: \(entry.route) · 已验证: \(entry.isVerified)")
        }

        if let telemetryReport, !telemetryReport.isEmpty {
            lines.append("")
            lines.append("--- 遥测摘要 ---")
            lines.append(telemetryReport)
        }

        lines.append("")
        lines.append("安全声明: 仅记录本地生命周期事件与错误类别，不包含任何对话内容、URL 参数、Cookie、Token 或凭据。")
        return lines.joined(separator: "\n")
    }

    // MARK: - Internal Helpers

    public static func sanitizeRoute(_ raw: String) -> String {
        switch raw {
        case "home", "conversation", "project", "other":
            return raw
        default:
            return "other"
        }
    }

    private func appendEntry(_ entry: JournalEntry) {
        journal.append(entry)
        if journal.count > Self.maxJournalEntries {
            journal.removeFirst(journal.count - Self.maxJournalEntries)
        }
    }

    private func recalculateCircuitState(recordingNewTermination: Bool = false) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-Self.failClosedWindowSeconds)
        let recentVerified = journal.filter { $0.isVerified && $0.timestamp >= cutoff }
        verifiedTerminationCount = recentVerified.count
        // Only a NEW verified exit may reopen a circuit the user explicitly acknowledged.
        isCircuitOpen = defaults.bool(forKey: Self.circuitOpenKey)
        if recordingNewTermination && verifiedTerminationCount >= Self.failClosedThreshold {
            isCircuitOpen = true
            defaults.set(true, forKey: Self.circuitOpenKey)
        }
        if isCircuitOpen {
            isSafeModeActive = true
            if lastFailureReason == nil {
                lastFailureReason = "熔断保护已开启：10分钟内发生多次异常退出，已进入安全模式。"
            }
        }
    }

    private func loadPersistedState() {
        if ProcessInfo.processInfo.arguments.contains("-uitest-circuit-open") {
            defaults.set(true, forKey: Self.circuitOpenKey)
        }
        if let data = defaults.data(forKey: Self.journalKey),
           let saved = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            journal = Array(saved.suffix(Self.maxJournalEntries))
        } else {
            journal = []
        }
        isCircuitOpen = defaults.bool(forKey: Self.circuitOpenKey)
        recalculateCircuitState()
        if isCircuitOpen {
            isSafeModeActive = true
            lastFailureReason = "熔断保护已开启：10分钟内发生多次异常退出，已进入安全模式。"
        }
    }

    private func persistState() {
        if let data = try? JSONEncoder().encode(journal) {
            defaults.set(data, forKey: Self.journalKey)
        }
        defaults.set(isCircuitOpen, forKey: Self.circuitOpenKey)
    }
}
