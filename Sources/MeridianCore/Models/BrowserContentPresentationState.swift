import AppKit

@MainActor
public final class BrowserContentPresentationState: ObservableObject {
    @Published public private(set) var previewTabID: TabID?
    @Published public private(set) var previewStartPageSpaceID: SpaceID?
    @Published public private(set) var activeContentTabID: TabID?
    @Published public private(set) var snapshotHandoffIdentity: WebContentSessionIdentity?
    private var snapshotHandoffID: UUID?
    private let snapshotHandoffExpirationNanoseconds: UInt64
    private var snapshotHandoffExpirationTask: Task<Void, Never>?
    private var tabSnapshots: [WebContentSessionIdentity: NSImage] = [:]

    public var snapshotHandoffTabID: TabID? {
        snapshotHandoffIdentity?.tabID
    }

    public init(snapshotHandoffExpirationNanoseconds: UInt64 = 1_200_000_000) {
        self.snapshotHandoffExpirationNanoseconds = snapshotHandoffExpirationNanoseconds
    }

    deinit {
        snapshotHandoffExpirationTask?.cancel()
    }

    public func setPreviewTabID(_ tabID: TabID?) {
        guard previewTabID != tabID else {
            return
        }

        previewTabID = tabID
    }

    public func setPreviewStartPageSpaceID(_ spaceID: SpaceID?) {
        guard previewStartPageSpaceID != spaceID else {
            return
        }

        previewStartPageSpaceID = spaceID
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
