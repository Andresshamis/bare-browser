import AuthenticationServices
import Combine
import OSLog
import Security

private let browserPasskeyLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MeridianBrowser",
    category: "Passkeys"
)

public enum BrowserPasskeyCapability {
    public static let browserEntitlement =
        "com.apple.developer.web-browser.public-key-credential"

    public static let hasSignedBrowserEntitlement: Bool = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                browserEntitlement as CFString,
                nil
              ) else {
            return false
        }

        return value as? Bool == true
    }()
}

public enum BrowserPasskeyAuthorizationState: Equatable, Sendable {
    case authorized
    case denied
    case notDetermined

    init(_ state: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState) {
        switch state {
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .denied
        }
    }
}

public enum BrowserPasskeyAccessPolicy {
    public static func shouldRequestAuthorization(
        isBrowserEntitled: Bool,
        state: BrowserPasskeyAuthorizationState,
        didRequestThisLaunch: Bool
    ) -> Bool {
        isBrowserEntitled
            && state == .notDetermined
            && !didRequestThisLaunch
    }

    public static func shouldInstallUnavailableInterception(
        isBrowserEntitled: Bool
    ) -> Bool {
        !isBrowserEntitled
    }
}

@MainActor
public final class BrowserPasskeyAccessController: ObservableObject {
    public static let browserEntitlement =
        BrowserPasskeyCapability.browserEntitlement

    @Published public private(set) var authorizationState: BrowserPasskeyAuthorizationState
    public let isBrowserEntitled: Bool

    private let credentialManager: ASAuthorizationWebBrowserPublicKeyCredentialManager
    private var didRequestThisLaunch = false

    public init() {
        let credentialManager = ASAuthorizationWebBrowserPublicKeyCredentialManager()
        self.credentialManager = credentialManager
        self.authorizationState = BrowserPasskeyAuthorizationState(
            credentialManager.authorizationStateForPlatformCredentials
        )
        self.isBrowserEntitled = BrowserPasskeyCapability.hasSignedBrowserEntitlement
    }

    public func requestAuthorizationIfNeeded() {
        guard BrowserPasskeyAccessPolicy.shouldRequestAuthorization(
            isBrowserEntitled: isBrowserEntitled,
            state: authorizationState,
            didRequestThisLaunch: didRequestThisLaunch
        ) else {
            if !isBrowserEntitled {
                browserPasskeyLogger.notice(
                    "browser passkey access unavailable because the signed browser entitlement is missing"
                )
            }
            return
        }

        didRequestThisLaunch = true
        credentialManager.requestAuthorizationForPublicKeyCredentials { [weak self] state in
            let resolvedState = BrowserPasskeyAuthorizationState(state)
            Task { @MainActor [weak self] in
                self?.authorizationState = resolvedState
                browserPasskeyLogger.info(
                    "browser passkey authorization completed state=\(String(describing: resolvedState), privacy: .public)"
                )
            }
        }
    }
}
