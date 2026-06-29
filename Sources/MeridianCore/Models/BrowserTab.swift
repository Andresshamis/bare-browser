import Foundation

public enum BrowserTabContent: Hashable, Codable, Sendable {
    case web
    case spaceCustomization(SpaceID)
    case passwordManager

    private enum CodingKeys: String, CodingKey {
        case type
        case spaceID
    }

    private enum ContentType: String, Codable {
        case web
        case spaceCustomization
        case passwordManager
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(ContentType.self, forKey: .type) ?? .web
        switch type {
        case .web:
            self = .web
        case .spaceCustomization:
            self = .spaceCustomization(try container.decode(SpaceID.self, forKey: .spaceID))
        case .passwordManager:
            self = .passwordManager
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .web:
            try container.encode(ContentType.web, forKey: .type)
        case .spaceCustomization(let spaceID):
            try container.encode(ContentType.spaceCustomization, forKey: .type)
            try container.encode(spaceID, forKey: .spaceID)
        case .passwordManager:
            try container.encode(ContentType.passwordManager, forKey: .type)
        }
    }

    public var isWeb: Bool {
        if case .web = self {
            return true
        }
        return false
    }
}

public struct BrowserTab: Identifiable, Hashable, Codable, Sendable {
    public var id: TabID
    public var title: String
    public var url: URL?
    public var faviconURL: URL?
    public var content: BrowserTabContent
    public var parentSpaceID: SpaceID
    public var parentFolderID: FolderID?
    public var isPinned: Bool
    public var isFavorite: Bool
    public var profileID: ProfileID
    public var lastActiveDate: Date
    public var isLoading: Bool
    public var isMuted: Bool
    public var splitViewID: SplitViewID?
    public var restorationMetadata: TabRestorationMetadata

    public init(
        id: TabID = UUID(),
        title: String,
        url: URL? = nil,
        faviconURL: URL? = nil,
        content: BrowserTabContent = .web,
        parentSpaceID: SpaceID,
        parentFolderID: FolderID? = nil,
        isPinned: Bool = false,
        isFavorite: Bool = false,
        profileID: ProfileID,
        lastActiveDate: Date = Date(),
        isLoading: Bool = false,
        isMuted: Bool = false,
        splitViewID: SplitViewID? = nil,
        restorationMetadata: TabRestorationMetadata = .init()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.faviconURL = faviconURL
        self.content = content
        self.parentSpaceID = parentSpaceID
        self.parentFolderID = parentFolderID
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.profileID = profileID
        self.lastActiveDate = lastActiveDate
        self.isLoading = isLoading
        self.isMuted = isMuted
        self.splitViewID = splitViewID
        self.restorationMetadata = restorationMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case faviconURL
        case content
        case parentSpaceID
        case parentFolderID
        case isPinned
        case isFavorite
        case profileID
        case lastActiveDate
        case isLoading
        case isMuted
        case splitViewID
        case restorationMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(TabID.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            url: try container.decodeIfPresent(URL.self, forKey: .url),
            faviconURL: try container.decodeIfPresent(URL.self, forKey: .faviconURL),
            content: try container.decodeIfPresent(BrowserTabContent.self, forKey: .content) ?? .web,
            parentSpaceID: try container.decode(SpaceID.self, forKey: .parentSpaceID),
            parentFolderID: try container.decodeIfPresent(FolderID.self, forKey: .parentFolderID),
            isPinned: try container.decode(Bool.self, forKey: .isPinned),
            isFavorite: try container.decode(Bool.self, forKey: .isFavorite),
            profileID: try container.decode(ProfileID.self, forKey: .profileID),
            lastActiveDate: try container.decodeIfPresent(Date.self, forKey: .lastActiveDate) ?? Date(),
            isLoading: try container.decodeIfPresent(Bool.self, forKey: .isLoading) ?? false,
            isMuted: try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false,
            splitViewID: try container.decodeIfPresent(SplitViewID.self, forKey: .splitViewID),
            restorationMetadata: try container.decodeIfPresent(
                TabRestorationMetadata.self,
                forKey: .restorationMetadata
            ) ?? .init()
        )
    }
}

public enum BrowserTabPlacement: String, Equatable, Sendable {
    case regular
    case pinned
    case favorite

    public var title: String {
        switch self {
        case .regular:
            return "Tabs"
        case .pinned:
            return "Pinned"
        case .favorite:
            return "Essentials"
        }
    }
}

public enum BrowserTabReorderDirection: String, Equatable, Sendable {
    case up
    case down

    public var title: String {
        switch self {
        case .up:
            return "Up"
        case .down:
            return "Down"
        }
    }
}

public struct TabRestorationMetadata: Hashable, Codable, Sendable {
    public var estimatedScrollPosition: Double?
    public var backForwardListHint: [URL]
    public var lastCommittedURL: URL?
    public var pendingHTTPFallbackURL: URL?

    public init(
        estimatedScrollPosition: Double? = nil,
        backForwardListHint: [URL] = [],
        lastCommittedURL: URL? = nil,
        pendingHTTPFallbackURL: URL? = nil
    ) {
        self.estimatedScrollPosition = estimatedScrollPosition
        self.backForwardListHint = backForwardListHint
        self.lastCommittedURL = lastCommittedURL
        self.pendingHTTPFallbackURL = pendingHTTPFallbackURL
    }
}
