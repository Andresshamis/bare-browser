import Foundation
import WebKit

@MainActor
public protocol ProfileWebsiteDataStoreDeleting: AnyObject {
    func removeWebsiteDataStore(identifier: UUID) async throws
}

@MainActor
public final class ProfileWebsiteDataStoreProvider: ObservableObject, ProfileWebsiteDataStoreDeleting {
    private var ephemeralStores: [ProfileID: WKWebsiteDataStore] = [:]

    public init() {}

    public func websiteDataStore(for profile: BrowserProfile) -> WKWebsiteDataStore {
        if profile.isEphemeral {
            if let existing = ephemeralStores[profile.id] {
                return existing
            }
            let store = WKWebsiteDataStore.nonPersistent()
            ephemeralStores[profile.id] = store
            return store
        }

        guard let identifier = profile.persistentWebsiteDataStoreID else {
            assertionFailure("Persistent profiles must have a website data store identifier.")
            return .nonPersistent()
        }

        return WKWebsiteDataStore(forIdentifier: identifier)
    }

    public func releaseEphemeralWebsiteDataStore(for profileID: ProfileID) {
        ephemeralStores.removeValue(forKey: profileID)
    }

    public func releaseEphemeralWebsiteDataStores(keeping profileIDs: Set<ProfileID>) {
        ephemeralStores = ephemeralStores.filter { profileIDs.contains($0.key) }
    }

    public func removeWebsiteDataStore(identifier: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
