import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    let scripts: RemoteScriptManager
    let updates: AppUpdateManager
    let web: WebViewStore

    @Published var optimizationMode: OptimizationMode {
        didSet {
            UserDefaults.standard.set(optimizationMode.rawValue, forKey: "optimizationMode")
            web.setOptimizationMode(optimizationMode)
        }
    }

    @Published var keepRecentTurns: Int {
        didSet {
            keepRecentTurns = min(max(keepRecentTurns, 8), 40)
            UserDefaults.standard.set(keepRecentTurns, forKey: "keepRecentTurns")
            web.setKeepRecentTurns(keepRecentTurns)
        }
    }

    private var memoryObserver: NSObjectProtocol?

    init() {
        let scripts = RemoteScriptManager()
        self.scripts = scripts
        self.updates = AppUpdateManager()

        let savedMode = UserDefaults.standard.string(forKey: "optimizationMode")
            .flatMap(OptimizationMode.init(rawValue:)) ?? .auto
        self.optimizationMode = savedMode

        let savedKeep = UserDefaults.standard.integer(forKey: "keepRecentTurns")
        let initialKeepRecentTurns = savedKeep == 0 ? 18 : min(max(savedKeep, 8), 40)
        self.keepRecentTurns = initialKeepRecentTurns

        self.web = WebViewStore(
            performanceScript: scripts.bestAvailableScript(),
            engineVersion: scripts.currentVersion,
            remoteConfig: scripts.currentConfig,
            mode: savedMode,
            keepRecentTurns: initialKeepRecentTurns
        )

        scripts.onInstalledUpdate = { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
        }

        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak web] _ in
            Task { @MainActor in
                web?.handleMemoryWarning()
            }
        }

        Task {
            await scripts.checkForUpdate(force: false)
            await updates.checkIfNeeded()
        }
    }

    deinit {
        if let memoryObserver {
            NotificationCenter.default.removeObserver(memoryObserver)
        }
    }

    func checkPerformanceUpdateAndApply() async {
        let changed = await scripts.checkForUpdate(force: true)
        guard changed else { return }

        web.installPerformanceScript(
            scripts.bestAvailableScript(),
            engineVersion: scripts.currentVersion,
            remoteConfig: scripts.currentConfig,
            reload: true
        )
    }

    func applyCachedPerformanceEngine() {
        web.installPerformanceScript(
            scripts.bestAvailableScript(),
            engineVersion: scripts.currentVersion,
            remoteConfig: scripts.currentConfig,
            reload: true
        )
    }
}
