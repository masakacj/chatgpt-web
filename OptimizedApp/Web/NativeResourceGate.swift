import Combine
import Foundation
import WebKit

/// App-process policy owner. Content blockers run in WebKit, never in page JavaScript.
@MainActor
final class NativeResourceGate: ObservableObject {
    static let version = "r1-empty"
    static let approvedRuleCount = 0
    static let approvedRulesJSON = "[]"
    private static let enabledKey = "optimized.resourceGate.enabled.v1"

    private let defaults: UserDefaults
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    func disableForSafety() { isEnabled = false }

    /// Complete before navigation starts; never block page loading when compilation fails.
    func install(to controller: WKUserContentController,
                 safeMode: Bool,
                 completion: @escaping (Bool) -> Void) {
        guard isEnabled && !safeMode && Self.approvedRuleCount > 0 else {
            completion(false)
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "optimized-resource-(Self.version)",
            encodedContentRuleList: Self.approvedRulesJSON
        ) { ruleList, error in
            Task { @MainActor in
                guard error == nil, let ruleList else {
                    completion(false)
                    return
                }
                controller.add(ruleList)
                completion(true)
            }
        }
    }
}
