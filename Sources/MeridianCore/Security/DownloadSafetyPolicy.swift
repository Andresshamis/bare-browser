import Darwin
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
        let visibleFilename = sanitized.drop { $0 == "." }
        return visibleFilename.isEmpty ? "download" : String(visibleFilename)
    }

    public func confirmationRequest(
        suggestedFilename: String,
        sourceURL: URL? = nil,
        date: Date = Date()
    ) -> DownloadConfirmationRequest {
        let sanitizedFilename = sanitizedFilename(from: suggestedFilename)
        return DownloadConfirmationRequest(
            suggestedFilename: suggestedFilename,
            sanitizedFilename: sanitizedFilename,
            sourceURL: sourceURL,
            risk: risk(for: sanitizedFilename),
            createdAt: date
        )
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

    public func safeDestinationURL(
        for selectedURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard selectedURL.isFileURL else {
            return nil
        }

        let directoryURL = selectedURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isWritableFile(atPath: directoryURL.path) else {
            return nil
        }

        let safeFilename = sanitizedFilename(from: selectedURL.lastPathComponent)
        let requestedURL = directoryURL.appendingPathComponent(safeFilename, isDirectory: false)
        return availableDestinationURL(for: requestedURL, fileManager: fileManager)
    }

    public func availableDestinationURL(
        for requestedURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        guard requestedURL.isFileURL else {
            return requestedURL
        }

        let directoryURL = requestedURL.deletingLastPathComponent()
        let baseName = requestedURL.deletingPathExtension().lastPathComponent
        let pathExtension = requestedURL.pathExtension
        var candidateURL = requestedURL
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            let candidateFilename = pathExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(pathExtension)"
            candidateURL = directoryURL.appendingPathComponent(candidateFilename, isDirectory: false)
            suffix += 1
        }

        return candidateURL
    }

    public func quarantineMetadataValue(sourceURL: URL?, date: Date = Date()) -> String {
        let timestamp = String(Int(date.timeIntervalSince1970), radix: 16)
        let origin = quarantineMetadataOrigin(from: sourceURL) ?? ""
        return "0083;\(timestamp);Meridian Browser;\(origin)"
    }

    private func quarantineMetadataOrigin(from sourceURL: URL?) -> String? {
        guard let sourceURL,
              var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string
    }

    @discardableResult
    public func applyQuarantineMetadata(
        to fileURL: URL,
        sourceURL: URL?,
        date: Date = Date()
    ) -> Bool {
        guard fileURL.isFileURL else {
            return false
        }

        let value = quarantineMetadataValue(sourceURL: sourceURL, date: date)
        let bytes = Array(value.utf8)

        return bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return false
            }

            return fileURL.withUnsafeFileSystemRepresentation { path in
                guard let path else {
                    return false
                }

                return setxattr(path, "com.apple.quarantine", baseAddress, buffer.count, 0, 0) == 0
            }
        }
    }
}
