import Foundation

public struct DownloadSourceMetadata: Equatable, Sendable {
    public static let currentPage = DownloadSourceMetadata()

    public var displayDescription: String
    public var quarantineOrigin: String?

    public init(
        displayDescription: String = "Current page",
        quarantineOrigin: String? = nil
    ) {
        let trimmedDescription = displayDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayDescription = trimmedDescription.isEmpty ? "Current page" : trimmedDescription
        self.quarantineOrigin = quarantineOrigin
    }
}

public struct DownloadConfirmationRequest: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var suggestedFilename: String
    public var sanitizedFilename: String
    public var sourceMetadata: DownloadSourceMetadata
    public var risk: DownloadSafetyPolicy.Risk
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        suggestedFilename: String,
        sanitizedFilename: String,
        sourceMetadata: DownloadSourceMetadata = .currentPage,
        risk: DownloadSafetyPolicy.Risk,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.suggestedFilename = suggestedFilename
        self.sanitizedFilename = sanitizedFilename
        self.sourceMetadata = sourceMetadata
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
            "Lumen Browser will only save this download after you choose a destination.",
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
        sourceMetadata.displayDescription
    }
}
