import Combine
import Foundation
import Network
import Security
import WebKit

/// WKWebsiteDataStore-only proxy routing. Never touches system VPN, URLSession or Mirror.
enum OptimizerProxyMode: String, Codable, CaseIterable {
    case home, office, direct
}

struct OptimizerProxyEndpoint: Codable, Equatable {
    var host: String = ""
    var port: Int = 0
    var username: String = ""

    var valid: Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == host, host.count >= 3, host.count <= 253,
              port >= 1 && port <= 65535, !host.contains("://"),
              !host.contains("/"), !host.contains("@"), !host.contains(" "),
              !host.contains(":"), !host.hasPrefix("."), !host.hasSuffix("."),
              username.count <= 128, !username.contains("\n") else { return false }
        return host.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0)
        }
    }
}

struct OptimizerProxyPlan: Equatable {
    var mode: OptimizerProxyMode = .home
    var home = OptimizerProxyEndpoint()
    var office = OptimizerProxyEndpoint()
    var backupEnabled = true
    var denyDirect = true

    var selected: [OptimizerProxyEndpoint] {
        switch mode {
        case .direct: return []
        case .home: return backupEnabled ? [home, office] : [home]
        case .office: return backupEnabled ? [office, home] : [office]
        }
    }

    var ready: Bool {
        // Explicit direct is user-selected, never a fallback for broken proxy configuration.
        mode == .direct || (denyDirect && selected.allSatisfy(\.valid))
    }

    var description: String {
        switch mode {
        case .direct: return "手动直连（不经过代理）"
        case .home: return backupEnabled ? "Home → Office（禁止直连）" : "Home（禁止直连）"
        case .office: return backupEnabled ? "Office → Home（禁止直连）" : "Office（禁止直连）"
        }
    }
}

enum OptimizerProxyCredential {
    static func load(_ kind: OptimizerProxyMode, pending: Bool = false) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.masakacj.chatgptweb.optimized.proxy",
            kSecAttrAccount as String: pending ? "pending-\(kind.rawValue)" : kind.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ password: String, kind: OptimizerProxyMode,
                     pending: Bool = false) -> Bool {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.masakacj.chatgptweb.optimized.proxy",
            kSecAttrAccount as String: pending ? "pending-\(kind.rawValue)" : kind.rawValue
        ]
        guard !password.isEmpty else { return true } // blank means retain existing credential
        let data = Data(password.utf8)
        let result = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var insert = key
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    /// Called only during native startup, before constructing any WKWebView.
    static func commitPending() -> Bool {
        for kind in [OptimizerProxyMode.home, .office] {
            guard let staged = load(kind, pending: true), !staged.isEmpty else { continue }
            guard save(staged, kind: kind) else { return false }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.masakacj.chatgptweb.optimized.proxy",
                kSecAttrAccount as String: "pending-\(kind.rawValue)"
            ]
            SecItemDelete(query as CFDictionary)
        }
        return true
    }
}

/// The only owner of proxy selection. Routes are applied before WKWebView load,
/// never automatically by replaying ChatGPT requests.
@MainActor
final class OptimizerProxySettings: ObservableObject {
    private static let key = "optimized.proxy.plan.v1"
    private static let pendingCredentialsKey = "optimized.proxy.pending.credentials.v1"
    // @MainActor process-wide guard: WindowGroup can create multiple scenes.
    // Do not promote staged credentials or reconfigure the shared default
    // WebKit data store from a second settings owner in the same process.
    private static var didAttemptStartupPromotion = false
    private static var configuredThisProcess = false
    private static var processPlan: OptimizerProxyPlan?
    private let defaults: UserDefaults
    private var locallyConfigured = false

    private var routeLockedForProcess: Bool {
        get { defaults === UserDefaults.standard ? Self.configuredThisProcess : locallyConfigured }
        set {
            if defaults === UserDefaults.standard { Self.configuredThisProcess = newValue }
            else { locallyConfigured = newValue }
        }
    }

    @Published private(set) var plan: OptimizerProxyPlan
    @Published private(set) var error: String?
    @Published private(set) var pendingRestart = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let production = defaults === UserDefaults.standard
        if !production || !Self.didAttemptStartupPromotion {
            if defaults.bool(forKey: Self.pendingCredentialsKey),
               OptimizerProxyCredential.commitPending() {
                defaults.set(false, forKey: Self.pendingCredentialsKey)
            }
            if production { Self.didAttemptStartupPromotion = true }
        }
        let stored = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(OptimizerProxyPlan.self, from: $0) }
            ?? OptimizerProxyPlan()
        plan = production ? (Self.processPlan ?? stored) : stored
        // An explicitly tagged simulator fixture keeps old native UI tests isolated
        // from production's fail-closed proxy bootstrap.
        if ProcessInfo.processInfo.arguments.contains("-uitest-proxy-direct") {
            plan.mode = .direct
        }
        if production && Self.processPlan == nil { Self.processPlan = plan }
    }

    func apply(_ candidate: OptimizerProxyPlan, homePassword: String,
               officePassword: String) -> Bool {
        guard candidate.ready else {
            error = "Home 和 Office 必须填写有效的代理主机及端口；不会自动改为直连。"
            return false
        }
        // Never overwrite active credentials in a process whose WebKit store
        // has already been configured. Staged Keychain entries are promoted
        // only on the next app startup, before any WKWebView is constructed.
        let pending = routeLockedForProcess
        guard OptimizerProxyCredential.save(homePassword, kind: .home, pending: pending),
              OptimizerProxyCredential.save(officePassword, kind: .office, pending: pending) else {
            error = "代理密码未能写入 Keychain。"
            return false
        }
        if candidate.mode != .direct {
            let profiles: [(OptimizerProxyEndpoint, OptimizerProxyMode)] =
                candidate.mode == .home ? [(candidate.home, .home), (candidate.office, .office)] :
                                          [(candidate.office, .office), (candidate.home, .home)]
            for (index, item) in profiles.enumerated() where index == 0 || candidate.backupEnabled {
                if !item.0.username.isEmpty &&
                    (OptimizerProxyCredential.load(item.1, pending: pending)?.isEmpty != false) &&
                    (OptimizerProxyCredential.load(item.1)?.isEmpty != false) {
                    error = "已填写代理用户名，但缺少 Keychain 密码。"
                    return false
                }
            }
        }
        guard let data = try? JSONEncoder().encode(candidate) else {
            error = "代理配置保存失败。"
            return false
        }
        defaults.set(data, forKey: Self.key)
        if pending && (!homePassword.isEmpty || !officePassword.isEmpty) {
            defaults.set(true, forKey: Self.pendingCredentialsKey)
        }
        if routeLockedForProcess {
            // Same-process WKWebsiteDataStore.default() is shared even after
            // temporary safe-mode views. Do not replace active route until relaunch.
            pendingRestart = true
        } else {
            plan = candidate
            if defaults === UserDefaults.standard { Self.processPlan = candidate }
        }
        error = nil
        return true
    }

    var canLoadWebView: Bool {
        guard plan.ready else { return false }
        if plan.mode == .direct { return true }
        for (route, kind) in [(plan.home, OptimizerProxyMode.home),
                              (plan.office, OptimizerProxyMode.office)] {
            let needed = (kind == plan.mode) || plan.backupEnabled
            if needed && !route.username.isEmpty &&
                (OptimizerProxyCredential.load(kind)?.isEmpty != false) { return false }
        }
        return true
    }

    /// No nil proxy when mode expects a configured route: caller must fail closed.
    func configure(_ store: WKWebsiteDataStore) -> Bool {
        guard canLoadWebView else { return false }
        // An existing store may still be in use by a retired WKWebView.
        if routeLockedForProcess { return true }
        if plan.mode == .direct {
            store.proxyConfigurations = []
            routeLockedForProcess = true
            return true
        }
        let routes: [(OptimizerProxyEndpoint, OptimizerProxyMode)]
        let useHomeFirst = plan.mode == .home
        if useHomeFirst {
            routes = plan.backupEnabled ? [(plan.home, .home), (plan.office, .office)] :
                [(plan.home, .home)]
        } else {
            routes = plan.backupEnabled ? [(plan.office, .office), (plan.home, .home)] :
                [(plan.office, .office)]
        }
        var configs: [ProxyConfiguration] = []
        for (route, kind) in routes {
            guard route.valid, let port = NWEndpoint.Port(rawValue: UInt16(route.port)) else {
                return false
            }
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(route.host), port: port)
            // TLS to the CONNECT server: no cleartext credential or ChatGPT traffic
            // over an unauthenticated public hop.
            var config = ProxyConfiguration(httpCONNECTProxy: endpoint,
                                            tlsOptions: NWProtocolTLS.Options())
            config.allowFailover = false // never fail over to a non-proxy connection
            if !route.username.isEmpty {
                guard let password = OptimizerProxyCredential.load(kind), !password.isEmpty else {
                    return false
                }
                config.applyCredential(username: route.username, password: password)
            }
            configs.append(config)
        }
        guard !configs.isEmpty else { return false }
        store.proxyConfigurations = configs
        routeLockedForProcess = true
        return true
    }
}
