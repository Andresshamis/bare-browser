import Foundation
import MeridianCore
import XCTest

final class LocalHistoryStoreTests: XCTestCase {
    func testRecordsPublicProfileVisitAndUpdatesExistingURL() throws {
        let profile = BrowserProfile(name: "Work")
        let url = URL(string: "https://example.com/docs")!
        var historyStore = LocalHistoryStore()

        let firstEntry = try XCTUnwrap(
            historyStore.recordVisit(
                url: url,
                title: "Docs",
                profile: profile,
                visitedAt: Date(timeIntervalSince1970: 10)
            )
        )
        let updatedEntry = try XCTUnwrap(
            historyStore.recordVisit(
                url: url,
                title: "Updated Docs",
                profile: profile,
                visitedAt: Date(timeIntervalSince1970: 20)
            )
        )

        XCTAssertEqual(firstEntry.id, updatedEntry.id)
        XCTAssertEqual(historyStore.entries.count, 1)
        XCTAssertEqual(historyStore.entries[0].title, "Updated Docs")
        XCTAssertEqual(historyStore.entries[0].visitCount, 2)
        XCTAssertEqual(historyStore.entries[0].lastVisitedAt, Date(timeIntervalSince1970: 20))
    }

    func testPrivateProfileAndNonWebURLsAreIgnored() {
        let privateProfile = BrowserProfile.privateBrowsing()
        let publicProfile = BrowserProfile(name: "Personal")
        var historyStore = LocalHistoryStore()

        historyStore.recordVisit(
            url: URL(string: "https://private.example/secret?token=fixture")!,
            title: "Private",
            profile: privateProfile
        )
        historyStore.recordVisit(
            url: URL(string: "file:///Users/example/secret.html")!,
            title: "Local File",
            profile: publicProfile
        )
        historyStore.recordVisit(
            url: URL(string: "mailto:hello@example.com")!,
            title: "Mail",
            profile: publicProfile
        )

        XCTAssertTrue(historyStore.entries.isEmpty)
    }

    func testRecordVisitNormalizesSensitiveURLComponentsBeforeRetention() throws {
        let profile = BrowserProfile(name: "Work")
        let url = URL(string: "https://user:pass@example.com/docs?view=full&token=fixture#secret-section")!
        var historyStore = LocalHistoryStore()

        let entry = try XCTUnwrap(
            historyStore.recordVisit(
                url: url,
                title: "Docs",
                profile: profile
            )
        )

        XCTAssertEqual(entry.url.absoluteString, "https://example.com/docs?view=full")
        XCTAssertNil(entry.url.user(percentEncoded: false))
        XCTAssertNil(entry.url.password(percentEncoded: false))
        XCTAssertNil(URLComponents(url: entry.url, resolvingAgainstBaseURL: false)?.fragment)

        let retainedURL = historyStore.entries[0].url.absoluteString
        for sensitiveComponent in ["user", "pass", "token", "fixture", "secret-section"] {
            XCTAssertFalse(retainedURL.contains(sensitiveComponent))
            XCTAssertTrue(historyStore.query(sensitiveComponent, profileID: profile.id).isEmpty)
        }

        XCTAssertEqual(historyStore.query("view=full", profileID: profile.id).map(\.id), [entry.id])
    }

    func testRepeatedVisitsMatchOnNormalizedHistoryURL() throws {
        let profile = BrowserProfile(name: "Work")
        var historyStore = LocalHistoryStore()

        let firstEntry = try XCTUnwrap(
            historyStore.recordVisit(
                url: URL(string: "https://user:pass@example.com/docs?view=full&token=one#frag")!,
                title: "Original",
                profile: profile,
                visitedAt: Date(timeIntervalSince1970: 10)
            )
        )
        let updatedEntry = try XCTUnwrap(
            historyStore.recordVisit(
                url: URL(string: "https://example.com/docs?view=full")!,
                title: "Updated",
                profile: profile,
                visitedAt: Date(timeIntervalSince1970: 20)
            )
        )

        XCTAssertEqual(firstEntry.id, updatedEntry.id)
        XCTAssertEqual(historyStore.entries.count, 1)
        XCTAssertEqual(historyStore.entries[0].url.absoluteString, "https://example.com/docs?view=full")
        XCTAssertEqual(historyStore.entries[0].title, "Updated")
        XCTAssertEqual(historyStore.entries[0].visitCount, 2)
        XCTAssertEqual(historyStore.entries[0].lastVisitedAt, Date(timeIntervalSince1970: 20))
    }

    func testInitialEntriesAreNormalizedBeforeRetention() throws {
        let profile = BrowserProfile(name: "Imported")
        let rawEntry = BrowserHistoryEntry(
            profileID: profile.id,
            url: URL(string: "https://name:password@example.com/imported?search=swift&session_id=secret#fragment")!,
            title: "Imported"
        )

        let historyStore = LocalHistoryStore(entries: [rawEntry])

        let entry = try XCTUnwrap(historyStore.entries.first)
        XCTAssertEqual(entry.url.absoluteString, "https://example.com/imported?search=swift")
        XCTAssertFalse(entry.url.absoluteString.contains("password"))
        XCTAssertFalse(entry.url.absoluteString.contains("session_id"))
        XCTAssertFalse(entry.url.absoluteString.contains("secret"))
        XCTAssertFalse(entry.url.absoluteString.contains("fragment"))
    }

    func testQueryIsScopedToProfileAndSortedByRecency() throws {
        let workProfile = BrowserProfile(name: "Work")
        let personalProfile = BrowserProfile(name: "Personal")
        var historyStore = LocalHistoryStore()

        historyStore.recordVisit(
            url: URL(string: "https://docs.example.com/old")!,
            title: "Docs Old",
            profile: workProfile,
            visitedAt: Date(timeIntervalSince1970: 10)
        )
        historyStore.recordVisit(
            url: URL(string: "https://docs.example.com/new")!,
            title: "Docs New",
            profile: workProfile,
            visitedAt: Date(timeIntervalSince1970: 30)
        )
        historyStore.recordVisit(
            url: URL(string: "https://docs.example.com/personal")!,
            title: "Docs Personal",
            profile: personalProfile,
            visitedAt: Date(timeIntervalSince1970: 40)
        )

        let workResults = historyStore.query("docs", profileID: workProfile.id)
        let personalResults = historyStore.query("docs", profileID: personalProfile.id)

        XCTAssertEqual(workResults.map(\.title), ["Docs New", "Docs Old"])
        XCTAssertEqual(personalResults.map(\.title), ["Docs Personal"])
        XCTAssertEqual(try XCTUnwrap(workResults.first).profileID, workProfile.id)
    }
}
