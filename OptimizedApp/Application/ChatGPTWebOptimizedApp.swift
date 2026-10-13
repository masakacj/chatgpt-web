import SwiftUI

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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .top) {
            OptimizedWebView(model: model, owner: owner)
                .id(model.webViewGeneration)
                .ignoresSafeArea()
            if model.diagnosticsEnabled {
                HStack(spacing: 8) {
                    Text(owner.projection.task.rawValue)
                    Text("r\(owner.projection.revision)")
                    Text(model.status)
                    Spacer()
                    Button("关闭诊断") { model.diagnosticsEnabled = false }
                }
                .font(.caption.monospaced())
                .padding(10)
                .background(.ultraThinMaterial)
                .padding(.top, 8)
                .padding(.horizontal, 10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                if let file = model.downloadedFile {
                    ShareLink(item: file) {
                        Label("导出下载", systemImage: "square.and.arrow.up")
                            .padding(10).background(.regularMaterial, in: Capsule())
                    }
                }
                Button {
                    model.diagnosticsEnabled.toggle()
                } label: {
                    Image(systemName: "stethoscope")
                        .frame(width: 40, height: 40)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("诊断")
            }
            .padding(14)
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
                model.rebuildAfterConfirmation()
            }
        } message: {
            Text("登录数据会保留。恢复需要重新创建 WKWebView，不会自动重复提交消息。")
        }
        .onChange(of: scenePhase) { _, phase in
            owner.setAppActive(phase == .active)
        }
    }
}
