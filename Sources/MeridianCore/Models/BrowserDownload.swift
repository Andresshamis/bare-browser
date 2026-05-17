import Foundation

public enum BrowserDownloadState: String, Codable, Sendable {
    case waitingForDestination
    case downloading
    case finished
    case failed
    case canceled

    public var isActive: Bool {
        switch self {
        case .waitingForDestination, .downloading:
            return true
        case .finished, .failed, .canceled:
            return false
        }
    }
}

public struct BrowserDownload: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var filename: String
    public var sourceDescription: String
    public var destinationURL: URL?
    public var state: BrowserDownloadState
    public var progress: Double?
    public var startedAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var failureMessage: String?

    public init(
        id: UUID = UUID(),
        filename: String,
        sourceDescription: String,
        destinationURL: URL? = nil,
        state: BrowserDownloadState,
        progress: Double? = nil,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.sourceDescription = sourceDescription
        self.destinationURL = destinationURL
        self.state = state
        self.progress = Self.normalizedProgress(progress)
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.failureMessage = failureMessage
    }

    public var progressPercent: Int? {
        progress.map { Int(($0 * 100).rounded()) }
    }

    public static func normalizedProgress(_ progress: Double?) -> Double? {
        guard let progress, progress.isFinite else {
            return nil
        }

        return min(max(progress, 0), 1)
    }
}
