import Foundation

public enum BrowserUserAgentPolicy {
    public static func desktopSafariUserAgent(
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> String {
        let majorVersion = max(osVersion.majorVersion, 17)
        let minorVersion = max(osVersion.minorVersion, 0)
        return """
        Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 \
        (KHTML, like Gecko) Version/\(majorVersion).\(minorVersion) Safari/605.1.15
        """
    }
}
