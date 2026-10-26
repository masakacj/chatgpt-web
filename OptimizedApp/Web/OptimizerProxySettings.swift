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
    static func load(_ kind: OptimizerProxyMode) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.masakacj.chatgptweb.optimized.proxy",
            kSecAttrAccount as String: kind.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ password: String, kind: OptimizerProxyMode) -> Bool {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.masakacj.chatgptweb.optimized.proxy",
            kSecAttrAccount as String: kind.rawValue
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
}

/// The only owner of proxy selection. Routes are applied before WKWebView load,
/// never automatically by replaying ChatGPT requests.
@MainActor
final class OptimizerProxySettings: ObservableObject {
    private static let key = "optimized.proxy.plan.v1"
    private let defaults: UserDefaults

    @Published private(set) var plan: OptimizerProxyPlan
    @Published private(set) var error: String?
    @Published private(set) var activeBackup = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(OptimizerProxyPlan.self, from: raw) {
            plan = saved
        } else {
            plan = OptimizerProxyPlan()
        }
        // An explicitly tagged simulator fixture keeps old native UI tests isolated
        // from production's fail-closed proxy bootstrap.
        if ProcessInfo.processInfo.arguments.contains("-uitest-proxy-direct") {
            plan.mode = .direct
        }
    }

    func apply(_ candidate: OptimizerProxyPlan, homePassword: String,
               officePassword: String) -> Bool {
        guard candidate.ready else {
            error = "Home 和 Office 必须填写有效的代理主机及端口；不会自动改为直连。"
            return false
        }
        guard OptimizerProxyCredential.save(homePassword, kind: .home),
              OptimizerProxyCredential.save(officePassword, kind: .office) else {
            error = "代理密码未能写入 Keychain。"
            return false
        }
        guard let data = try? JSONEncoder().encode(candidate) else {
            error = "代理配置保存失败。"
            return false
        }
        defaults.set(data, forKey: Self.key)
        plan = candidate
        activeBackup = false
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

    /// Failover is permitted only at initial GET bootstrap before any navigation commits.
    /// It changes the order for the next new WKWebView and never retries a POST.
    func selectBackupForInitialLoad() -> Bool {
        guard plan.mode != .direct, plan.backupEnabled, !activeBackup,
              plan.home.valid, plan.office.valid else { return false }
        activeBackup = true
        return true
    }

    /// No nil proxy when mode expects a configured route: caller must fail closed.
    func configure(_ store: WKWebsiteDataStore) -> Bool {
        guard canLoadWebView else { return false }
        if plan.mode == .direct {
            store.proxyConfigurations = []
            return true
        }
        let routes: [(OptimizerProxyEndpoint, OptimizerProxyMode)]
        let useHomeFirst = (plan.mode == .home) != activeBackup
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
        return true
    }
}
