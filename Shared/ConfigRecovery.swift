import Foundation
import SwiftUI

// Shared by self-signed iOS apps. No credentials are compiled into the IPA.
enum ConfigRecoveryScope: String {
    case optimizer
    case mirror
}

enum ConfigRecoveryError: LocalizedError {
    case invalidPassword, unavailable, notConfigured, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidPassword: return "配置密码不正确，或尝试次数过多。"
        case .unavailable: return "配置服务暂时无法访问，请检查网络。"
        case .notConfigured: return "服务器尚未设置该 App 的配置。"
        case .invalidResponse: return "服务器下发的配置格式不正确。"
        }
    }
}

enum ConfigRecovery {
    static let endpoint = URL(string: "https://config.781751.xyz:58443")!

    static func parse(_ data: Data, scope: ConfigRecoveryScope) throws -> Data {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["schema"] as? Int == 1,
              obj["app"] as? String == scope.rawValue,
              let config = obj["config"] as? [String: Any],
              JSONSerialization.isValidJSONObject(config) else {
            throw ConfigRecoveryError.invalidResponse
        }
        return try JSONSerialization.data(withJSONObject: config)
    }

    static func fetch(_ scope: ConfigRecoveryScope, password: String) async throws -> Data {
        guard password.count >= 16, password.count <= 128 else {
            throw ConfigRecoveryError.invalidPassword
        }
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/config/" + scope.rawValue))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])

        // Native URLSession is intentionally separate from the Optimizer WebKit proxy.
        // The proxy's fail-closed rule continues to apply to ChatGPT traffic.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let response: (Data, URLResponse)
        do { response = try await session.data(for: request) }
        catch { throw ConfigRecoveryError.unavailable }
        guard let http = response.1 as? HTTPURLResponse,
              response.0.count <= 16 * 1024 else { throw ConfigRecoveryError.unavailable }
        switch http.statusCode {
        case 200: return try parse(response.0, scope: scope)
        case 403, 429: throw ConfigRecoveryError.invalidPassword
        case 404: throw ConfigRecoveryError.notConfigured
        default: throw ConfigRecoveryError.unavailable
        }
    }
}

@MainActor
struct ConfigRecoveryView: View {
    let scope: ConfigRecoveryScope
    let importConfig: (Data) -> Bool
    @State private var password = ""
    @State private var busy = false
    @State private var message = ""

    var body: some View {
        Form {
            Section("个人配置中心") {
                Text("config.781751.xyz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("固定配置密码", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                Button("读取并应用配置") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            let config = try await ConfigRecovery.fetch(scope, password: password)
                            if importConfig(config) {
                                message = "配置已恢复。Optimizer 代理变更需完全退出 App 后生效；镜像版请重新选择 PC 标签页。"
                                password = ""
                            } else {
                                message = "服务器配置无效或当前连接未断开，原设置未更改。"
                            }
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }.disabled(busy || password.isEmpty)
                if !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("服务器只返回本 App 所需的配置。没有向服务器上传 ChatGPT 登录 Cookie、对话或草稿。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("快速恢复配置")
    }
}
