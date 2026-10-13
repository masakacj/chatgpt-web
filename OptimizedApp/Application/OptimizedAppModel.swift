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
    private var lastRecovery = Date.distantPast
    var retryHandler: ((String, Int) async -> Bool)?

    func markReady() {
        status = "ChatGPT"
        recoveryAttempts = 0
    }

    func markProcessTerminated() {
        status = "网页进程已停止"
        let now = Date()
        if now.timeIntervalSince(lastRecovery) > 90 {
            recoveryAttempts = 0
        }
        lastRecovery = now
        if recoveryAttempts < 2 {
            recoveryAttempts += 1
            status = "正在恢复网页"
            webViewGeneration = UUID()
        } else {
            processTerminated = true
        }
    }

    func rebuildAfterConfirmation() {
        processTerminated = false
        status = "正在恢复网页"
        recoveryAttempts = 0
        webViewGeneration = UUID()
    }

    func retry(document: String, sequence: Int) async -> Bool {
        await retryHandler?(document, sequence) ?? false
    }
}
