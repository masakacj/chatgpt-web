import SwiftUI
import Combine
import UIKit

@main
struct ChatGPTWebOptimizedApp: App {
    var body: some Scene {
        WindowGroup {
            OptimizedRootView()
        }
    }
}

struct OptimizedRootView: View {
    @StateObject private var supervisor: NativeOptimizationSupervisor
    @StateObject private var model: OptimizedAppModel
    @StateObject private var owner: ConversationManagerOwner
    @StateObject private var telemetry: OptimizedTelemetry
    @StateObject private var resourceGate = NativeResourceGate()
    @StateObject private var liveDebug = OptimizedLiveDebug()
    @StateObject private var proxySettings = OptimizerProxySettings()
    @State private var showingProxySettings = false
    @State private var thermalStateDescription = Self.formatThermalState(ProcessInfo.processInfo.thermalState)
    @AppStorage("optimized.pcHistory.enabled.v1") private var pcHistoryEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init(supervisor: NativeOptimizationSupervisor? = nil,
         model: OptimizedAppModel? = nil,
         owner: ConversationManagerOwner? = nil,
         telemetry: OptimizedTelemetry? = nil) {
        let supervisor = supervisor ?? NativeOptimizationSupervisor()
        let model = model ?? OptimizedAppModel()
        let owner = owner ?? ConversationManagerOwner()
        let telemetry = telemetry ?? OptimizedTelemetry()
        _supervisor = StateObject(wrappedValue: supervisor)
        model.supervisor = supervisor
        if supervisor.isSafeModeActive || supervisor.isCircuitOpen {
            model.processTerminated = true
        }
        _model = StateObject(wrappedValue: model)
        _owner = StateObject(wrappedValue: owner)
        _telemetry = StateObject(wrappedValue: telemetry)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 32)
                }
                .disabled(!model.canGoBack)
                .accessibilityLabel("返回上一页")
                .accessibilityIdentifier("navigation.back.button")
                Button {
                    model.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 32)
                }
                .disabled(!model.canGoForward)
                .accessibilityLabel("前进下一页")
                .accessibilityIdentifier("navigation.forward.button")
                Text("ChatGPT")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingProxySettings = true
                } label: {
                    Image(systemName: "network")
                        .frame(width: 36, height: 32)
                }
                .accessibilityLabel("代理设置")
                .accessibilityIdentifier("navigation.proxy.button")
                Button {
                    model.diagnosticsEnabled = true
                } label: {
                    Image(systemName: "stethoscope")
                        .frame(width: 36, height: 32)
                }
                .accessibilityLabel("诊断")
                .accessibilityIdentifier("navigation.diagnostics.button")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.regularMaterial)

            if model.processTerminated || supervisor.isSafeModeActive {
                NativeSafeModeView(
                    model: model,
                    owner: owner,
                    telemetry: telemetry,
                    supervisor: supervisor
                )
                .transition(.opacity)
            } else if !proxySettings.canLoadWebView {
                VStack(spacing: 16) {
                    Image(systemName: "network")
                        .font(.system(size: 38))
                    Text("请配置 Home / Office 代理")
                        .font(.headline)
                    Text("已启用禁止自动直连。没有已配置的代理时不会加载 ChatGPT。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("设置代理") { showingProxySettings = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("proxy.configure.button")
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OptimizedWebView(model: model, owner: owner, telemetry: telemetry,
                                 supervisor: supervisor, resourceGate: resourceGate,
                                 liveDebug: liveDebug,
                                 pcHistoryEnabled: pcHistoryEnabled,
                                 proxySettings: proxySettings)
                    .id(model.webViewGeneration)
            }
        }
        .sheet(isPresented: $showingProxySettings) {
            OptimizerProxyEditor(settings: proxySettings,
                                 canReload: owner.projection.task != .running && owner.projection.task != .waiting) {
                // Do not mutate the shared WKWebsiteDataStore while an old WebView
                // might still own an in-flight connection. Next app start applies it.
                showingProxySettings = false
                if let backup = proxySettings.exportRecoveryConfig() {
                    Task { await ConfigRecovery.uploadSaved(.optimizer, data: backup) }
                }
            }
        }
        .sheet(isPresented: $model.diagnosticsEnabled) {
            NavigationStack {
                List {
                    Section("会话管理") {
                        LabeledContent("任务状态", value: owner.projection.task.rawValue == "unknown" ? "尚未检测到任务状态" : owner.projection.task.rawValue)
                        LabeledContent("修订版本", value: String(owner.projection.revision))
                        LabeledContent("网页状态", value: model.status)
                        LabeledContent("网页恢复次数", value: String(model.recoveryAttempts))
                    }

                    Section("原生安全监控 · Supervisor") {
                        LabeledContent("安全模式", value: (supervisor.isSafeModeActive || model.processTerminated) ? "已激活" : "正常")
                        LabeledContent("熔断状态", value: supervisor.isCircuitOpen ? "熔断开启 (Fail-Closed)" : "正常")
                        LabeledContent("近期终止次数", value: "\(supervisor.verifiedTerminationCount)")
                        if let reason = supervisor.lastFailureReason {
                            LabeledContent("最近状态", value: reason)
                        }
                    }

                    Section("PC Chrome 长对话优化") {
                        Toggle("历史内容布局减负（下次重建网页生效）", isOn: $pcHistoryEnabled)
                        Text("与 PC 扩展保持相同的低干预方向：长对话至少 24 个消息块才启用，只对较早历史应用 WebKit 布局减负；最新 12 条消息及正在运行、等待授权的内容保持原样。不裁剪 DOM 或拦截 MCP。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Section("独立网络代理") {
                        LabeledContent("当前线路", value: proxySettings.plan.description)
                        LabeledContent("代理配置", value: proxySettings.pendingRestart ? "已保存，需重新打开 App 生效" : (proxySettings.canLoadWebView ? "就绪" : "尚未配置或缺少代理凭据"))
                        Button("修改代理设置") {
                            model.diagnosticsEnabled = false
                            showingProxySettings = true
                        }
                        Text("仅作用于 Optimizer 的 WebKit 页面；禁止代理失效时静默直连，切换线路必须由用户确认。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Section("资源加载策略") {
                        Toggle("第三方统计资源过滤（下次重建网页生效）", isOn: $resourceGate.isEnabled)
                        LabeledContent("可用规则", value: String(NativeResourceGate.approvedRuleCount))
                        LabeledContent("本次已安装", value: String(resourceGate.appliedRuleCount))
                        Text("只屏蔽 ChatGPT 页面中的指定第三方统计请求，不拦截消息、登录、图片、附件、MCP 或授权流程；实际节能幅度仍需真机对照。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("系统热状态 · 原生") {
                        LabeledContent("当前热状态", value: thermalStateDescription)
                        Text("基于 iOS 原生 ProcessInfo.thermalState 事件驱动通知；仅表示系统热调节等级（正常/温热/较热/严重过热），不代表芯片实际摄氏度。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("实时性能调试（独立于 D1）") {
                        Toggle("允许远程只读性能采样", isOn: $liveDebug.isEnabled)
                        LabeledContent("在线状态", value: liveDebug.state)
                        LabeledContent("调试会话", value: liveDebug.room)
                        LabeledContent("最近采样", value: liveDebug.lastProbe)
                        Button("复制调试配对码") {
                            UIPasteboard.general.string = liveDebug.pairingCode
                        }
                        Text("配对码包含访问密钥，请只交给可信的测试端；远端只能读取指标和请求固定快照，无法发送消息或执行任意脚本。关闭后停止响应请求。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Section("故障演练与测试") {
                        Button("模拟 WebContent 进程终止 (SIMULATED)") {
                            model.diagnosticsEnabled = false
                            owner.invalidateDocument(processTerminated: true)
                            model.simulateProcessTermination()
                        }
                        .accessibilityIdentifier("diagnostics.simulate.termination")
                        .foregroundStyle(.orange)

                        Text("此操作仅用于演练 Native Supervisor 与安全模式界面，属于模拟测试，不调用私有 WebKit 终止 API，不发送网络请求。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("远程诊断 · Cloudflare") {
                        Toggle("自动采集诊断事件", isOn: $telemetry.isEnabled)
                        LabeledContent("上传状态", value: telemetry.state)
                        LabeledContent("待上传", value: String(telemetry.pendingCount))
                        LabeledContent("最近事件", value: telemetry.lastEvent)
                        if let last = telemetry.lastSuccess {
                            LabeledContent("最近成功", value: last.formatted(date: .abbreviated,
                                                                            time: .standard))
                        }
                        LabeledContent("会话编号", value: telemetry.sessionId)
                        Button("立即发送待上传事件") { telemetry.flush(force: true) }
                            .disabled(!telemetry.isEnabled || telemetry.pendingCount == 0)
                        ShareLink("分享本地诊断摘要", item: supervisor.exportReport(telemetryReport: telemetry.localReport))
                        Text("只记录错误码、网页类型、终止与恢复事件；不读取聊天正文、URL、Cookie 或 Token。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("诊断")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { model.diagnosticsEnabled = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("重试当前对话？", isPresented: Binding(
            get: { owner.recoveryCandidate != nil },
            set: { if !$0 { owner.dismissRecoveryCandidate() } }
        )) {
            Button("取消", role: .cancel) { owner.dismissRecoveryCandidate() }
            Button("重试") {
                guard let candidate = owner.recoveryCandidate else { return }
                Task {
                    if await owner.authorizeManualRetry() {
                        _ = await model.retry(document: candidate.documentId, sequence: candidate.sequence)
                    }
                }
            }
        } message: {
            Text("仅点击当前官方加载错误面板的重试按钮一次。不会重放请求或自动刷新整页。")
        }
        .onChange(of: scenePhase) { oldPhase, phase in
            guard oldPhase != phase else { return }
            owner.setAppActive(phase == .active)
            liveDebug.setForeground(phase == .active)
            if phase == .active {
                supervisor.recordForeground()
                telemetry.record(.foreground)
                telemetry.flush()
            } else if phase == .background {
                supervisor.recordBackground()
                telemetry.record(.background, urgent: true)
            }
        }
        .onAppear {
            model.supervisor = supervisor
            liveDebug.resourceGate = resourceGate
            liveDebug.supervisor = supervisor
            liveDebug.setForeground(scenePhase == .active)
            thermalStateDescription = Self.formatThermalState(ProcessInfo.processInfo.thermalState)
            supervisor.recordLaunch()
            if supervisor.isCircuitOpen {
                model.processTerminated = true
            }
            if model.processTerminated || supervisor.isSafeModeActive {
                resourceGate.disableForSafety()
                liveDebug.stop()
            }
            telemetry.record(.launch, urgent: true)
        }
        .onChange(of: model.processTerminated) { _, terminated in
            if terminated {
                resourceGate.disableForSafety()
                liveDebug.stop()
            }
        }
        .onChange(of: supervisor.isSafeModeActive) { _, active in
            if active { liveDebug.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            telemetry.record(.memoryWarning, urgent: true)
            liveDebug.memoryWarning()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            let current = ProcessInfo.processInfo.thermalState
            thermalStateDescription = Self.formatThermalState(current)
            telemetry.recordThermalStateChange(current)
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            telemetry.periodicTick(isActive: scenePhase == .active)
        }
    }

    static func formatThermalState(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "正常 (Nominal)"
        case .fair: return "温热 (Fair)"
        case .serious: return "较热 (Serious)"
        case .critical: return "严重过热 (Critical)"
        @unknown default: return "未知"
        }
    }
}

/// Native safe mode screen that replaces or covers failed web view independently from WebContent.
struct NativeSafeModeView: View {
    @ObservedObject var model: OptimizedAppModel
    @ObservedObject var owner: ConversationManagerOwner
    let telemetry: OptimizedTelemetry
    @ObservedObject var supervisor: NativeOptimizationSupervisor

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "shield.slash.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(supervisor.isCircuitOpen ? .red : .orange)
                        .padding(.top, 24)

                    Text(supervisor.isCircuitOpen ? "熔断安全模式" : "网页安全模式")
                        .font(.title2.bold())

                    Text(supervisor.lastFailureReason ?? "网页进程已停止。为保护会话安全，已暂停网页加载。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Primary actions
                VStack(spacing: 12) {
                    Button {
                        owner.invalidateDocument(processTerminated: true)
                        telemetry.record(.manualRecovery, urgent: true)
                        model.rebuildAfterConfirmation()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("重新创建网页 (返回主页)")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityIdentifier("safemode.rebuild.button")

                    Button {
                        supervisor.stayInSafeMode()
                    } label: {
                        Text("保持安全模式")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("safemode.staysafe.button")
                }
                .padding(.horizontal, 24)

                // Diagnostics export
                ShareLink(item: supervisor.exportReport(telemetryReport: telemetry.localReport)) {
                    Label("导出原生诊断报告", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityIdentifier("safemode.export.button")

                // Mirror Fallback Instructions
                VStack(alignment: .leading, spacing: 10) {
                    Label("Mirror 客户端备用指引", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("若网页版持续异常退出，建议直接从 iPhone 主屏幕打开已安装的 ChatGPT Web 镜像版。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("两款应用完全独立：独立沙盒、独立登录、不共享 Cookie 或凭据，不会干扰正常使用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("safemode.mirror.instructions")

                Spacer(minLength: 24)
            }
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier("native.safemode.view")
    }
}
