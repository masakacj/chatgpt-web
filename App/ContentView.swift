import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        ChatGPTWebView(store: model.web)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .topTrailing) {
                FloatingControlButton(
                    web: model.web,
                    mode: model.optimizationMode,
                    openSettings: { showingSettings = true }
                )
                .padding(.top, 8)
                .padding(.trailing, 10)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    model: model,
                    scripts: model.scripts,
                    updates: model.updates,
                    web: model.web
                )
            }
    }
}

private struct FloatingControlButton: View {
    @ObservedObject var web: WebViewStore
    let mode: OptimizationMode
    let openSettings: () -> Void

    var body: some View {
        Menu {
            Section {
                Label(statusText, systemImage: web.metrics.streaming ? "waveform" : "bolt.fill")
                    .foregroundStyle(.secondary)
            }

            Button(action: web.goBack) {
                Label("返回", systemImage: "chevron.left")
            }
            .disabled(!web.webView.canGoBack)

            Button(action: web.goForward) {
                Label("前进", systemImage: "chevron.right")
            }
            .disabled(!web.webView.canGoForward)

            Button(action: web.reload) {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            Divider()

            Button(action: openSettings) {
                Label("设置", systemImage: "gearshape")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Circle()
                            .stroke(.primary.opacity(0.10), lineWidth: 0.5)
                    }
                    .shadow(radius: 4, y: 1)

                if web.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: web.metrics.streaming ? "waveform" : "bolt.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.82))
                }
            }
            .contentShape(Circle())
            .accessibilityLabel("ChatGPT Web 控制")
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        if web.metrics.turns == 0 {
            return "性能：\(mode.title)"
        }

        return "\(web.metrics.effectiveMode) · \(web.metrics.turns)轮 · C\(web.metrics.cold)"
    }
}
