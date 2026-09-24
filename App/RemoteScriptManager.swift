import CryptoKit
import Foundation

@MainActor
final class RemoteScriptManager: ObservableObject {
    @Published private(set) var currentVersion: String
    @Published private(set) var currentConfig: RemotePerfConfig
    @Published private(set) var lastCheck: Date?
    @Published private(set) var status: String = "就绪"
    @Published private(set) var latestNotes: String?
    @Published var autoUpdate: Bool {
        didSet { UserDefaults.standard.set(autoUpdate, forKey: "perfAutoUpdate") }
    }

    var onInstalledUpdate: (() -> Void)?

    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var supportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ChatGPTWeb", isDirectory: true)
    }

    private var scriptFile: URL {
        supportDirectory.appendingPathComponent("perf.js")
    }

    private var manifestFile: URL {
        supportDirectory.appendingPathComponent("perf-manifest.json")
    }

    init() {
        let savedAuto = UserDefaults.standard.object(forKey: "perfAutoUpdate") as? Bool
        self.autoUpdate = savedAuto ?? true

        if let manifest = Self.loadManifest(from: Self.supportManifestURL()) {
            self.currentVersion = manifest.version
            self.currentConfig = manifest.config ?? .defaults
            self.latestNotes = manifest.notes
        } else {
            self.currentVersion = Self.bundledVersion
            self.currentConfig = .defaults
        }

        let timestamp = UserDefaults.standard.double(forKey: "perfLastCheck")
        self.lastCheck = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    func bestAvailableScript() -> String {
        if
            let manifest = Self.loadManifest(from: manifestFile),
            let data = try? Data(contentsOf: scriptFile),
            Self.sha256(data) == manifest.sha256.lowercased(),
            let text = String(data: data, encoding: .utf8)
        {
            return text
        }

        if
            let url = Bundle.main.url(forResource: "perf-fallback", withExtension: "js"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        {
            return text
        }

        return "window.ChatGPTPerf = window.ChatGPTPerf || { version: 'missing' };"
    }

    @discardableResult
    func checkForUpdate(force: Bool) async -> Bool {
        guard force || autoUpdate else { return false }

        if !force, let lastCheck, Date().timeIntervalSince(lastCheck) < 60 * 30 {
            return false
        }

        status = "检查远程引擎…"

        do {
            var request = URLRequest(url: Self.cacheBustedManifestURL())
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (manifestData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let manifest = try decoder.decode(RemotePerfManifest.self, from: manifestData)
            currentConfig = manifest.config ?? .defaults
            latestNotes = manifest.notes

            if let minimum = manifest.minimumAppVersion,
               VersionCompare.isNewer(minimum, than: AppConfig.appVersion) {
                status = "远程引擎需要 App \(minimum)+"
                rememberCheck()
                return false
            }

            let needsScript = manifest.version != currentVersion || !fileManager.fileExists(atPath: scriptFile.path)

            guard needsScript else {
                persistManifest(manifest)
                status = "已是最新引擎 \(manifest.version)"
                rememberCheck()
                return false
            }

            var scriptRequest = URLRequest(url: manifest.scriptURL)
            scriptRequest.cachePolicy = .reloadIgnoringLocalCacheData
            scriptRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

            let (scriptData, scriptResponse) = try await URLSession.shared.data(for: scriptRequest)
            guard let scriptHTTP = scriptResponse as? HTTPURLResponse,
                  (200..<300).contains(scriptHTTP.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let actualHash = Self.sha256(scriptData)
            guard actualHash == manifest.sha256.lowercased() else {
                throw NSError(
                    domain: "ChatGPTWeb.RemoteScript",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "远程脚本 SHA-256 校验失败"]
                )
            }

            try fileManager.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )
            try scriptData.write(to: scriptFile, options: .atomic)
            persistManifest(manifest)

            currentVersion = manifest.version
            status = "已下载引擎 \(manifest.version)"
            rememberCheck()
            onInstalledUpdate?()
            return true
        } catch {
            status = "更新失败：\(error.localizedDescription)"
            rememberCheck()
            return false
        }
    }

    func resetToBundled() {
        try? fileManager.removeItem(at: scriptFile)
        try? fileManager.removeItem(at: manifestFile)
        currentVersion = Self.bundledVersion
        currentConfig = .defaults
        latestNotes = nil
        status = "已恢复内置引擎"
        onInstalledUpdate?()
    }

    private func persistManifest(_ manifest: RemotePerfManifest) {
        do {
            try fileManager.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(manifest)
            try data.write(to: manifestFile, options: .atomic)
        } catch {
            status = "保存清单失败：\(error.localizedDescription)"
        }
    }

    private func rememberCheck() {
        let now = Date()
        lastCheck = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "perfLastCheck")
    }

    private static let bundledVersion = "0.1.0"

    private static func supportManifestURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("ChatGPTWeb", isDirectory: true)
            .appendingPathComponent("perf-manifest.json")
    }

    private static func loadManifest(from url: URL) -> RemotePerfManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RemotePerfManifest.self, from: data)
    }

    private static func cacheBustedManifestURL() -> URL {
        var components = URLComponents(url: AppConfig.remoteManifestURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        return components.url!
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
