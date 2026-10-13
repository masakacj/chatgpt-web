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
    @StateObject private var model = OptimizedAppModel()
    @StateObject private var owner = ConversationManagerOwner()
    @StateObject private var telemetry = OptimizedTelemetry()
    @Environment(\.scenePhase) private var scenePhase

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
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.regularMaterial)

            OptimizedWebView(model: model, owner: owner, telemetry: telemetry)
                .id(model.webViewGeneration)
        }
        .sheet(isPresented: $model.diagnosticsEnabled) {
            NavigationStack {
                List {
                    LabeledContent("任务状态", value: owner.projection.task.rawValue == "unknown" ? "尚未检测到任务状态" : owner.projection.task.rawValue)
                    LabeledContent("修订版本", value: String(owner.projection.revision))
                    LabeledContent("网页状态", value: model.status)
                    LabeledContent("网页恢复次数", value: String(model.recoveryAttempts))
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
                        ShareLink("分享本地诊断摘要", item: telemetry.localReport)
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
        .alert("网页进程已停止", isPresented: $model.processTerminated) {
            Button("稍后", role: .cancel) {}
            Button("重新创建网页") {
                owner.invalidateDocument(processTerminated: true)
                telemetry.record(.manualRecovery, urgent: true)
                model.rebuildAfterConfirmation()
            }
        } message: {
            Text("登录数据会保留。恢复需要重新创建 WKWebView，不会自动重复提交消息。")
        }
        .onChange(of: scenePhase) { _, phase in
            owner.setAppActive(phase == .active)
            if phase == .active {
                telemetry.record(.foreground)
                telemetry.flush()
            } else if phase == .background {
                telemetry.record(.background, urgent: true)
            }
        }
        .onAppear {
            telemetry.record(.launch, urgent: true)
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
