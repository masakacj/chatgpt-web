import SwiftUI
import Combine

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
    @Environment(\.scenePhase) private var scenePhase

    init(supervisor: NativeOptimizationSupervisor = NativeOptimizationSupervisor(),
         model: OptimizedAppModel = OptimizedAppModel(),
         owner: ConversationManagerOwner = ConversationManagerOwner(),
         telemetry: OptimizedTelemetry = OptimizedTelemetry()) {
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
                Text("ChatGPT")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
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
            } else {
                OptimizedWebView(model: model, owner: owner, telemetry: telemetry,
                                 supervisor: supervisor, resourceGate: resourceGate)
                    .id(model.webViewGeneration)
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

                    Section("资源加载策略") {
                        Toggle("资源过滤实验（下次打开网页生效）", isOn: $resourceGate.isEnabled)
                        LabeledContent("已验证安全规则", value: String(NativeResourceGate.approvedRuleCount))
                        Text("当前没有经过实机验证的可阻断资源；此开关不会过滤 ChatGPT 请求，也不代表已提升性能。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
        .onChange(of: scenePhase) { _, phase in
            owner.setAppActive(phase == .active)
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
            supervisor.recordLaunch()
            if supervisor.isCircuitOpen {
                model.processTerminated = true
            }
            if model.processTerminated || supervisor.isSafeModeActive {
                resourceGate.disableForSafety()
            }
            telemetry.record(.launch, urgent: true)
        }
        .onChange(of: model.processTerminated) { _, terminated in
            if terminated { resourceGate.disableForSafety() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            telemetry.record(.memoryWarning, urgent: true)
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            telemetry.periodicTick(isActive: scenePhase == .active)
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
