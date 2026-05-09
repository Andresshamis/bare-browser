import Foundation

public struct LocalHistoryStore: Sendable {
    public private(set) var entries: [BrowserHistoryEntry]

    public init(entries: [BrowserHistoryEntry] = []) {
        self.entries = entries.compactMap { entry in
            guard let normalizedURL = Self.normalizedHistoryURL(entry.url) else {
                return nil
            }

            var normalizedEntry = entry
            normalizedEntry.url = normalizedURL
            return normalizedEntry
        }
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
            return entries[index]
        }

        let entry = BrowserHistoryEntry(
            profileID: profile.id,
            url: normalizedURL,
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
}
