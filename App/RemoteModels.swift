import Foundation

struct RemotePerfConfig: Codable, Equatable {
    var balancedThreshold: Int
    var aggressiveThreshold: Int
    var extremeThreshold: Int
    var coldViewportDistance: Double
    var extremeViewportDistance: Double
    var unloadMedia: Bool
    var packExtreme: Bool
    var disableAnimations: Bool
    var disableBackdropFilters: Bool

    static let defaults = RemotePerfConfig(
        balancedThreshold: 28,
        aggressiveThreshold: 70,
        extremeThreshold: 140,
        coldViewportDistance: 6,
        extremeViewportDistance: 12,
        unloadMedia: true,
        packExtreme: false,
        disableAnimations: true,
        disableBackdropFilters: true
    )
}

struct RemotePerfManifest: Codable {
    let version: String
    let scriptURL: URL
    let sha256: String
    let minimumAppVersion: String?
    let notes: String?
    let config: RemotePerfConfig?
}

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let body: String?
    let prerelease: Bool
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body
        case prerelease
        case draft
    }
}

enum VersionCompare {
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let a = components(lhs)
        let b = components(rhs)
        let count = max(a.count, b.count)

        for i in 0..<count {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av > bv }
        }
        return false
    }

    private static func components(_ value: String) -> [Int] {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .first?
            .split(separator: ".")
            .map { Int($0) ?? 0 } ?? []
    }
}
