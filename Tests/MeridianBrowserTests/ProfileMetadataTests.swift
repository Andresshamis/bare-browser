import MeridianCore
import XCTest

final class ProfileMetadataTests: XCTestCase {
    func testPersistentProfilesCarryWebsiteDataStoreIdentifiers() {
        let profile = BrowserProfile(name: "Work")

        XCTAssertFalse(profile.isEphemeral)
        XCTAssertNotNil(profile.websiteDataStoreID)
    }

    func testPrivateProfilesDoNotPersistWebsiteDataStoreIdentifiers() {
        let profile = BrowserProfile.privateBrowsing()

        XCTAssertTrue(profile.isEphemeral)
        XCTAssertNil(profile.websiteDataStoreID)
    }
}
