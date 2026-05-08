import Foundation

public struct BrowserProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: ProfileID
    public var name: String
    public var colorHex: String
    public var websiteDataStoreID: UUID?
    public var isEphemeral: Bool
    public var createdAt: Date

    public init(
        id: ProfileID = UUID(),
        name: String,
        colorHex: String = "#6B8F71",
        websiteDataStoreID: UUID? = UUID(),
        isEphemeral: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.websiteDataStoreID = isEphemeral ? nil : websiteDataStoreID
        self.isEphemeral = isEphemeral
        self.createdAt = createdAt
    }

    public static func privateBrowsing(id: ProfileID = UUID()) -> BrowserProfile {
        BrowserProfile(
            id: id,
            name: "Private",
            colorHex: "#5E5CE6",
            websiteDataStoreID: nil,
            isEphemeral: true
        )
    }
}
