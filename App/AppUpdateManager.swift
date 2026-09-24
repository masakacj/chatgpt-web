import Foundation

@MainActor
final class AppUpdateManager: ObservableObject {
    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseURL: URL?
    @Published private(set) var updateAvailable = false
    @Published private(set) var status = "未检查"
    @Published private(set) var lastCheck: Date?

    func checkIfNeeded() async {
        if let last = lastCheck ?? savedLastCheck,
           Date().timeIntervalSince(last) < 60 * 60 * 12 {
            return
        }
        await check(force: false)
    }

    func check(force: Bool = true) async {
        if !force, let last = savedLastCheck,
           Date().timeIntervalSince(last) < 60 * 60 * 12 {
            lastCheck = last
            return
        }

        status = "检查 App Release…"

        do {
            let url = URL(string: "https://api.github.com/repos/\(AppConfig.repository)/releases/latest")!
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("ChatGPTWeb/\(AppConfig.appVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            releaseURL = release.htmlURL
            updateAvailable = VersionCompare.isNewer(latestVersion ?? "0", than: AppConfig.appVersion)
            status = updateAvailable
                ? "发现 App \(latestVersion ?? release.tagName)"
                : "App 已是最新版本"

            let now = Date()
            lastCheck = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "appLastCheck")
        } catch {
            status = "检查失败：\(error.localizedDescription)"
        }
    }

    private var savedLastCheck: Date? {
        let value = UserDefaults.standard.double(forKey: "appLastCheck")
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }
}
