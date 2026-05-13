import WebKit

public enum WebViewNewWindowPolicy {
    public static func shouldOpenInCurrentTab(
        navigationType: WKNavigationType,
        sourceFrameIsMainFrame: Bool
    ) -> Bool {
        switch navigationType {
        case .linkActivated, .formSubmitted, .formResubmitted:
            true
        case .other:
            sourceFrameIsMainFrame
        case .backForward, .reload:
            false
        @unknown default:
            false
        }
    }
}
