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
                Section("快速配置") {
                    NavigationLink("从 config.781751.xyz 恢复代理") {
                        ConfigRecoveryView(scope: .optimizer,
                                           importConfig: { settings.importRecoveryConfig($0) })
                    }
                    Text("换 Team ID 后输入固定密码，恢复 Home / Office 的全部代理参数。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("应用") {
                    Text(draft.description)
                        .font(.subheadline)
                    if settings.pendingRestart {
                        Text("配置已保存。请彻底退出并重新打开 App 应用新线路。")
                            .foregroundStyle(.orange).font(.footnote)
                    }
                    if let error = settings.error {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                    if !canReload {
                        Text("当前对话仍在执行或等待工具授权，暂不允许切换代理。")
                            .foregroundStyle(.orange).font(.footnote)
                    }
                    Button("保存配置（重启 App 后生效）") {
                        showApplyConfirmation = true
                    }
                    .disabled(!draft.ready || !canReload)
                    .accessibilityIdentifier("proxy.apply.button")
                    Text("设置将在下次完全退出并重新打开 App 时应用；首次尚未加载网页的安装可直接开始。避免在旧 WebView 连接仍存活时修改共享 WebKit 数据存储。")
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
            .confirmationDialog("保存新的网络代理配置？",
                                isPresented: $showApplyConfirmation,
                                titleVisibility: .visible) {
                Button("保存（不重发消息）") {
                    if settings.apply(draft, homePassword: homePassword,
                                      officePassword: officePassword) {
                        onApplied()
                    }
                }
            } message: {
                Text("当前网页不会热重建；请在完成当前任务后完全退出并重新打开 Optimizer，新配置才会生效。")
            }
        }
    }
}
