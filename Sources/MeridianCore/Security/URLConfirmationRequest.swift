import Foundation

public struct URLConfirmationRequest: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case externalApplication
        case localFile

        public var pendingMessage: String {
            switch self {
            case .externalApplication:
                return "External application link is waiting for confirmation."
            case .localFile:
                return "Local file link is waiting for confirmation."
            }
        }

        public var confirmationTitle: String {
            switch self {
            case .externalApplication:
                return "Open External Application?"
            case .localFile:
                return "Open Local File?"
            }
        }

        public var confirmButtonTitle: String {
            switch self {
            case .externalApplication:
                return "Open Application"
            case .localFile:
                return "Open File"
            }
        }

        public var approvedMessage: String {
            switch self {
            case .externalApplication:
                return "Opened external application link."
            case .localFile:
                return "Opened local file link."
            }
        }

        public var cancelledMessage: String {
            switch self {
            case .externalApplication:
                return "External application link was canceled."
            case .localFile:
                return "Local file link was canceled."
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var url: URL
    public var sourceURL: URL?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        url: URL,
        sourceURL: URL? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.sourceURL = sourceURL
        self.createdAt = createdAt
    }

    public var confirmationTitle: String {
        kind.confirmationTitle
    }

    public var confirmButtonTitle: String {
        kind.confirmButtonTitle
    }

    public var confirmationMessage: String {
        switch kind {
        case .externalApplication:
            return "Meridian will hand this link to another app only if you approve.\n\nLink: \(displayURL)\nSource: \(sourceDescription)"
        case .localFile:
            return "Meridian blocked local file access until you approve opening it outside the web view.\n\nFile: \(displayURL)\nSource: \(sourceDescription)"
        }
    }

    public var displayURL: String {
        if url.isFileURL {
            return url.path(percentEncoded: false)
        }
        return url.absoluteString
    }

    public var sourceDescription: String {
        guard let sourceURL else {
            return "Command bar"
        }

        if let host = sourceURL.host(percentEncoded: false), !host.isEmpty {
            return host
        }

        if let scheme = sourceURL.scheme, !scheme.isEmpty {
            return "\(scheme) URL"
        }

        return sourceURL.absoluteString
    }
}
