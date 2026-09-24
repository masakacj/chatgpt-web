import Foundation

enum AppConfig {
    static let homeURL = URL(string: "https://chatgpt.com/")!
    static let repository = "masakacj/chatgpt-web"
    static let repositoryURL = URL(string: "https://github.com/masakacj/chatgpt-web")!
    static let remoteManifestURL = URL(
        string: "https://raw.githubusercontent.com/masakacj/chatgpt-web/main/remote/manifest.json"
    )!

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var fullVersion: String {
        "\(appVersion) (\(buildNumber))"
    }
}

enum OptimizationMode: String, CaseIterable, Identifiable, Codable {
    case auto
    case balanced
    case aggressive
    case extreme
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "自动"
        case .balanced: "平衡"
        case .aggressive: "激进"
        case .extreme: "极限"
        case .off: "关闭"
        }
    }
}

struct PerfMetrics: Equatable {
    var turns = 0
    var hot = 0
    var warm = 0
    var cold = 0
    var packed = 0
    var domNodes = 0
    var longTaskMs = 0.0
    var streaming = false
    var effectiveMode = "off"
    var engineVersion = "bundled"
}
