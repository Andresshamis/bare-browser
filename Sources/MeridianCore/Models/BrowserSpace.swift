import Foundation

public struct BrowserSpace: Identifiable, Hashable, Codable, Sendable {
    public static let defaultSymbolName = "circle.fill"
    static let legacyDefaultSymbolName = "circle.grid.2x2.fill"

    public var id: SpaceID
    public var name: String
    public var symbolName: String
    public var colorHex: String
    public var profileID: ProfileID
    public var favoriteTabIDs: [TabID]
    public var pinnedTabIDs: [TabID]
    public var folderIDs: [FolderID]
    public var regularTabIDs: [TabID]
    public var selectedTabID: TabID?
    public var lastActiveDate: Date

    public init(
        id: SpaceID = UUID(),
        name: String,
        symbolName: String = Self.defaultSymbolName,
        colorHex: String = "#4F7CAC",
        profileID: ProfileID,
        favoriteTabIDs: [TabID] = [],
        pinnedTabIDs: [TabID] = [],
        folderIDs: [FolderID] = [],
        regularTabIDs: [TabID] = [],
        selectedTabID: TabID? = nil,
        lastActiveDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.profileID = profileID
        self.favoriteTabIDs = favoriteTabIDs
        self.pinnedTabIDs = pinnedTabIDs
        self.folderIDs = folderIDs
        self.regularTabIDs = regularTabIDs
        self.selectedTabID = selectedTabID
        self.lastActiveDate = lastActiveDate
    }
}
