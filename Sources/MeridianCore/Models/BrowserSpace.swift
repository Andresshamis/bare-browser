import Foundation

public enum SidebarTintSource: String, Codable, Hashable, Sendable {
    case spaceColor
    case custom
}

public struct SidebarGlassSettings: Hashable, Codable, Sendable {
    public static let standard = SidebarGlassSettings(
        glassOpacity: 0.60,
        tintOpacity: 0,
        colorNoiseLevel: 0,
        colorNoiseScale: 0,
        edgeOpacity: 0.40,
        shadowOpacity: 0.20,
        highlightOpacity: 0.20
    )

    public var glassOpacity: Double
    public var tintOpacity: Double
    public var colorNoiseLevel: Double
    public var colorNoiseScale: Double
    public var edgeOpacity: Double
    public var shadowOpacity: Double
    public var highlightOpacity: Double

    public init(
        glassOpacity: Double,
        tintOpacity: Double,
        colorNoiseLevel: Double = 0,
        colorNoiseScale: Double = 0,
        edgeOpacity: Double,
        shadowOpacity: Double,
        highlightOpacity: Double
    ) {
        self.glassOpacity = Self.clamped(glassOpacity)
        self.tintOpacity = Self.clamped(tintOpacity)
        self.colorNoiseLevel = Self.clamped(colorNoiseLevel)
        self.colorNoiseScale = Self.clamped(colorNoiseScale)
        self.edgeOpacity = Self.clamped(edgeOpacity)
        self.shadowOpacity = Self.clamped(shadowOpacity)
        self.highlightOpacity = Self.clamped(highlightOpacity)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private enum CodingKeys: String, CodingKey {
        case glassOpacity
        case tintOpacity
        case colorNoiseLevel
        case colorNoiseScale
        case edgeOpacity
        case shadowOpacity
        case highlightOpacity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            glassOpacity: try container.decodeIfPresent(Double.self, forKey: .glassOpacity) ?? Self.standard.glassOpacity,
            tintOpacity: try container.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? Self.standard.tintOpacity,
            colorNoiseLevel: try container.decodeIfPresent(Double.self, forKey: .colorNoiseLevel) ?? Self.standard.colorNoiseLevel,
            colorNoiseScale: try container.decodeIfPresent(Double.self, forKey: .colorNoiseScale) ?? Self.standard.colorNoiseScale,
            edgeOpacity: try container.decodeIfPresent(Double.self, forKey: .edgeOpacity) ?? Self.standard.edgeOpacity,
            shadowOpacity: try container.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? Self.standard.shadowOpacity,
            highlightOpacity: try container.decodeIfPresent(Double.self, forKey: .highlightOpacity) ?? Self.standard.highlightOpacity
        )
    }
}

public struct SidebarAppearance: Hashable, Codable, Sendable {
    public static let standard = SidebarAppearance()

    public var tintSource: SidebarTintSource
    public var tintHex: String
    public var base: SidebarGlassSettings
    public var pinnedOverride: SidebarGlassSettings?

    public init(
        tintSource: SidebarTintSource = .spaceColor,
        tintHex: String = "#4F7CAC",
        base: SidebarGlassSettings = .standard,
        pinnedOverride: SidebarGlassSettings? = nil
    ) {
        self.tintSource = tintSource
        self.tintHex = tintHex
        self.base = base
        self.pinnedOverride = pinnedOverride
    }

    public var pinnedSettings: SidebarGlassSettings {
        pinnedOverride ?? base
    }

    public func tintHex(forSpaceColorHex spaceColorHex: String) -> String {
        switch tintSource {
        case .spaceColor:
            return spaceColorHex
        case .custom:
            return tintHex
        }
    }
}

public struct BrowserSpace: Identifiable, Hashable, Codable, Sendable {
    public static let defaultSymbolName = "circle.fill"
    static let legacyDefaultSymbolName = "circle.grid.2x2.fill"

    public var id: SpaceID
    public var name: String
    public var symbolName: String
    public var colorHex: String
    public var sidebarAppearance: SidebarAppearance
    public internal(set) var profileID: ProfileID
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
        sidebarAppearance: SidebarAppearance = .standard,
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
        self.sidebarAppearance = sidebarAppearance
        self.profileID = profileID
        self.favoriteTabIDs = favoriteTabIDs
        self.pinnedTabIDs = pinnedTabIDs
        self.folderIDs = folderIDs
        self.regularTabIDs = regularTabIDs
        self.selectedTabID = selectedTabID
        self.lastActiveDate = lastActiveDate
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case symbolName
        case colorHex
        case sidebarAppearance
        case profileID
        case favoriteTabIDs
        case pinnedTabIDs
        case folderIDs
        case regularTabIDs
        case selectedTabID
        case lastActiveDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SpaceID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? Self.defaultSymbolName
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#4F7CAC"
        sidebarAppearance = try container.decodeIfPresent(SidebarAppearance.self, forKey: .sidebarAppearance) ?? .standard
        profileID = try container.decode(ProfileID.self, forKey: .profileID)
        favoriteTabIDs = try container.decodeIfPresent([TabID].self, forKey: .favoriteTabIDs) ?? []
        pinnedTabIDs = try container.decodeIfPresent([TabID].self, forKey: .pinnedTabIDs) ?? []
        folderIDs = try container.decodeIfPresent([FolderID].self, forKey: .folderIDs) ?? []
        regularTabIDs = try container.decodeIfPresent([TabID].self, forKey: .regularTabIDs) ?? []
        selectedTabID = try container.decodeIfPresent(TabID.self, forKey: .selectedTabID)
        lastActiveDate = try container.decodeIfPresent(Date.self, forKey: .lastActiveDate) ?? Date()
    }
}
