import Foundation

public struct LocalHistoryStore: Sendable {
    public private(set) var entries: [BrowserHistoryEntry]

    public init(entries: [BrowserHistoryEntry] = []) {
        self.entries = entries.filter { Self.isRecordable($0.url) }
    }

    @discardableResult
    public mutating func recordVisit(
        url: URL,
        title: String?,
        profile: BrowserProfile,
        visitedAt: Date = Date()
    ) -> BrowserHistoryEntry? {
        guard !profile.isEphemeral, Self.isRecordable(url) else {
            return nil
        }

        let resolvedTitle = Self.resolvedTitle(title, for: url)
        if let index = entries.firstIndex(where: { $0.profileID == profile.id && $0.url == url }) {
            entries[index].title = resolvedTitle
            entries[index].lastVisitedAt = visitedAt
            entries[index].visitCount += 1
            return entries[index]
        }

        let entry = BrowserHistoryEntry(
            profileID: profile.id,
            url: url,
            title: resolvedTitle,
            lastVisitedAt: visitedAt
        )
        entries.append(entry)
        return entry
    }

    public func query(_ query: String, profileID: ProfileID, limit: Int = 5) -> [BrowserHistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else {
            return []
        }

        return Array(
            entries
                .filter { entry in
                    entry.profileID == profileID
                        && (
                            entry.title.localizedCaseInsensitiveContains(trimmed)
                                || entry.url.absoluteString.localizedCaseInsensitiveContains(trimmed)
                                || entry.displayHost.localizedCaseInsensitiveContains(trimmed)
                        )
                }
                .sorted { lhs, rhs in
                    if lhs.lastVisitedAt == rhs.lastVisitedAt {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    }
                    return lhs.lastVisitedAt > rhs.lastVisitedAt
                }
                .prefix(limit)
        )
    }

    public static func isRecordable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private static func resolvedTitle(_ title: String?, for url: URL) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return url.host(percentEncoded: false) ?? url.absoluteString
    }
}
