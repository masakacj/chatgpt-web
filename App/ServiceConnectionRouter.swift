import Foundation

/// Two HTTPS transports, one logical paired PC Bridge. This router never owns
/// pairing keys, draft owners or command IDs and never retries a write.
@MainActor
final class STServiceConnectionRouter {
    enum Lane: String { case direct, cloudflare, home }

    private(set) var lane: Lane = .direct
    private(set) var notice: String?
    private(set) var authenticatedServerId: String?
    private(set) var homeVerified = false
    private var fallbackVerified = false
    private var fallback: URL?
    private var home: URL?
    private var context = ""
    private var nextHomeProbe = Date.distantPast
    private var probeInProgress = false

    static let recoveryDelay: TimeInterval = 45

    var label: String {
        switch lane {
        case .home: return "Home HTTPS · 主线路"
        case .cloudflare: return "Cloudflare 443 · 备用线路"
        case .direct: return "HTTPS · 单线路"
        }
    }
    var cloudflareOrigin: URL? { fallback }
    var candidateHomeOrigin: URL? { home }

    /// Only the historical CF443 origin (or an isolated UI fixture) can gain a
    /// Home alternate. Arbitrary custom endpoints remain single-route.
    func configure(logicalOrigin: URL, transportOrigin: URL, identity: String,
                   homeInput: String, homeEnabled: Bool, fixture: Bool = false) {
        let token = identity + "|" + logicalOrigin.absoluteString + "|" +
                    homeInput + "|" + String(homeEnabled)
        guard token != context else { return }
        context = token
        lane = .direct; fallback = nil; home = nil
        authenticatedServerId = nil; fallbackVerified = false; homeVerified = false
        notice = nil; nextHomeProbe = .distantPast; probeInProgress = false

        let official = transportOrigin.absoluteString == PCCompanionPolicy.defaultEndpoint
        let simulated = fixture && transportOrigin.host == "shared-tab.invalid"
        guard official || simulated else {
            notice = "自定义连接不自动切换到其他服务器"
            fallback = transportOrigin
            return
        }
        fallback = transportOrigin
        lane = .cloudflare
        guard homeEnabled else {
            notice = "Home 主线路未启用，使用 Cloudflare 443"
            return
        }
        do {
            let candidate = try PCCompanionPolicy.origin(homeInput)
            guard candidate != transportOrigin else {
                notice = "Home 和备用地址相同，已保持单线路"
                return
            }
            home = candidate
            notice = "Home 尚未通过同一 Bridge 身份验证，暂用 Cloudflare"
        } catch {
            notice = "Home 地址无效，暂用 Cloudflare"
        }
    }

    /// A serverId is accepted only from an authenticated, successful CF health
    /// response. An untrusted Home self-assertion alone cannot establish trust.
    func attestCloudflare(_ serverId: String?) {
        guard fallback != nil else { return }
        // Each resume must establish a fresh authenticated CF anchor before
        // any previous Home verification can carry a new request.
        homeVerified = false
        if home != nil { lane = .cloudflare }
        guard let serverId, Self.isValidServerId(serverId) else {
            authenticatedServerId = nil; fallbackVerified = false; homeVerified = false
            if home != nil { notice = "Bridge 未提供已认证 serverId，Home 自动切换已禁用" }
            return
        }
        authenticatedServerId = serverId
        fallbackVerified = true
    }

    /// This must be called only with the authenticated health response from
    /// the user-explicitly-trusted HTTPS Home endpoint.
    @discardableResult
    func attestHome(_ serverId: String?) -> Bool {
        guard home != nil, fallbackVerified, let expected = authenticatedServerId,
              serverId == expected else {
            homeVerified = false
            if home != nil { notice = "Home 与 Cloudflare 的 Bridge 身份不一致，拒绝切换" }
            return false
        }
        homeVerified = true
        lane = .home
        notice = nil
        return true
    }

    func reportHomeHealthError(_ error: Error) {
        guard home != nil else { return }
        homeVerified = false
        lane = .cloudflare
        if let code = (error as? STError)?.status, code == 401 || code == 403 {
            notice = "Home 配对认证失败，已保留 Cloudflare 连接"
        } else {
            notice = "Home 暂不可达，已保留 Cloudflare 连接"
        }
    }

    static func isValidServerId(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{16,128}$", options: .regularExpression) != nil
    }

    private var activeOrigin: URL {
        if lane == .home, homeVerified, let home { return home }
        return fallback ?? URL(string: PCCompanionPolicy.defaultEndpoint)!
    }

    /// After Home failure, recovery requires a fresh authenticated health GET,
    /// with an enforced cooldown. It never replays the failed GET indefinitely.
    private func restoreHomeIfReady(probe: (URL) async throws -> String?) async {
        guard lane == .cloudflare, homeVerified, let home,
              Date() >= nextHomeProbe, !probeInProgress else { return }
        probeInProgress = true
        nextHomeProbe = Date().addingTimeInterval(Self.recoveryDelay)
        defer { probeInProgress = false }
        let generation = context
        do {
            let id = try await probe(home)
            guard context == generation else { return }
            if id == authenticatedServerId && fallbackVerified {
                lane = .home
                notice = nil
            } else {
                homeVerified = false
                notice = "Home 身份已变化，禁止自动恢复"
            }
        } catch {
            if context == generation { notice = "Home 恢复检测未通过，继续使用 Cloudflare" }
        }
    }

    /// Exactly one alternate GET attempt. POST/DELETE and any other method
    /// return their first outcome, even on timeout/502/connection loss.
    func perform<T>(method: String, retryable: (Error) -> Bool,
                    probe: (URL) async throws -> String?,
                    operation: (URL) async throws -> T) async throws -> T {
        if method == "GET" { await restoreHomeIfReady(probe: probe) }
        let first = activeOrigin, generation = context
        do {
            return try await operation(first)
        } catch {
            guard generation == context, method == "GET", retryable(error), lane == .home,
                  fallbackVerified, let fallback, homeVerified else { throw error }
            lane = .cloudflare
            nextHomeProbe = Date().addingTimeInterval(Self.recoveryDelay)
            notice = "Home 读取失败，已切换 Cloudflare；写操作不会重试"
            // The backup was previously authenticated as this same serverId.
            return try await operation(fallback)
        }
    }
}
