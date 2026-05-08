import Foundation

public struct BrowserProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: ProfileID
    public var name: String
    public var colorHex: String
    public private(set) var websiteDataStoreID: UUID?
    public var isEphemeral: Bool
    public var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex
        case websiteDataStoreID
        case isEphemeral
        case createdAt
    }

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
        self.websiteDataStoreID = isEphemeral ? nil : websiteDataStoreID ?? id
        self.isEphemeral = isEphemeral
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(ProfileID.self, forKey: .id)
        let isEphemeral = try container.decode(Bool.self, forKey: .isEphemeral)

        self.init(
            id: id,
            name: try container.decode(String.self, forKey: .name),
            colorHex: try container.decode(String.self, forKey: .colorHex),
            websiteDataStoreID: try container.decodeIfPresent(UUID.self, forKey: .websiteDataStoreID),
            isEphemeral: isEphemeral,
            createdAt: try container.decode(Date.self, forKey: .createdAt)
        )
    }

    public var persistentWebsiteDataStoreID: UUID? {
        isEphemeral ? nil : websiteDataStoreID
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
