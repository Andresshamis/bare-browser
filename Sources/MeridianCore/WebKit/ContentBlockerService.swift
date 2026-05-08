import Foundation
import WebKit

@MainActor
public enum ContentBlockerService {
    public static let defaultIdentifier = "MeridianDefaultPrivacyRules"

    public static func installDefaultRules(into userContentController: WKUserContentController) {
        guard let store = WKContentRuleListStore.default() else {
            return
        }

        store.compileContentRuleList(
            forIdentifier: defaultIdentifier,
            encodedContentRuleList: defaultRuleList
        ) { ruleList, _ in
            guard let ruleList else {
                return
            }
            userContentController.add(ruleList)
        }
    }

    private static let defaultRuleList = #"""
    [
      {
        "trigger": {
          "url-filter": ".*://.*(doubleclick\\.net|googlesyndication\\.com|google-analytics\\.com|facebook\\.com/tr|connect\\.facebook\\.net).*"
        },
        "action": {
          "type": "block"
        }
      }
    ]
    """#
}
