import Foundation

public struct DownloadSafetyPolicy: Sendable {
    public enum Risk: Equatable, Sendable {
        case low
        case requiresConfirmation(reason: String)
        case blocked(reason: String)
    }

    private let blockedExtensions: Set<String>
    private let confirmationExtensions: Set<String>

    public init(
        blockedExtensions: Set<String> = ["app", "pkg", "mobileconfig"],
        confirmationExtensions: Set<String> = ["command", "dmg", "exec", "scpt", "sh", "terminal", "workflow"]
    ) {
        self.blockedExtensions = blockedExtensions
        self.confirmationExtensions = confirmationExtensions
    }

    public func sanitizedFilename(from suggestedFilename: String) -> String {
        let trimmed = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "download" : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/\\:\0")
            .union(.newlines)
            .union(.controlCharacters)

        let sanitizedScalars = fallback.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "-" : Character(scalar)
        }
        let sanitized = String(sanitizedScalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "download" : sanitized
    }

    public func risk(for filename: String) -> Risk {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        guard !ext.isEmpty else {
            return .low
        }

        if blockedExtensions.contains(ext) {
            return .blocked(reason: "Downloads ending in .\(ext) require a dedicated installer flow.")
        }

        if confirmationExtensions.contains(ext) {
            return .requiresConfirmation(reason: "Downloads ending in .\(ext) can execute code.")
        }

        return .low
    }
}
