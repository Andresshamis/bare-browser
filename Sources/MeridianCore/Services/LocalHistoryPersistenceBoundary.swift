import Foundation

public enum LocalHistoryPersistenceBoundary {
    public static func persistentEntries(
        from entries: [BrowserHistoryEntry],
        profiles: [BrowserProfile]
    ) -> [BrowserHistoryEntry] {
        let persistentProfileIDs = Set(
            profiles
                .filter { !$0.isEphemeral }
                .map(\.id)
        )

        return LocalHistoryStore(
            entries: entries,
            allowedProfileIDs: persistentProfileIDs
        ).entries
    }
}
