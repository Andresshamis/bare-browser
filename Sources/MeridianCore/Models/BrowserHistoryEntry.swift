import Foundation

public struct BrowserHistoryEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var profileID: ProfileID
    public var url: URL
    public var title: String
    public var lastVisitedAt: Date
    public var visitCount: Int

    public init(
        id: UUID = UUID(),
        profileID: ProfileID,
        url: URL,
        title: String,
        lastVisitedAt: Date = Date(),
        visitCount: Int = 1
    ) {
        self.id = id
        self.profileID = profileID
        self.url = url
        self.title = title
        self.lastVisitedAt = lastVisitedAt
        self.visitCount = max(1, visitCount)
    }

    public var displayHost: String {
        url.host(percentEncoded: false) ?? url.scheme ?? url.absoluteString
    }
}
