import Foundation

public struct URLSecurityPolicy: Sendable {
    public static let insecureTransportMessage = "This page uses insecure HTTP."

    public enum Decision: Equatable, Sendable {
        case allowInWebView
        case requireExternalApplicationConfirmation
        case requireLocalFileConfirmation
        case block(reason: String)
    }

    public var allowedWebSchemes: Set<String>
    public var externalApplicationSchemes: Set<String>
    public var blockedSchemes: Set<String>

    public init(
        allowedWebSchemes: Set<String> = ["http", "https", "about"],
        externalApplicationSchemes: Set<String> = ["facetime", "mailto", "maps", "tel"],
        blockedSchemes: Set<String> = ["data", "javascript", "vbscript"]
    ) {
        self.allowedWebSchemes = allowedWebSchemes
        self.externalApplicationSchemes = externalApplicationSchemes
        self.blockedSchemes = blockedSchemes
    }

    public func decision(for url: URL) -> Decision {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return .block(reason: "Missing URL scheme.")
        }

        if blockedSchemes.contains(scheme) {
            return .block(reason: "Blocked unsafe URL scheme: \(scheme).")
        }

        if scheme == "file" {
            return .requireLocalFileConfirmation
        }

        if allowedWebSchemes.contains(scheme) {
            return .allowInWebView
        }

        if externalApplicationSchemes.contains(scheme) {
            return .requireExternalApplicationConfirmation
        }

        return .block(reason: "Unsupported URL scheme: \(scheme).")
    }

    public func confirmationKind(for url: URL) -> URLConfirmationRequest.Kind? {
        switch decision(for: url) {
        case .requireExternalApplicationConfirmation:
            return .externalApplication
        case .requireLocalFileConfirmation:
            return .localFile
        case .allowInWebView, .block:
            return nil
        }
    }

    public func isInsecureTransport(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http" && !isLoopbackOrLocalhost(url)
    }

    public func httpsUpgradeCandidate(for url: URL) -> URL? {
        guard allowedWebSchemes.contains("http"),
              allowedWebSchemes.contains("https"),
              url.scheme?.lowercased() == "http",
              !isLoopbackOrLocalhost(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = "https"
        return components.url
    }

    public func isHTTPSUpgradeCandidate(_ candidateURL: URL, for originalHTTPURL: URL) -> Bool {
        httpsUpgradeCandidate(for: originalHTTPURL) == candidateURL
    }

    public func shouldFallbackToHTTP(afterHTTPSUpgradeError error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return true
        }

        let certificateErrorCodes: Set<Int> = [
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorClientCertificateRejected,
            NSURLErrorClientCertificateRequired
        ]

        return !certificateErrorCodes.contains(nsError.code)
    }

    public func securityMessage(forAllowedWebURL url: URL) -> String? {
        isInsecureTransport(url) ? Self.insecureTransportMessage : nil
    }

    private func isLoopbackOrLocalhost(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else {
            return false
        }

        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
    }
}
