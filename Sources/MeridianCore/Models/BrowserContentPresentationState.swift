import AppKit

enum BrowserContentPagerPreviewTarget: Equatable, Sendable {
    case activity
    case space
    case tab(TabID)
    case startPage(SpaceID)
}

@MainActor
public final class BrowserContentPresentationState: ObservableObject {
    @Published private(set) var pagerPreviewTarget: BrowserContentPagerPreviewTarget?
    @Published public private(set) var activeContentTabID: TabID?
    @Published public private(set) var snapshotHandoffIdentity: WebContentSessionIdentity?
    private var snapshotHandoffID: UUID?
    private let snapshotHandoffExpirationNanoseconds: UInt64
    private var snapshotHandoffExpirationTask: Task<Void, Never>?
    private var tabSnapshots: [WebContentSessionIdentity: NSImage] = [:]

    public var snapshotHandoffTabID: TabID? {
        snapshotHandoffIdentity?.tabID
    }

    public var previewTabID: TabID? {
        guard case .tab(let tabID) = pagerPreviewTarget else {
            return nil
        }
        return tabID
    }

    public var previewStartPageSpaceID: SpaceID? {
        guard case .startPage(let spaceID) = pagerPreviewTarget else {
            return nil
        }
        return spaceID
    }

    // nil follows the committed selection; true/false follows the live pager target.
    var activityPagePreviewOverride: Bool? {
        guard let pagerPreviewTarget else {
            return nil
        }
        return pagerPreviewTarget == .activity
    }

    public init(snapshotHandoffExpirationNanoseconds: UInt64 = 1_200_000_000) {
        self.snapshotHandoffExpirationNanoseconds = snapshotHandoffExpirationNanoseconds
    }

    deinit {
        snapshotHandoffExpirationTask?.cancel()
    }

    func setPagerPreviewTarget(_ target: BrowserContentPagerPreviewTarget?) {
        guard pagerPreviewTarget != target else {
            return
        }
        pagerPreviewTarget = target
    }

    public func setPreviewTabID(_ tabID: TabID?) {
        if let tabID {
            setPagerPreviewTarget(.tab(tabID))
        } else if case .tab = pagerPreviewTarget {
            setPagerPreviewTarget(nil)
        }
    }

    public func setPreviewStartPageSpaceID(_ spaceID: SpaceID?) {
        if let spaceID {
            setPagerPreviewTarget(.startPage(spaceID))
        } else if case .startPage = pagerPreviewTarget {
            setPagerPreviewTarget(nil)
        }
    }

    func setActivityPagePreviewOverride(_ isPresented: Bool?) {
        switch isPresented {
        case true:
            setPagerPreviewTarget(.activity)
        case false:
            setPagerPreviewTarget(.space)
        case nil:
            setPagerPreviewTarget(nil)
        }
    }

    public func setActiveContentTabID(_ tabID: TabID?) {
        guard activeContentTabID != tabID else {
            return
        }

        activeContentTabID = tabID
    }

    @discardableResult
    public func beginSnapshotHandoff(to identity: WebContentSessionIdentity?) -> UUID? {
        guard let identity,
              tabSnapshots[identity] != nil else {
            clearSnapshotHandoff()
            return nil
        }

        let handoffID = UUID()
        snapshotHandoffID = handoffID
        snapshotHandoffIdentity = identity
        scheduleSnapshotHandoffExpiration(handoffID, identity: identity)
        return handoffID
    }

    public func snapshotHandoffToken(for identity: WebContentSessionIdentity) -> UUID? {
        guard snapshotHandoffIdentity == identity else {
            return nil
        }

        return snapshotHandoffID
    }

    public func completeSnapshotHandoff(
        _ handoffID: UUID?,
        for identity: WebContentSessionIdentity
    ) {
        guard snapshotHandoffID == handoffID,
              snapshotHandoffIdentity == identity else {
            return
        }

        clearSnapshotHandoff()
    }

    public func clearSnapshotHandoff() {
        snapshotHandoffExpirationTask?.cancel()
        snapshotHandoffExpirationTask = nil
        snapshotHandoffID = nil
        snapshotHandoffIdentity = nil
    }

    public func storeSnapshot(_ image: NSImage, for identity: WebContentSessionIdentity) {
        guard image.isValid,
              image.size.width > 0,
              image.size.height > 0 else {
            return
        }

        if previewTabID == identity.tabID && activeContentTabID != identity.tabID {
            objectWillChange.send()
        }
        tabSnapshots = tabSnapshots.filter { $0.key.tabID != identity.tabID }
        tabSnapshots[identity] = image
    }

    public func snapshot(for identity: WebContentSessionIdentity?) -> NSImage? {
        guard let identity else {
            return nil
        }

        return tabSnapshots[identity]
    }

    public func removeSnapshots(keeping identities: Set<WebContentSessionIdentity>) {
        tabSnapshots = tabSnapshots.filter { identities.contains($0.key) }
        if let snapshotHandoffIdentity,
           !identities.contains(snapshotHandoffIdentity) {
            clearSnapshotHandoff()
        }
    }

    public func removeSnapshot(for tabID: TabID) {
        tabSnapshots = tabSnapshots.filter { $0.key.tabID != tabID }
        if snapshotHandoffIdentity?.tabID == tabID {
            clearSnapshotHandoff()
        }
    }

    private func scheduleSnapshotHandoffExpiration(
        _ handoffID: UUID,
        identity: WebContentSessionIdentity
    ) {
        snapshotHandoffExpirationTask?.cancel()
        snapshotHandoffExpirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.snapshotHandoffExpirationNanoseconds ?? 0)
            guard !Task.isCancelled else {
                return
            }

            self?.completeSnapshotHandoff(handoffID, for: identity)
        }
    }
}

struct BrowserActivityPagePresentation {
    static func isPresented(
        isSelected: Bool,
        previewOverride: Bool?
    ) -> Bool {
        previewOverride ?? isSelected
    }
}

struct BrowserContentPreviewPlaceholder {
    static func shouldShow(
        for previewTab: BrowserTab?,
        selectedTabID: TabID?,
        snapshotIsAvailable: Bool
    ) -> Bool {
        guard let previewTab,
              previewTab.id != selectedTabID,
              previewTab.content.isWeb,
              previewTab.url != nil else {
            return false
        }

        return !snapshotIsAvailable
    }
}

struct BrowserSpaceFocusedTabResolver {
    static func focusedTabID(
        for space: BrowserSpace,
        folders: [BrowserFolder],
        tabsByID: [TabID: BrowserTab]
    ) -> TabID? {
        let folderTabIDs = folders.flatMap(\.tabIDs)
        let candidateIDs = [space.selectedTabID].compactMap { $0 }
            + space.favoriteTabIDs
            + space.pinnedTabIDs
            + space.regularTabIDs
            + folderTabIDs

        return candidateIDs.first { candidateID in
            guard let tab = tabsByID[candidateID] else {
                return false
            }

            return tab.parentSpaceID == space.id
        }
    }
}
