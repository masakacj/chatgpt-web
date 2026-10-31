import CryptoKit
import Foundation
import Security
import SwiftUI
import UIKit

enum ConfigRecoveryScope: String { case optimizer, mirror }

enum ConfigRecoveryError: LocalizedError {
    case invalidKey, unavailable, missing, conflict, invalidBackup, keychain
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "恢复密钥无效，请使用完整的 43 位恢复密钥。"
        case .unavailable: return "配置服务不可用，请检查网络后重试。"
        case .missing: return "未找到该恢复密钥对应的备份。"
        case .conflict: return "服务器已有更新版本，请先恢复，避免覆盖新配置。"
        case .invalidBackup: return "备份内容错误或密钥不匹配。"
        case .keychain: return "无法将恢复密钥保存在设备 Keychain。"
        }
    }
}

enum ConfigRecovery {
    private static let endpoint = URL(string: "https://ipa.781751.xyz:58443")!
    private static let keychainService = "com.masakacj.config-recovery.v1"

    private struct Envelope: Decodable { let revision: Int; let blob: String }
    private struct Saved: Decodable { let revision: Int }
    private struct Upload: Encodable { let expectedRevision: Int; let blob: String }

    static func generateKey() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard result == errSecSuccess else { return nil }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func secret(_ code: String) throws -> Data {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 43,
              let bytes = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/") + "="), bytes.count == 32 else {
            throw ConfigRecoveryError.invalidKey
        }
        return bytes
    }

    private static func derive(_ label: String, scope: ConfigRecoveryScope, secret: Data) -> Data {
        Data(SHA256.hash(data: Data("config-recovery:v1:\(label):\(scope.rawValue):".utf8) + secret))
    }

    private static func authentication(_ code: String, scope: ConfigRecoveryScope) throws -> String {
        try derive("auth", scope: scope, secret: secret(code)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func symmetricKey(_ code: String, scope: ConfigRecoveryScope) throws -> SymmetricKey {
        try SymmetricKey(data: derive("encrypt", scope: scope, secret: secret(code)))
    }

    private static func request(_ scope: ConfigRecoveryScope, _ code: String, method: String,
                                data: Data? = nil) throws -> URLRequest {
        var result = URLRequest(url: endpoint.appendingPathComponent("config/v1/" + scope.rawValue))
        result.httpMethod = method
        result.timeoutInterval = 12
        result.setValue("Bearer " + (try authentication(code, scope: scope)), forHTTPHeaderField: "Authorization")
        if let data {
            result.httpBody = data
            result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return result
    }

    private static func send(_ req: URLRequest) async throws -> (Data, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let (body, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, body.count <= 24 * 1024 else {
                throw ConfigRecoveryError.unavailable
            }
            return (body, http.statusCode)
        } catch {
            if error is ConfigRecoveryError { throw error }
            throw ConfigRecoveryError.unavailable
        }
    }

    static func encrypt(_ scope: ConfigRecoveryScope, code: String, data: Data) throws -> String {
        let sealed = try AES.GCM.seal(data, using: symmetricKey(code, scope: scope),
                                      authenticating: Data(scope.rawValue.utf8))
        guard let combined = sealed.combined else { throw ConfigRecoveryError.invalidBackup }
        return combined.base64EncodedString()
    }

    static func decrypt(_ scope: ConfigRecoveryScope, code: String, blob: String) throws -> Data {
        guard let combined = Data(base64Encoded: blob),
              let sealed = try? AES.GCM.SealedBox(combined: combined),
              let result = try? AES.GCM.open(sealed, using: symmetricKey(code, scope: scope),
                                             authenticating: Data(scope.rawValue.utf8)) else {
            throw ConfigRecoveryError.invalidBackup
        }
        return result
    }

    static func download(_ scope: ConfigRecoveryScope, code: String) async throws -> (data: Data, revision: Int) {
        let (body, status) = try await send(request(scope, code, method: "GET"))
        guard status != 404 else { throw ConfigRecoveryError.missing }
        guard status == 200, let record = try? JSONDecoder().decode(Envelope.self, from: body) else {
            throw ConfigRecoveryError.unavailable
        }
        return (try decrypt(scope, code: code, blob: record.blob), record.revision)
    }

    static func upload(_ scope: ConfigRecoveryScope, code: String, data: Data,
                       expectedRevision: Int) async throws -> Int {
        guard data.count <= 10 * 1024, expectedRevision >= 0 else {
            throw ConfigRecoveryError.invalidBackup
        }
        let blob = try encrypt(scope, code: code, data: data)
        let body = try JSONEncoder().encode(Upload(expectedRevision: expectedRevision, blob: blob))
        let (response, status) = try await send(request(scope, code, method: "PUT", data: body))
        if status == 409 { throw ConfigRecoveryError.conflict }
        guard status == 200, let saved = try? JSONDecoder().decode(Saved.self, from: response),
              saved.revision == expectedRevision + 1 else {
            throw ConfigRecoveryError.unavailable
        }
        return saved.revision
    }

    private static func keyQuery(_ scope: ConfigRecoveryScope) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: scope.rawValue]
    }

    static func savedKey(_ scope: ConfigRecoveryScope) -> String? {
        var query = keyQuery(scope)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var data: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &data) == errSecSuccess,
              let content = data as? Data else { return nil }
        return String(data: content, encoding: .utf8)
    }

    static func remember(_ code: String, scope: ConfigRecoveryScope, revision: Int) throws {
        _ = try secret(code)
        var query = keyQuery(scope)
        let fields: [String: Any] = [kSecValueData as String: Data(code.utf8)]
        let result = SecItemUpdate(query as CFDictionary, fields as CFDictionary)
        if result == errSecItemNotFound {
            query.merge(fields) { _, value in value }
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw ConfigRecoveryError.keychain }
        } else if result != errSecSuccess { throw ConfigRecoveryError.keychain }
        UserDefaults.standard.set(revision, forKey: revisionKey(scope, code: code))
    }

    private static func revisionKey(_ scope: ConfigRecoveryScope, code: String) -> String {
        let auth = (try? authentication(code, scope: scope)) ?? ""
        return "configRecovery.v1." + scope.rawValue + "." + String(auth.prefix(16))
    }

    static func uploadSaved(_ scope: ConfigRecoveryScope, data: Data) async {
        guard let code = savedKey(scope) else { return }
        let rev = UserDefaults.standard.integer(forKey: revisionKey(scope, code: code))
        guard rev > 0 else { return }
        if let next = try? await upload(scope, code: code, data: data, expectedRevision: rev) {
            UserDefaults.standard.set(next, forKey: revisionKey(scope, code: code))
        }
    }

    static func revision(_ scope: ConfigRecoveryScope, code: String) -> Int {
        UserDefaults.standard.integer(forKey: revisionKey(scope, code: code))
    }
}

@MainActor
struct ConfigRecoveryView: View {
    let scope: ConfigRecoveryScope
    let exportConfig: () -> Data?
    let importConfig: (Data) -> Bool

    @State private var code = ""
    @State private var busy = false
    @State private var status = ""

    var body: some View {
        Form {
            Section("固定恢复密钥") {
                SecureField("43 位恢复密钥", text: $code)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Button("生成密钥") {
                        code = ConfigRecovery.generateKey() ?? ""
                        status = "请立即复制并保存密钥。换 Team ID 后需要重新输入。"
                    }
                    Button("复制密钥") { UIPasteboard.general.string = code }
                        .disabled(code.isEmpty)
                }
                Text("密钥不会上传；服务端只保存端到端加密的配置。请将密钥存入密码管理器，切勿放进 IPA 或代码仓库。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("配置恢复") {
                Button("从服务器恢复") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            let result = try await ConfigRecovery.download(scope, code: code)
                            guard importConfig(result.data) else {
                                status = "备份中的配置无效，当前设置保持不变。"
                                return
                            }
                            try ConfigRecovery.remember(code, scope: scope, revision: result.revision)
                            status = "配置已恢复。代理变更需完全退出 App 后生效；PC 连接请重新选择标签页。"
                        } catch { status = error.localizedDescription }
                    }
                }.disabled(busy)
                Button("将当前配置加密备份到服务器") {
                    guard let data = exportConfig() else {
                        status = "当前配置不完整，请先保存并验证代理或 PC 配对。"
                        return
                    }
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            let revision = try await ConfigRecovery.upload(
                                scope, code: code, data: data,
                                expectedRevision: ConfigRecovery.revision(scope, code: code))
                            try ConfigRecovery.remember(code, scope: scope, revision: revision)
                            status = "已备份。后续配置变化会自动同步，请保管好恢复密钥。"
                        } catch { status = error.localizedDescription }
                    }
                }.disabled(busy)
                if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                Text("只备份你自建服务的参数，不同步 ChatGPT 登录 Cookie、网页缓存和对话内容。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("配置备份与恢复")
        .onAppear { code = ConfigRecovery.savedKey(scope) ?? "" }
    }
}
