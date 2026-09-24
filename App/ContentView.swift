import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            ChatGPTWebView(store: model.web)
                .ignoresSafeArea(edges: .bottom)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PerfToolbar(
                web: model.web,
                mode: model.optimizationMode,
                openSettings: { showingSettings = true }
            )
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

private struct PerfToolbar: View {
    @ObservedObject var web: WebViewStore
    let mode: OptimizationMode
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: web.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!web.webView.canGoBack)

            Button(action: web.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!web.webView.canGoForward)

            Button(action: web.reload) {
                Image(systemName: "arrow.clockwise")
            }

            Divider()
                .frame(height: 20)

            HStack(spacing: 5) {
                Image(systemName: web.metrics.streaming ? "waveform" : "bolt.fill")
                Text(statusText)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            if web.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var statusText: String {
        if web.metrics.turns == 0 {
            return mode.title
        }
        return "\(web.metrics.effectiveMode) · \(web.metrics.turns)轮 · C\(web.metrics.cold)"
    }
}
