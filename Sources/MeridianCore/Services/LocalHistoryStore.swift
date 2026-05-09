import Foundation

public struct LocalHistoryStore: Sendable {
    public private(set) var entries: [BrowserHistoryEntry]

    public init(entries: [BrowserHistoryEntry] = [], allowedProfileIDs: Set<ProfileID>? = nil) {
        var mergedEntries: [HistoryKey: BrowserHistoryEntry] = [:]

        for entry in entries {
            if let allowedProfileIDs, !allowedProfileIDs.contains(entry.profileID) {
                continue
            }

            guard let normalizedURL = Self.normalizedHistoryURL(entry.url) else {
                continue
            }

            var normalizedEntry = entry
            normalizedEntry.url = normalizedURL
            normalizedEntry.title = Self.resolvedTitle(entry.title, for: normalizedURL)
            normalizedEntry.visitCount = max(1, entry.visitCount)

            let key = HistoryKey(profileID: entry.profileID, urlString: normalizedURL.absoluteString)
            if let existingEntry = mergedEntries[key] {
                mergedEntries[key] = Self.mergedEntry(existingEntry, normalizedEntry)
            } else {
                mergedEntries[key] = normalizedEntry
            }
        }

        self.entries = Self.sortedEntries(Array(mergedEntries.values))
    }

    @discardableResult
    public mutating func recordVisit(
        url: URL,
        title: String?,
        profile: BrowserProfile,
        visitedAt: Date = Date()
    ) -> BrowserHistoryEntry? {
        guard !profile.isEphemeral,
              let normalizedURL = Self.normalizedHistoryURL(url) else {
            return nil
        }

        let resolvedTitle = Self.resolvedTitle(title, for: normalizedURL)
        if let index = entries.firstIndex(where: { $0.profileID == profile.id && $0.url == normalizedURL }) {
            entries[index].title = resolvedTitle
            entries[index].lastVisitedAt = visitedAt
            entries[index].visitCount += 1
            let updatedEntry = entries[index]
            entries = Self.sortedEntries(entries)
            return updatedEntry
        }

        let entry = BrowserHistoryEntry(
            profileID: profile.id,
            url: normalizedURL,
            title: resolvedTitle,
            lastVisitedAt: visitedAt
        )
        entries.append(entry)
        entries = Self.sortedEntries(entries)
        return entry
    }

    @discardableResult
    public mutating func deleteEntry(id: UUID, profileID: ProfileID? = nil) -> BrowserHistoryEntry? {
        guard let index = entries.firstIndex(where: { entry in
            entry.id == id && (profileID == nil || entry.profileID == profileID)
        }) else {
            return nil
        }

        return entries.remove(at: index)
    }

    @discardableResult
    public mutating func clearEntries(profileID: ProfileID) -> [BrowserHistoryEntry] {
        let removedEntries = entries.filter { $0.profileID == profileID }
        entries.removeAll { $0.profileID == profileID }
        return removedEntries
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

    private static func normalizedHistoryURL(_ url: URL) -> URL? {
        guard isRecordable(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else {
            return nil
        }

        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.fragment = nil

        if let queryItems = components.queryItems {
            let retainedItems = queryItems.filter { !isSensitiveQueryItemName($0.name) }
            components.queryItems = retainedItems.isEmpty ? nil : retainedItems
        }

        return components.url
    }

    private static func mergedEntry(
        _ lhs: BrowserHistoryEntry,
        _ rhs: BrowserHistoryEntry
    ) -> BrowserHistoryEntry {
        let preferredEntry = preferredEntry(lhs, rhs)
        return BrowserHistoryEntry(
            id: preferredEntry.id,
            profileID: preferredEntry.profileID,
            url: preferredEntry.url,
            title: resolvedTitle(preferredEntry.title, for: preferredEntry.url),
            lastVisitedAt: max(lhs.lastVisitedAt, rhs.lastVisitedAt),
            visitCount: max(1, lhs.visitCount) + max(1, rhs.visitCount)
        )
    }

    private static func preferredEntry(
        _ lhs: BrowserHistoryEntry,
        _ rhs: BrowserHistoryEntry
    ) -> BrowserHistoryEntry {
        if lhs.lastVisitedAt != rhs.lastVisitedAt {
            return lhs.lastVisitedAt > rhs.lastVisitedAt ? lhs : rhs
        }

        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending ? lhs : rhs
        }

        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    private static func sortedEntries(_ entries: [BrowserHistoryEntry]) -> [BrowserHistoryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.lastVisitedAt != rhs.lastVisitedAt {
                return lhs.lastVisitedAt > rhs.lastVisitedAt
            }
            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            if lhs.url.absoluteString != rhs.url.absoluteString {
                return lhs.url.absoluteString < rhs.url.absoluteString
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func resolvedTitle(_ title: String?, for url: URL) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return url.host(percentEncoded: false) ?? url.absoluteString
    }

    private static func isSensitiveQueryItemName(_ name: String) -> Bool {
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        guard !normalizedName.isEmpty else {
            return false
        }

        if normalizedName.contains("token")
            || normalizedName.contains("password")
            || normalizedName.contains("passwd")
            || normalizedName.contains("secret")
            || normalizedName.contains("credential")
            || normalizedName.contains("session")
            || normalizedName.contains("signature")
            || normalizedName == "sig"
            || normalizedName == "auth"
            || normalizedName.hasPrefix("auth_")
            || normalizedName.hasSuffix("_auth")
            || normalizedName == "jwt"
            || normalizedName == "api_key"
            || normalizedName == "apikey" {
            return true
        }

        return false
    }

    private struct HistoryKey: Hashable {
        var profileID: ProfileID
        var urlString: String
    }
}
