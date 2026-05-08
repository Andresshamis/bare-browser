import Foundation
import MeridianCore
import XCTest

@MainActor
final class BrowserStoreTests: XCTestCase {
    func testInitialSnapshotHasProfileSpaceAndSelectedTab() {
        let store = BrowserStore(snapshot: SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 0)))

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.spaces.count, 1)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertNotNil(store.selectedSpaceID)
        XCTAssertNotNil(store.selectedTabID)
        XCTAssertEqual(store.activeProfile?.name, "Personal")
    }

    func testCreatesSpaceFolderAndTabWithStableRelationships() {
        let store = BrowserStore()
        let space = store.createSpace(name: "Work")
        let folder = store.createFolder(name: "Research", in: space.id)
        let tab = store.createTab(url: URL(string: "https://webkit.org"), in: space.id, folderID: folder?.id)

        XCTAssertEqual(store.selectedSpaceID, space.id)
        XCTAssertEqual(tab?.parentSpaceID, space.id)
        XCTAssertEqual(tab?.parentFolderID, folder?.id)
        XCTAssertEqual(store.folders.first(where: { $0.id == folder?.id })?.tabIDs, [tab?.id].compactMap { $0 })
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let store = BrowserStore()
        _ = store.createTab(url: URL(string: "https://example.com"))

        let snapshot = store.snapshot(date: Date(timeIntervalSince1970: 10))
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.tabs.count, snapshot.tabs.count)
        XCTAssertEqual(decoded.selectedTabID, snapshot.selectedTabID)
    }

    func testExternalURLCreatesPendingConfirmationInsteadOfOpeningTab() {
        let store = BrowserStore()
        let initialTabCount = store.tabs.count
        let externalURL = URL(string: "mailto:hello@example.com")!

        store.open(externalURL)

        XCTAssertEqual(store.tabs.count, initialTabCount)
        XCTAssertEqual(store.pendingURLConfirmation?.kind, .externalApplication)
        XCTAssertEqual(store.pendingURLConfirmation?.url, externalURL)
        XCTAssertEqual(store.lastUserMessage, URLConfirmationRequest.Kind.externalApplication.pendingMessage)
    }

    func testApprovingPendingConfirmationRevalidatesAndOpensURL() {
        let store = BrowserStore()
        let externalURL = URL(string: "mailto:hello@example.com")!
        var openedURL: URL?

        store.open(externalURL)
        let didOpen = store.approvePendingURLConfirmation { url in
            openedURL = url
            return true
        }

        XCTAssertTrue(didOpen)
        XCTAssertEqual(openedURL, externalURL)
        XCTAssertNil(store.pendingURLConfirmation)
        XCTAssertEqual(store.lastUserMessage, URLConfirmationRequest.Kind.externalApplication.approvedMessage)
    }

    func testCancelingPendingConfirmationDoesNotOpenURL() {
        let store = BrowserStore()
        let fileURL = URL(fileURLWithPath: "/tmp/test.html")

        store.requestURLConfirmation(kind: .localFile, url: fileURL, sourceURL: URL(string: "https://example.com"))

        XCTAssertEqual(store.pendingURLConfirmation?.sourceDescription, "example.com")

        store.cancelPendingURLConfirmation()

        XCTAssertNil(store.pendingURLConfirmation)
        XCTAssertEqual(store.lastUserMessage, URLConfirmationRequest.Kind.localFile.cancelledMessage)
    }

    func testPendingExternalURLConfirmationStoresSanitizedSourceContext() throws {
        let store = BrowserStore()
        let externalURL = URL(string: "mailto:help@meridian.test")!
        let sourceURL = URL(string: "https://user:pass@example.com/private/start?token=fixture#frag")!

        store.requestURLConfirmation(kind: .externalApplication, url: externalURL, sourceURL: sourceURL)

        let request = try XCTUnwrap(store.pendingURLConfirmation)
        XCTAssertEqual(request.url, externalURL)
        XCTAssertEqual(request.sourceDescription, "example.com")
        for sensitiveComponent in ["user", "pass", "/private", "token", "fixture", "frag"] {
            XCTAssertFalse(request.confirmationMessage.contains(sensitiveComponent), sensitiveComponent)
            XCTAssertFalse(request.sourceDescription.contains(sensitiveComponent), sensitiveComponent)
        }
    }

    func testPendingLocalFileConfirmationPreservesTargetAndSanitizesSourceContext() throws {
        let store = BrowserStore()
        let fileURL = URL(fileURLWithPath: "/tmp/report.html")
        let sourceURL = URL(string: "https://user:pass@example.com/private/start?token=fixture#frag")!
        var openedURL: URL?

        store.requestURLConfirmation(kind: .localFile, url: fileURL, sourceURL: sourceURL)

        let request = try XCTUnwrap(store.pendingURLConfirmation)
        XCTAssertEqual(request.url, fileURL)
        XCTAssertEqual(request.sourceDescription, "example.com")

        let didOpen = store.approvePendingURLConfirmation { url in
            openedURL = url
            return true
        }

        XCTAssertTrue(didOpen)
        XCTAssertEqual(openedURL, fileURL)
        XCTAssertNil(store.pendingURLConfirmation)
    }

    func testBlockedDownloadCompletesWithoutPendingPrompt() {
        let store = BrowserStore()
        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "installer.pkg",
            sourceURL: URL(string: "https://example.com/installer.pkg")
        )
        var completedURL: URL? = URL(fileURLWithPath: "/tmp/should-not-save")

        store.requestDownloadConfirmation(request) { destinationURL in
            completedURL = destinationURL
        }

        XCTAssertNil(completedURL)
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertEqual(store.lastUserMessage, "Downloads ending in .pkg require a dedicated installer flow.")
    }

    func testPendingDownloadConfirmationStoresSanitizedSourceMetadata() throws {
        let store = BrowserStore()
        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "report.pdf",
            sourceURL: URL(string: "https://user:password@example.com/private/source-name.zip?token=secret#fragment")
        )
        var completionCalled = false

        store.requestDownloadConfirmation(request) { _ in
            completionCalled = true
        }

        let pendingRequest = try XCTUnwrap(store.pendingDownloadConfirmation)
        XCTAssertFalse(completionCalled)
        XCTAssertEqual(pendingRequest.sourceDescription, "example.com")
        XCTAssertEqual(pendingRequest.sourceMetadata.quarantineOrigin, "https://example.com")

        let exposedState = [
            pendingRequest.sourceDescription,
            pendingRequest.sourceMetadata.quarantineOrigin ?? "",
            pendingRequest.confirmationMessage
        ].joined(separator: "\n")
        XCTAssertFalse(exposedState.contains("user"))
        XCTAssertFalse(exposedState.contains("password"))
        XCTAssertFalse(exposedState.contains("private"))
        XCTAssertFalse(exposedState.contains("source-name"))
        XCTAssertFalse(exposedState.contains("token"))
        XCTAssertFalse(exposedState.contains("secret"))
        XCTAssertFalse(exposedState.contains("fragment"))
    }

    func testRiskyDownloadApprovalUsesSafeNonExistingDestination() throws {
        let store = BrowserStore()
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let existingURL = temporaryDirectory.appendingPathComponent("script.sh")
        FileManager.default.createFile(atPath: existingURL.path, contents: Data())
        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "../script.sh",
            sourceURL: URL(string: "https://example.com/script.sh")
        )
        var completedURL: URL?

        store.requestDownloadConfirmation(request) { destinationURL in
            completedURL = destinationURL
        }
        let didApprove = store.approvePendingDownloadConfirmation(destination: existingURL)

        XCTAssertTrue(didApprove)
        XCTAssertEqual(completedURL?.lastPathComponent, "script 2.sh")
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertEqual(store.lastUserMessage, "Download will be saved as script 2.sh.")
    }

    func testDownloadAlertDismissalDuringDestinationSelectionKeepsPendingDownload() throws {
        let store = BrowserStore()
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "archive.zip",
            sourceURL: URL(string: "https://example.com/archive.zip")
        )
        let selectedURL = temporaryDirectory.appendingPathComponent("archive.zip")
        var completedURL: URL?
        var completionCallCount = 0

        store.requestDownloadConfirmation(request) { destinationURL in
            completionCallCount += 1
            completedURL = destinationURL
        }

        XCTAssertTrue(store.beginPendingDownloadDestinationSelection())
        XCTAssertTrue(store.isChoosingDownloadDestination)

        store.dismissPendingDownloadConfirmationAlert()

        XCTAssertEqual(completionCallCount, 0)
        XCTAssertNotNil(store.pendingDownloadConfirmation)
        XCTAssertTrue(store.isChoosingDownloadDestination)

        let didApprove = store.approvePendingDownloadConfirmation(destination: selectedURL)

        XCTAssertTrue(didApprove)
        XCTAssertEqual(completionCallCount, 1)
        XCTAssertEqual(completedURL, selectedURL)
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertFalse(store.isChoosingDownloadDestination)
    }

    func testDownloadAlertDismissalWithoutDestinationSelectionCancelsDownload() {
        let store = BrowserStore()
        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "archive.zip",
            sourceURL: URL(string: "https://example.com/archive.zip")
        )
        var completedURL: URL? = URL(fileURLWithPath: "/tmp/should-not-save")

        store.requestDownloadConfirmation(request) { destinationURL in
            completedURL = destinationURL
        }

        store.dismissPendingDownloadConfirmationAlert()

        XCTAssertNil(completedURL)
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertFalse(store.isChoosingDownloadDestination)
        XCTAssertEqual(store.lastUserMessage, request.cancelledMessage)
    }

    func testLowRiskDownloadRejectsDestinationChangedToRiskyExtension() throws {
        let store = BrowserStore()
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "archive.zip",
            sourceURL: URL(string: "https://example.com/archive.zip")
        )
        var completedURL: URL? = URL(fileURLWithPath: "/tmp/should-not-save")

        store.requestDownloadConfirmation(request) { destinationURL in
            completedURL = destinationURL
        }
        let didApprove = store.approvePendingDownloadConfirmation(
            destination: temporaryDirectory.appendingPathComponent("renamed.sh")
        )

        XCTAssertFalse(didApprove)
        XCTAssertNil(completedURL)
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertEqual(
            store.lastUserMessage,
            "Download destination requires confirmation. Downloads ending in .sh can execute code."
        )
    }

    func testCancelingPendingDownloadCompletesWithNilDestination() {
        let store = BrowserStore()
        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "archive.zip",
            sourceURL: URL(string: "https://example.com/archive.zip")
        )
        var completedURL: URL? = URL(fileURLWithPath: "/tmp/should-not-save")

        store.requestDownloadConfirmation(request) { destinationURL in
            completedURL = destinationURL
        }
        store.cancelPendingDownloadConfirmation()

        XCTAssertNil(completedURL)
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertEqual(store.lastUserMessage, request.cancelledMessage)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
