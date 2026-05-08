import Foundation

public enum SessionSnapshotFactory {
    public static func initial(date: Date = Date()) -> BrowserSessionSnapshot {
        let profile = BrowserProfile(
            id: UUID(uuidString: "A0B97C4C-0E21-4B4E-A09C-B7C8B37C2601")!,
            name: "Personal",
            colorHex: "#4F7CAC",
            websiteDataStoreID: UUID(uuidString: "BDE1E51C-694D-4E4C-A64E-9014F2FE51CF")!,
            createdAt: date
        )
        let space = BrowserSpace(
            id: UUID(uuidString: "E7F390AB-B64B-4E32-944E-B2DD8BC85F2E")!,
            name: "Today",
            symbolName: "sparkle.magnifyingglass",
            colorHex: "#4F7CAC",
            profileID: profile.id,
            lastActiveDate: date
        )
        let welcomeTab = BrowserTab(
            id: UUID(uuidString: "C9C267E3-C314-4F10-A69D-C03CBA3B533F")!,
            title: "Start Page",
            url: URL(string: "https://www.apple.com"),
            parentSpaceID: space.id,
            isFavorite: true,
            profileID: profile.id,
            lastActiveDate: date,
            restorationMetadata: TabRestorationMetadata(lastCommittedURL: URL(string: "https://www.apple.com"))
        )
        var seededSpace = space
        seededSpace.favoriteTabIDs = [welcomeTab.id]
        seededSpace.selectedTabID = welcomeTab.id

        return BrowserSessionSnapshot(
            profiles: [profile],
            spaces: [seededSpace],
            folders: [],
            tabs: [welcomeTab],
            selectedSpaceID: seededSpace.id,
            selectedTabID: welcomeTab.id,
            capturedAt: date
        )
    }
}
