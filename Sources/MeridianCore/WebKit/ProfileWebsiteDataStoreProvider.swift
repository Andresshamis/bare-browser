import Foundation
import WebKit

@MainActor
public final class ProfileWebsiteDataStoreProvider {
    public init() {}

    public func websiteDataStore(for profile: BrowserProfile) -> WKWebsiteDataStore {
        if profile.isEphemeral {
            return .nonPersistent()
        }

        guard let identifier = profile.websiteDataStoreID else {
            assertionFailure("Persistent profiles must have a website data store identifier.")
            return .default()
        }

        return WKWebsiteDataStore(forIdentifier: identifier)
    }
}
