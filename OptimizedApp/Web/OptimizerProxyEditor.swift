import SwiftUI

/// An independent App-only proxy editor. Secrets are written to Optimizer Keychain,
/// never UserDefaults, Cloudflare telemetry or an URL.
struct OptimizerProxyEditor: View {
    @ObservedObject var settings: OptimizerProxySettings
    let canReload: Bool
    let onApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = OptimizerProxyPlan()
    @State private var homePassword = ""
    @State private var officePassword = ""
    @State private var showApplyConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("仅 Optimizer 生效") {
                    Picker("当前代理", selection: $draft.mode) {
                        Text("Home 家宽").tag(OptimizerProxyMode.home)
                        Text("Office GOST").tag(OptimizerProxyMode.office)
                        Text("手动直连").tag(OptimizerProxyMode.direct)
                    }
                    Toggle("备用代理线路", isOn: $draft.backupEnabled)
                        .disabled(draft.mode == .direct)
                    HStack {
                        Text("禁止自动直连")
                        Spacer()
                        Image(systemName: draft.mode == .direct ? "minus.circle" : "checkmark.shield.fill")
                            .foregroundStyle(.secondary)
                    }
                    Text("代理故障时绝不静默改用手机直连。手动直连须明确选择；不自动重放任何聊天、上传或工具请求。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Home 家宽 · HTTPS CONNECT") {
                    TextField("代理域名或 IP", text: $draft.home.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("端口", value: $draft.home.port, format: .number)
                        .keyboardType(.numberPad)
                    TextField("用户名（可选）", text: $draft.home.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("代理密码（留空保留已保存密码）", text: $homePassword)
                    Text("必须是有受信任 TLS 证书的 CONNECT 入口。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Office · HTTPS CONNECT（备用）") {
                    TextField("代理域名或 IP", text: $draft.office.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("端口", value: $draft.office.port, format: .number)
                        .keyboardType(.numberPad)
                    TextField("用户名（可选）", text: $draft.office.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("代理密码（留空保留已保存密码）", text: $officePassword)
                }
                Section("应用") {
                    Text(draft.description)
                        .font(.subheadline)
                    if let error = settings.error {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                    if !canReload {
                        Text("当前对话仍在执行或等待工具授权，暂不允许切换代理。")
                            .foregroundStyle(.orange).font(.footnote)
                    }
                    Button("保存并重新连接网页") {
                        showApplyConfirmation = true
                    }
                    .disabled(!draft.ready || !canReload)
                    .accessibilityIdentifier("proxy.apply.button")
                    Text("保存会复用现有 Optimizer 登录态，在新的 WKWebView 导航前应用代理。不清空 Cookie；目前端点未由系统自动填入。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Optimizer 网络代理")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear { draft = settings.plan }
            .confirmationDialog("应用新的网络代理？",
                                isPresented: $showApplyConfirmation,
                                titleVisibility: .visible) {
                Button("重新连接（不重发消息）") {
                    if settings.apply(draft, homePassword: homePassword,
                                      officePassword: officePassword) {
                        onApplied()
                    }
                }
            } message: {
                Text("旧 WebView 将被销毁并新建。请确认没有未完成的上传、发送或工具确认操作。")
            }
        }
    }
}
