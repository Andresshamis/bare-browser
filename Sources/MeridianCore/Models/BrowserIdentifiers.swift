import Foundation

public typealias TabID = UUID
public typealias SpaceID = UUID
public typealias FolderID = UUID
public typealias ProfileID = UUID
public typealias SplitViewID = UUID

public enum SidebarItemID: Hashable, Sendable {
    case favorite(TabID)
    case pinned(TabID)
    case folder(FolderID)
    case tab(TabID)
}
