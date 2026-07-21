import Foundation
import WebKit

@MainActor
public protocol ProfileWebsiteDataStoreDeleting: AnyObject {
    func removeWebsiteDataStore(identifier: UUID) async throws
}

@MainActor
public final class ProfileWebsiteDataStoreProvider: ProfileWebsiteDataStoreDeleting {
    public init() {}

    public func websiteDataStore(for profile: BrowserProfile) -> WKWebsiteDataStore {
        if profile.isEphemeral {
            return .nonPersistent()
        }

        guard let identifier = profile.persistentWebsiteDataStoreID else {
            assertionFailure("Persistent profiles must have a website data store identifier.")
            return .nonPersistent()
        }

        return WKWebsiteDataStore(forIdentifier: identifier)
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
