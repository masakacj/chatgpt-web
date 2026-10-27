import Combine
import Foundation
import WebKit

/// WebKit-only, ChatGPT-top-page tracking suppression. Never intercept API/auth/MCP resources.
@MainActor
final class NativeResourceGate: ObservableObject {
    static let version = "r2-tracking-only"
    static let approvedRuleCount = 7
    static let approvedRulesJSON = #"""
    [
      {
        "trigger": {
          "url-filter": "^https?://([^/]+\\.)?google-analytics\\.com/g/collect",
          "if-domain": [
            "chatgpt.com",
            "*chatgpt.com"
          ],
          "load-type": [
            "third-party"
          ],
          "resource-type": [
            "script",
            "image",
            "raw"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([^/]+\\.)?google-analytics\\.com/collect",
          "if-domain": [
            "chatgpt.com",
            "*chatgpt.com"
          ],
          "load-type": [
            "third-party"
          ],
          "resource-type": [
            "script",
            "image",
            "raw"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([^/]+\\.)?doubleclick\\.net/pagead",
          "if-domain": [
            "chatgpt.com",
            "*chatgpt.com"
          ],
          "load-type": [
            "third-party"
          ],
          "resource-type": [
            "script",
            "image",
            "raw"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([^/]+\\.)?doubleclick\\.net/activityi",
          "if-domain": [
            "chatgpt.com",
            "*chatgpt.com"
          ],
          "load-type": [
            "third-party"
          ],
          "resource-type": [
            "script",
            "image",
            "raw"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([^/]+\\.)?googletagmanager\\.com/gtm\\.js",
          "if-domain": [
            "chatgpt.com",
            "*chatgpt.com"
          ],
          "load-type": [
            "third-party"
          ],
          "resource-type": [
            "script",
            "image",
            "raw"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([^/]+\\.)?clarity\\.ms/collect",
          "if-domain": [
            "chatgpt.com",
            "*chatgpt.com"
          ],
          "load-type": [
            "third-party"
          ],
          "resource-type": [
            "script",
            "image",
            "raw"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([^/]+\\.)?clarity\\.ms/tag",
          "if-domain": [
            "chatgpt.com",
            "*chatgpt.com"
          ],
          "load-type": [
            "third-party"
          ],
          "resource-type": [
            "script",
            "image",
            "raw"
          ]
        },
        "action": {
          "type": "block"
        }
      }
    ]
    """#
    private static let enabledKey = "optimized.resourceGate.enabled.v1"

    private let defaults: UserDefaults
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }
    @Published private(set) var appliedRuleCount = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // First run with real rules defaults to ON; respect a previously saved OFF choice.
        isEnabled = (defaults.object(forKey: Self.enabledKey) as? Bool) ?? true
    }

    func disableForSafety() {
        isEnabled = false
        appliedRuleCount = 0
    }

    /// Apply before navigation; compilation failure never prevents ChatGPT loading.
    func install(to controller: WKUserContentController,
                 safeMode: Bool,
                 completion: @escaping (Bool) -> Void) {
        guard isEnabled && !safeMode else {
            appliedRuleCount = 0
            completion(false)
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "optimized-resource-\(Self.version)",
            encodedContentRuleList: Self.approvedRulesJSON
        ) { [weak self] ruleList, error in
            Task { @MainActor in
                guard let self, self.isEnabled, !safeMode, error == nil, let ruleList else {
                    self?.appliedRuleCount = 0
                    completion(false)
                    return
                }
                controller.add(ruleList)
                self.appliedRuleCount = Self.approvedRuleCount
                completion(true)
            }
        }
    }
}
