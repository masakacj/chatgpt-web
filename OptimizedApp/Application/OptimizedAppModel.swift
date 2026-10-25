import Foundation
import SwiftUI

@MainActor
final class OptimizedAppModel: ObservableObject {
    @Published var webViewGeneration = UUID()
    @Published var processTerminated = false
    @Published var downloadedFile: URL?
    @Published var status = "正在打开 ChatGPT"
    @Published var diagnosticsEnabled = false
    @Published var recoveryAttempts = 0
    @Published var targetURL = URL(string: "https://chatgpt.com/")!

    weak var supervisor: NativeOptimizationSupervisor?
    var retryHandler: ((String, Int) async -> Bool)?
    private(set) var lastTerminatedGeneration: UUID?

    func markReady() {
        status = "ChatGPT"
        recoveryAttempts = 0
    }

    /// On WebContent termination: NEVER automatically regenerate WKWebView.
    /// Invalidate and show native safe screen, requiring explicit user confirmation before rebuild.
    /// Repeated same-generation callbacks are idempotent and will not increment failure count.
    func markProcessTerminated(route: String = "other", isSynthetic: Bool = false) {
        status = "网页进程已停止"
        processTerminated = true
        guard isSynthetic || lastTerminatedGeneration != webViewGeneration else {
            return
        }
        if !isSynthetic {
            lastTerminatedGeneration = webViewGeneration
        }
        supervisor?.recordWebContentTermination(route: route, isSynthetic: isSynthetic)
    }

    /// User-invoked simulated WebContent termination test action.
    /// Exercises Supervisor and safe mode UI without calling private WebKit kill APIs or sending network requests.
    func simulateProcessTermination() {
        markProcessTerminated(route: "other", isSynthetic: true)
    }

    /// Explicit user-confirmed rebuild: restores to home route instead of blindly re-entering a risky route.
    func rebuildAfterConfirmation() {
        processTerminated = false
        supervisor?.confirmRebuild()
        status = "正在恢复网页"
        recoveryAttempts += 1
        targetURL = URL(string: "https://chatgpt.com/")!
        webViewGeneration = UUID()
        lastTerminatedGeneration = nil
    }

    func retry(document: String, sequence: Int) async -> Bool {
        await retryHandler?(document, sequence) ?? false
    }
}
