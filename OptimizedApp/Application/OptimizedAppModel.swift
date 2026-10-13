import Foundation
import SwiftUI

@MainActor
final class OptimizedAppModel: ObservableObject {
    @Published var webViewGeneration = UUID()
    @Published var processTerminated = false
    @Published var downloadedFile: URL?
    @Published var status = "正在打开 ChatGPT"
    @Published var diagnosticsEnabled = false
    var retryHandler: ((String, Int) async -> Bool)?

    func markReady() {
        status = "ChatGPT"
    }

    func markProcessTerminated() {
        processTerminated = true
        status = "网页进程已停止"
    }

    func rebuildAfterConfirmation() {
        processTerminated = false
        status = "正在恢复网页"
        webViewGeneration = UUID()
    }

    func retry(document: String, sequence: Int) async -> Bool {
        await retryHandler?(document, sequence) ?? false
    }
}
