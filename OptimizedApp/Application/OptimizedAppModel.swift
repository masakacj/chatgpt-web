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
    @Published private(set) var webPageUnresponsive = false
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
    private weak var webHealthView: WKWebView?
    private var webHealthToken: UUID?
    private var webHealthStartedAt: Date?
    private weak var navigationProbeView: WKWebView?
    private var navigationProbeStartedAt: Date?

    func markReady() {
        status = "ChatGPT"
        recoveryAttempts = 0
    }

    static func isWebHealthTimedOut(since start: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(start) >= 15
    }

    func beginNavigationJSProbe(on view: WKWebView) -> Bool {
        guard !(webHealthToken != nil && webHealthView === view),
              !(navigationProbeStartedAt != nil && navigationProbeView === view) else { return false }
        navigationProbeView = view
        navigationProbeStartedAt = Date()
        return true
    }

    func endNavigationJSProbe(on view: WKWebView) {
        guard navigationProbeView === view else { return }
        navigationProbeView = nil
        navigationProbeStartedAt = nil
        if webPageUnresponsive { webPageUnresponsive = false }
    }

    /// A single bounded read-only JS ping; no DOM scans, chat content or request replay.
    /// An unanswered ping stays in flight, preventing a growing queue of WebKit calls.
    func checkWebContentHealth() -> Bool {
        guard !isBackgrounded, !processTerminated, let view = attachedWebView,
              !view.isLoading, view.url?.host == "chatgpt.com" else { return false }
        if let startedAt = navigationProbeStartedAt, navigationProbeView === view {
            guard !webPageUnresponsive, Self.isWebHealthTimedOut(since: startedAt) else { return false }
            webPageUnresponsive = true
            return true
        }
        if webHealthToken != nil && webHealthView !== view {
            webHealthToken = nil
            webHealthStartedAt = nil
        }
        if let startedAt = webHealthStartedAt {
            guard !webPageUnresponsive, Self.isWebHealthTimedOut(since: startedAt) else { return false }
            webPageUnresponsive = true
            return true
        }
        let token = UUID()
        let generation = webViewGeneration
        webHealthView = view
        webHealthToken = token
        webHealthStartedAt = Date()
        Task { [weak self, weak view] in
            guard let view else { return }
            let responsive: Bool
            do {
                _ = try await view.callAsyncJavaScript(
                    "return 1;", arguments: [:], in: nil,
                    contentWorld: WebConfigurationFactory.observationWorld)
                responsive = true
            } catch { responsive = false }
            guard let self, self.webHealthToken == token,
                  self.webHealthView === view,
                  self.webViewGeneration == generation else { return }
            self.webHealthToken = nil
            self.webHealthStartedAt = nil
            self.webHealthView = nil
            if responsive && self.webPageUnresponsive { self.webPageUnresponsive = false }
        }
        return false
    }

    func resetWebContentHealth() {
        if navigationProbeView === attachedWebView, navigationProbeStartedAt != nil {
            navigationProbeStartedAt = Date()
        } else {
            navigationProbeView = nil
            navigationProbeStartedAt = nil
        }
        if webHealthToken != nil && webHealthView === attachedWebView {
            // A pending WebKit call cannot be canceled by clearing its token.
            webHealthStartedAt = Date()
        } else {
            webHealthToken = nil
            webHealthStartedAt = nil
            webHealthView = nil
        }
        if webPageUnresponsive { webPageUnresponsive = false }
    }

    func resumeWebContentHealth() {
        // Time spent backgrounded is not evidence that a foreground WebContent is hung.
        if webHealthStartedAt != nil { webHealthStartedAt = Date() }
        if navigationProbeStartedAt != nil { navigationProbeStartedAt = Date() }
    }

    #if DEBUG
    func setPendingWebHealthProbeForTesting(_ view: WKWebView) {
        webHealthView = view
        webHealthToken = UUID()
        webHealthStartedAt = Date()
    }
    var hasPendingWebHealthProbeForTesting: Bool { webHealthToken != nil }
    var hasPendingNavigationProbeForTesting: Bool { navigationProbeStartedAt != nil }
    #endif

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
        resetWebContentHealth()
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
        resetWebContentHealth()
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
        resetWebContentHealth()
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
