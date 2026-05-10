import Foundation

public struct BrowserTab: Identifiable, Hashable, Codable, Sendable {
    public var id: TabID
    public var title: String
    public var url: URL?
    public var faviconURL: URL?
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

public struct TabRestorationMetadata: Hashable, Codable, Sendable {
    public var estimatedScrollPosition: Double?
    public var backForwardListHint: [URL]
    public var lastCommittedURL: URL?

    public init(
        estimatedScrollPosition: Double? = nil,
        backForwardListHint: [URL] = [],
        lastCommittedURL: URL? = nil
    ) {
        self.estimatedScrollPosition = estimatedScrollPosition
        self.backForwardListHint = backForwardListHint
        self.lastCommittedURL = lastCommittedURL
    }
}
