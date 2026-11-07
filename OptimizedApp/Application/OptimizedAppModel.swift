import Foundation
import SwiftUI
import WebKit

@MainActor
final class OptimizedAppModel: ObservableObject {
    @Published var webViewGeneration = UUID()
    // Weak only: retain no additional WebContent memory while tracking reuse.
    weak var attachedWebView: WKWebView?
    var isBackgrounded = false
    @Published private(set) var pendingBackgroundReadOnlyRecovery = false
    @Published var processTerminated = false
    @Published var downloadedFile: URL?
    @Published var status = "正在打开 ChatGPT"
    @Published var diagnosticsEnabled = false
    @Published private(set) var frameworkCacheReport = "未检测"
    @Published private(set) var frameworkCacheChecking = false
    @Published var recoveryAttempts = 0
    @Published var targetURL = URL(string: "https://chatgpt.com/")!
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    var goBackHandler: (() -> Void)?
    var goForwardHandler: (() -> Void)?
    weak var supervisor: NativeOptimizationSupervisor?
    var retryHandler: ((String, Int) async -> Bool)?
    private(set) var lastTerminatedGeneration: UUID?

    func markReady() {
        status = "ChatGPT"
        recoveryAttempts = 0
    }

    func setCanGoBack(_ available: Bool) {
        guard canGoBack != available else { return }
        canGoBack = available
    }

    func goBack() {
        goBackHandler?()
    }

    func setCanGoForward(_ available: Bool) {
        guard canGoForward != available else { return }
        canGoForward = available
    }

    func goForward() {
        goForwardHandler?()
    }

    /// On WebContent termination: NEVER automatically regenerate WKWebView.
    /// Invalidate and show native safe screen, requiring explicit user confirmation before rebuild.
    /// Repeated same-generation callbacks are idempotent and will not increment failure count.
    func markProcessTerminated(route: String = "other", isSynthetic: Bool = false,
                               backgroundReadOnlyEligible: Bool = false) {
        goBackHandler = nil
        goForwardHandler = nil
        canGoBack = false
        canGoForward = false
        status = "网页进程已停止"
        processTerminated = true
        guard isSynthetic || lastTerminatedGeneration != webViewGeneration else {
            return
        }
        if !isSynthetic {
            lastTerminatedGeneration = webViewGeneration
        }
        supervisor?.recordWebContentTermination(route: route, isSynthetic: isSynthetic)
        pendingBackgroundReadOnlyRecovery = !isSynthetic && backgroundReadOnlyEligible &&
            supervisor?.isCircuitOpen == false && supervisor?.isSafeModeActive == true
    }

    /// User-invoked simulated WebContent termination test action.
    /// Exercises Supervisor and safe mode UI without calling private WebKit kill APIs or sending network requests.
    func simulateProcessTermination() {
        markProcessTerminated(route: "other", isSynthetic: true)
    }

    /// One-shot GET-only recovery from a verified background WebContent loss.
    /// Never restores the old conversation route or replays any Send/Retry/approval.
    @discardableResult
    func restoreHomeAfterBackgroundLoss() -> Bool {
        guard pendingBackgroundReadOnlyRecovery, processTerminated,
              supervisor?.confirmBackgroundReadOnlyRecovery() == true else { return false }
        pendingBackgroundReadOnlyRecovery = false
        processTerminated = false
        status = "正在恢复网页"
        recoveryAttempts += 1
        targetURL = URL(string: "https://chatgpt.com/")!
        webViewGeneration = UUID()
        lastTerminatedGeneration = nil
        return true
    }

    /// Explicit user-confirmed rebuild: restores to home route instead of blindly re-entering a risky route.
    func rebuildAfterConfirmation() {
        pendingBackgroundReadOnlyRecovery = false
        processTerminated = false
        supervisor?.confirmRebuild()
        status = "正在恢复网页"
        recoveryAttempts += 1
        targetURL = URL(string: "https://chatgpt.com/")!
        webViewGeneration = UUID()
        lastTerminatedGeneration = nil
    }


    /// Read-only resource-timing sample. It never fetches/replaces a resource,
    /// reads a URL's content, or changes the site's origin/cache headers.
    func inspectFrameworkResourceCache() async {
        guard !frameworkCacheChecking else { return }
        guard !processTerminated, let webView = attachedWebView else {
            frameworkCacheReport = "网页未就绪"
            return
        }
        guard !webView.isLoading else {
            frameworkCacheReport = "网页仍在加载，请稍后检查"
            return
        }
        frameworkCacheChecking = true
        defer { frameworkCacheChecking = false }

        let javascript = """
        const entries = performance.getEntriesByType('resource');
        let total = 0, sameOriginMeasured = 0, suspectedHits = 0, opaque = 0, crossOrigin = 0;
        let transferredKiB = 0;
        for (let i = 0; i < entries.length && i < 800; i++) {
            const resource = entries[i];
            if (resource.initiatorType !== 'script' && resource.initiatorType !== 'link' &&
                resource.initiatorType !== 'css') continue;
            total++;
            let local = false;
            try { local = new URL(resource.name, location.href).origin === location.origin; }
            catch (_) {}
            if (!local) { crossOrigin++; continue; }
            if (resource.encodedBodySize > 0) {
                sameOriginMeasured++;
                if (resource.transferSize === 0) suspectedHits++;
                transferredKiB += Math.ceil(resource.transferSize / 1024);
            } else {
                opaque++;
            }
        }
        return {total, sameOriginMeasured, suspectedHits, opaque, crossOrigin, transferredKiB};
        """
        do {
            guard let result = try await webView.callAsyncJavaScript(
                javascript, arguments: [:], in: nil,
                contentWorld: WebConfigurationFactory.observationWorld) as? [String: Any],
                attachedWebView === webView, !processTerminated else {
                frameworkCacheReport = "页面已切换，请重新检查"
                return
            }
            func count(_ name: String) -> Int {
                max(0, min(10_000, (result[name] as? NSNumber)?.intValue ?? 0))
            }
            frameworkCacheReport = "JS/CSS：\(count("total")) 项；同源可测 \(count("sameOriginMeasured")) 项，疑似缓存复用 \(count("suspectedHits")) 项；跨域 \(count("crossOrigin")) 项无法判断"
        } catch {
            frameworkCacheReport = "读取失败：页面可能正在重建"
        }
    }

    func retry(document: String, sequence: Int) async -> Bool {
        await retryHandler?(document, sequence) ?? false
    }
}
