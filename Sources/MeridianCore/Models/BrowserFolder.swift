import Foundation

public struct BrowserFolder: Identifiable, Hashable, Codable, Sendable {
    public var id: FolderID
    public var name: String
    public var parentSpaceID: SpaceID
    public var parentFolderID: FolderID?
    public var childFolderIDs: [FolderID]
    public var tabIDs: [TabID]
    public var isCollapsed: Bool
    public var createdAt: Date

    public init(
        id: FolderID = UUID(),
        name: String,
        parentSpaceID: SpaceID,
        parentFolderID: FolderID? = nil,
        childFolderIDs: [FolderID] = [],
        tabIDs: [TabID] = [],
        isCollapsed: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parentSpaceID = parentSpaceID
        self.parentFolderID = parentFolderID
        self.childFolderIDs = childFolderIDs
        self.tabIDs = tabIDs
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
    }
}
