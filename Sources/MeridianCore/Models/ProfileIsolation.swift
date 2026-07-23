import CryptoKit
import Foundation

public struct WebContentSessionIdentity: Hashable, Sendable {
    public var tabID: TabID
    public var spaceID: SpaceID
    public var profileID: ProfileID
    public var websiteDataStoreID: UUID?

    public init(
        tabID: TabID,
        spaceID: SpaceID,
        profileID: ProfileID,
        websiteDataStoreID: UUID?
    ) {
        self.tabID = tabID
        self.spaceID = spaceID
        self.profileID = profileID
        self.websiteDataStoreID = websiteDataStoreID
    }
}

public struct SessionIntegrityRepairReport: Codable, Equatable, Sendable {
    public var duplicateProfileIDsRemoved: Int
    public var duplicateWebsiteDataStoresIsolated: Int
    public var duplicateSpaceIDsRemoved: Int
    public var duplicateFolderIDsRemoved: Int
    public var duplicateTabIDsRemoved: Int
    public var orphanedObjectsRemoved: Int
    public var tabProfileMismatchesRepaired: Int
    public var ownershipListsRebuilt: Int
    public var folderRelationshipsRepaired: Int
    public var splitViewsRemoved: Int
    public var selectionsRepaired: Int
    public var fallbackWasUsed: Bool

    public init(
        duplicateProfileIDsRemoved: Int = 0,
        duplicateWebsiteDataStoresIsolated: Int = 0,
        duplicateSpaceIDsRemoved: Int = 0,
        duplicateFolderIDsRemoved: Int = 0,
        duplicateTabIDsRemoved: Int = 0,
        orphanedObjectsRemoved: Int = 0,
        tabProfileMismatchesRepaired: Int = 0,
        ownershipListsRebuilt: Int = 0,
        folderRelationshipsRepaired: Int = 0,
        splitViewsRemoved: Int = 0,
        selectionsRepaired: Int = 0,
        fallbackWasUsed: Bool = false
    ) {
        self.duplicateProfileIDsRemoved = duplicateProfileIDsRemoved
        self.duplicateWebsiteDataStoresIsolated = duplicateWebsiteDataStoresIsolated
        self.duplicateSpaceIDsRemoved = duplicateSpaceIDsRemoved
        self.duplicateFolderIDsRemoved = duplicateFolderIDsRemoved
        self.duplicateTabIDsRemoved = duplicateTabIDsRemoved
        self.orphanedObjectsRemoved = orphanedObjectsRemoved
        self.tabProfileMismatchesRepaired = tabProfileMismatchesRepaired
        self.ownershipListsRebuilt = ownershipListsRebuilt
        self.folderRelationshipsRepaired = folderRelationshipsRepaired
        self.splitViewsRemoved = splitViewsRemoved
        self.selectionsRepaired = selectionsRepaired
        self.fallbackWasUsed = fallbackWasUsed
    }

    public var didRepairIsolationState: Bool {
        duplicateProfileIDsRemoved > 0
            || duplicateWebsiteDataStoresIsolated > 0
            || duplicateSpaceIDsRemoved > 0
            || duplicateFolderIDsRemoved > 0
            || duplicateTabIDsRemoved > 0
            || orphanedObjectsRemoved > 0
            || tabProfileMismatchesRepaired > 0
            || ownershipListsRebuilt > 0
            || folderRelationshipsRepaired > 0
            || splitViewsRemoved > 0
            || selectionsRepaired > 0
            || fallbackWasUsed
    }

    public var userMessage: String? {
        guard didRepairIsolationState else {
            return nil
        }
        if duplicateWebsiteDataStoresIsolated > 0 {
            return "Lumen Browser separated profiles that were sharing website data. Some affected profiles were signed out for safety."
        }
        return "Lumen Browser repaired saved profile and space assignments before restoring this session."
    }
}

public enum ProfileIsolationDiagnosticArchive {
    private static let reportKey = "ProfileIsolation.LastRepairReport"

    public static func load(defaults: UserDefaults = .standard) -> SessionIntegrityRepairReport? {
        guard let data = defaults.data(forKey: reportKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SessionIntegrityRepairReport.self, from: data)
    }

    public static func save(
        _ report: SessionIntegrityRepairReport,
        defaults: UserDefaults = .standard
    ) {
        guard report.didRepairIsolationState,
              let data = try? JSONEncoder().encode(report) else {
            return
        }
        defaults.set(data, forKey: reportKey)
    }
}

public struct SessionIntegrityRepairResult: Equatable, Sendable {
    public var snapshot: BrowserSessionSnapshot
    public var report: SessionIntegrityRepairReport

    public init(snapshot: BrowserSessionSnapshot, report: SessionIntegrityRepairReport) {
        self.snapshot = snapshot
        self.report = report
    }
}

public struct PersistentProfileCreationResult: Equatable, Sendable {
    public var profile: BrowserProfile
    public var space: BrowserSpace

    public init(profile: BrowserProfile, space: BrowserSpace) {
        self.profile = profile
        self.space = space
    }
}

public struct ProfileIsolationDiagnostics: Equatable, Sendable {
    public var generatedAt: Date
    public var report: SessionIntegrityRepairReport
    public var profileCount: Int
    public var spaceCount: Int
    public var tabCount: Int
    public var selectedIdentity: WebContentSessionIdentity?
    public var invariantFailures: [String]

    public init(
        generatedAt: Date = Date(),
        report: SessionIntegrityRepairReport,
        profileCount: Int,
        spaceCount: Int,
        tabCount: Int,
        selectedIdentity: WebContentSessionIdentity?,
        invariantFailures: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.report = report
        self.profileCount = profileCount
        self.spaceCount = spaceCount
        self.tabCount = tabCount
        self.selectedIdentity = selectedIdentity
        self.invariantFailures = invariantFailures
    }

    public var redactedText: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let identity = selectedIdentity.map {
            "tab=\(Self.redacted($0.tabID)) space=\(Self.redacted($0.spaceID)) profile=\(Self.redacted($0.profileID)) store=\($0.websiteDataStoreID.map(Self.redacted) ?? "private")"
        } ?? "none"

        return """
        Lumen Browser Profile Isolation Diagnostics
        Generated: \(generatedAt.formatted(.iso8601))
        App: \(version) (\(build))
        OS: \(os)
        Objects: profiles=\(profileCount) spaces=\(spaceCount) tabs=\(tabCount)
        Selected identity: \(identity)
        Current invariant failures: \(invariantFailures.isEmpty ? "none" : invariantFailures.joined(separator: ","))
        Repairs: duplicateProfileIDs=\(report.duplicateProfileIDsRemoved) sharedStores=\(report.duplicateWebsiteDataStoresIsolated) duplicateSpaceIDs=\(report.duplicateSpaceIDsRemoved) duplicateFolderIDs=\(report.duplicateFolderIDsRemoved) duplicateTabIDs=\(report.duplicateTabIDsRemoved) orphans=\(report.orphanedObjectsRemoved) tabProfiles=\(report.tabProfileMismatchesRepaired) ownershipLists=\(report.ownershipListsRebuilt) folderRelationships=\(report.folderRelationshipsRepaired) splitViews=\(report.splitViewsRemoved) selections=\(report.selectionsRepaired) fallback=\(report.fallbackWasUsed)
        Privacy: no URLs, cookies, page contents, account names, email addresses, or credentials are included.
        """
    }

    private static func redacted(_ id: UUID) -> String {
        let digest = SHA256.hash(data: Data(id.uuidString.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
