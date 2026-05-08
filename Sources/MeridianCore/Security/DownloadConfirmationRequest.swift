import Foundation

public struct DownloadConfirmationRequest: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var suggestedFilename: String
    public var sanitizedFilename: String
    public var sourceURL: URL?
    public var risk: DownloadSafetyPolicy.Risk
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        suggestedFilename: String,
        sanitizedFilename: String,
        sourceURL: URL? = nil,
        risk: DownloadSafetyPolicy.Risk,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.suggestedFilename = suggestedFilename
        self.sanitizedFilename = sanitizedFilename
        self.sourceURL = sourceURL
        self.risk = risk
        self.createdAt = createdAt
    }

    public var pendingMessage: String {
        switch risk {
        case .low:
            return "Download is waiting for a save location."
        case .requiresConfirmation:
            return "Risky download is waiting for confirmation."
        case .blocked(let reason):
            return reason
        }
    }

    public var confirmationTitle: String {
        switch risk {
        case .low:
            return "Download File?"
        case .requiresConfirmation:
            return "Confirm Risky Download?"
        case .blocked:
            return "Download Blocked"
        }
    }

    public var confirmButtonTitle: String {
        "Choose Location"
    }

    public var cancelledMessage: String {
        "Download was canceled."
    }

    public var approvedMessage: String {
        "Download destination approved."
    }

    public var confirmationMessage: String {
        var lines = [
            "Meridian will only save this download after you choose a destination.",
            "",
            "File: \(sanitizedFilename)",
            "Source: \(sourceDescription)"
        ]

        if case .requiresConfirmation(let reason) = risk {
            lines.append("Risk: \(reason)")
        }

        return lines.joined(separator: "\n")
    }

    public var sourceDescription: String {
        guard let sourceURL else {
            return "Current page"
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
