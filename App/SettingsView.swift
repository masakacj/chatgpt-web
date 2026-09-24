import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var scripts: RemoteScriptManager
    @ObservedObject var updates: AppUpdateManager
    @ObservedObject var web: WebViewStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("版本") {
                    LabeledContent("App", value: AppConfig.fullVersion)
                    LabeledContent("Perf Engine", value: scripts.currentVersion)
                    LabeledContent("Web Engine", value: web.metrics.engineVersion)
                    LabeledContent("更新状态", value: scripts.status)

                    Button("检查并应用 Perf 更新") {
                        Task { await model.checkPerformanceUpdateAndApply() }
                    }

                    Toggle("自动检查 Perf 更新", isOn: $scripts.autoUpdate)

                    if let notes = scripts.latestNotes, !notes.isEmpty {
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("性能模式") {
                    Picker("优化等级", selection: $model.optimizationMode) {
                        ForEach(OptimizationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Stepper(
                        "保持最近 \(model.keepRecentTurns) 轮完整",
                        value: $model.keepRecentTurns,
                        in: 8...40
                    )

                    metric("当前轮数", web.metrics.turns)
                    metric("Hot", web.metrics.hot)
                    metric("Warm", web.metrics.warm)
                    metric("Cold", web.metrics.cold)
                    metric("Packed", web.metrics.packed)
                    metric("DOM", web.metrics.domNodes)

                    LabeledContent(
                        "Long Task",
                        value: String(format: "%.0f ms", web.metrics.longTaskMs)
                    )
                    LabeledContent("有效模式", value: web.metrics.effectiveMode)
                }

                Section("页面") {
                    Button("重新载入当前 Chat") {
                        dismiss()
                        web.hardReload()
                    }

                    Button("清理 Web 缓存（保留登录）") {
                        Task {
                            await web.clearWebCaches()
                            web.hardReload()
                        }
                    }

                    Button("在 Safari 打开当前页") {
                        web.openCurrentInSafari()
                    }

                    if web.processRestarts > 0 {
                        LabeledContent("WebKit 自动恢复", value: "\(web.processRestarts) 次")
                    }

                    if let error = web.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("App 更新") {
                    LabeledContent("状态", value: updates.status)

                    if let latest = updates.latestVersion {
                        LabeledContent("最新 Release", value: latest)
                    }

                    Button("检查 GitHub Release") {
                        Task { await updates.check(force: true) }
                    }

                    if updates.updateAvailable, let url = updates.releaseURL {
                        Link("打开最新 Release / IPA", destination: url)
                    }
                }

                Section("恢复") {
                    Button("恢复内置 Perf Engine", role: .destructive) {
                        scripts.resetToBundled()
                        model.applyCachedPerformanceEngine()
                    }

                    Link("打开项目仓库", destination: AppConfig.repositoryURL)
                }
            }
            .navigationTitle("ChatGPT Web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func metric(_ title: String, _ value: Int) -> some View {
        LabeledContent(title, value: "\(value)")
    }
}
