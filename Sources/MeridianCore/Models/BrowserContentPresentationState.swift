import AppKit

@MainActor
public final class BrowserContentPresentationState: ObservableObject {
    @Published public private(set) var previewTabID: TabID?
    @Published public private(set) var previewStartPageSpaceID: SpaceID?
    @Published public private(set) var activeContentTabID: TabID?
    @Published public private(set) var snapshotHandoffTabID: TabID?
    private var snapshotHandoffID: UUID?
    private var tabSnapshots: [TabID: NSImage] = [:]

    public init() {}

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
    public func beginSnapshotHandoff(to tabID: TabID?) -> UUID? {
        guard let tabID,
              tabSnapshots[tabID] != nil else {
            clearSnapshotHandoff()
            return nil
        }

        let handoffID = UUID()
        snapshotHandoffID = handoffID
        snapshotHandoffTabID = tabID
        return handoffID
    }

    public func snapshotHandoffToken(for tabID: TabID) -> UUID? {
        guard snapshotHandoffTabID == tabID else {
            return nil
        }

        return snapshotHandoffID
    }

    public func completeSnapshotHandoff(_ handoffID: UUID?, for tabID: TabID) {
        guard snapshotHandoffID == handoffID,
              snapshotHandoffTabID == tabID else {
            return
        }

        clearSnapshotHandoff()
    }

    public func clearSnapshotHandoff() {
        snapshotHandoffID = nil
        snapshotHandoffTabID = nil
    }

    public func storeSnapshot(_ image: NSImage, for tabID: TabID) {
        guard image.isValid,
              image.size.width > 0,
              image.size.height > 0 else {
            return
        }

        if previewTabID == tabID && activeContentTabID != tabID {
            objectWillChange.send()
        }
        tabSnapshots[tabID] = image
    }

    public func snapshot(for tabID: TabID?) -> NSImage? {
        guard let tabID else {
            return nil
        }

        return tabSnapshots[tabID]
    }

    public func removeSnapshots(keeping tabIDs: Set<TabID>) {
        tabSnapshots = tabSnapshots.filter { tabIDs.contains($0.key) }
        if let snapshotHandoffTabID,
           !tabIDs.contains(snapshotHandoffTabID) {
            clearSnapshotHandoff()
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

            return tab.parentSpaceID == space.id && tab.profileID == space.profileID
        }
    }
}
