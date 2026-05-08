import Foundation

public struct BrowserSessionSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var profiles: [BrowserProfile]
    public var spaces: [BrowserSpace]
    public var folders: [BrowserFolder]
    public var tabs: [BrowserTab]
    public var splitViews: [SplitViewLayout]
    public var selectedSpaceID: SpaceID?
    public var selectedTabID: TabID?
    public var capturedAt: Date

    public init(
        schemaVersion: Int = 1,
        profiles: [BrowserProfile],
        spaces: [BrowserSpace],
        folders: [BrowserFolder],
        tabs: [BrowserTab],
        splitViews: [SplitViewLayout] = [],
        selectedSpaceID: SpaceID? = nil,
        selectedTabID: TabID? = nil,
        capturedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.spaces = spaces
        self.folders = folders
        self.tabs = tabs
        self.splitViews = splitViews
        self.selectedSpaceID = selectedSpaceID
        self.selectedTabID = selectedTabID
        self.capturedAt = capturedAt
    }
}
