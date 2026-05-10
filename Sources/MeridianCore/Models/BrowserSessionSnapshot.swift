import Foundation

public struct BrowserSessionSnapshot: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profiles
        case spaces
        case folders
        case tabs
        case splitViews
        case selectedSpaceID
        case selectedTabID
        case capturedAt
        case sitePermissionSettings
    }

    public var schemaVersion: Int
    public var profiles: [BrowserProfile]
    public var spaces: [BrowserSpace]
    public var folders: [BrowserFolder]
    public var tabs: [BrowserTab]
    public var splitViews: [SplitViewLayout]
    public var selectedSpaceID: SpaceID?
    public var selectedTabID: TabID?
    public var capturedAt: Date
    public var sitePermissionSettings: [SitePermissionSetting]

    public init(
        schemaVersion: Int = 1,
        profiles: [BrowserProfile],
        spaces: [BrowserSpace],
        folders: [BrowserFolder],
        tabs: [BrowserTab],
        splitViews: [SplitViewLayout] = [],
        selectedSpaceID: SpaceID? = nil,
        selectedTabID: TabID? = nil,
        capturedAt: Date = Date(),
        sitePermissionSettings: [SitePermissionSetting] = []
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
        self.sitePermissionSettings = sitePermissionSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.profiles = try container.decode([BrowserProfile].self, forKey: .profiles)
        self.spaces = try container.decode([BrowserSpace].self, forKey: .spaces)
        self.folders = try container.decode([BrowserFolder].self, forKey: .folders)
        self.tabs = try container.decode([BrowserTab].self, forKey: .tabs)
        self.splitViews = try container.decode([SplitViewLayout].self, forKey: .splitViews)
        self.selectedSpaceID = try container.decodeIfPresent(SpaceID.self, forKey: .selectedSpaceID)
        self.selectedTabID = try container.decodeIfPresent(TabID.self, forKey: .selectedTabID)
        self.capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        self.sitePermissionSettings = try container.decodeIfPresent(
            [SitePermissionSetting].self,
            forKey: .sitePermissionSettings
        ) ?? []
    }
}
