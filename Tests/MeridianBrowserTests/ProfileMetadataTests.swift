import MeridianCore
import XCTest

final class ProfileMetadataTests: XCTestCase {
    func testPersistentProfilesCarryWebsiteDataStoreIdentifiers() {
        let profile = BrowserProfile(name: "Work")

        XCTAssertFalse(profile.isEphemeral)
        XCTAssertNotNil(profile.websiteDataStoreID)
    }

    func testPersistentProfilesRepairMissingWebsiteDataStoreIdentifier() {
        let profileID = UUID(uuidString: "8D3FB4C7-D76E-41A3-9DB9-D24A50E1A03F")!
        let profile = BrowserProfile(
            id: profileID,
            name: "Recovered",
            websiteDataStoreID: nil,
            isEphemeral: false,
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )

        XCTAssertEqual(profile.websiteDataStoreID, profileID)
        XCTAssertEqual(profile.persistentWebsiteDataStoreID, profileID)
    }

    func testPrivateProfilesDoNotPersistWebsiteDataStoreIdentifiers() {
        let profile = BrowserProfile.privateBrowsing()

        XCTAssertTrue(profile.isEphemeral)
        XCTAssertNil(profile.websiteDataStoreID)
        XCTAssertNil(profile.persistentWebsiteDataStoreID)
    }

    func testDecodedPersistentProfilesRepairMissingWebsiteDataStoreIdentifier() throws {
        let profileID = UUID(uuidString: "A042C901-892A-4B83-BE84-6F36764934FE")!
        let json = """
        {
          "id": "\(profileID.uuidString)",
          "name": "Imported",
          "colorHex": "#4F7CAC",
          "isEphemeral": false,
          "createdAt": 0
        }
        """

        let profile = try JSONDecoder().decode(BrowserProfile.self, from: Data(json.utf8))

        XCTAssertFalse(profile.isEphemeral)
        XCTAssertEqual(profile.websiteDataStoreID, profileID)
        XCTAssertEqual(profile.persistentWebsiteDataStoreID, profileID)
    }

    func testDecodedPrivateProfilesDiscardWebsiteDataStoreIdentifier() throws {
        let json = """
        {
          "id": "9EF1D9C9-2D10-41EA-B5F3-6DCAC361ABDB",
          "name": "Private",
          "colorHex": "#5E5CE6",
          "websiteDataStoreID": "E63F81B8-71C6-4D4F-B1C1-6100CF31D972",
          "isEphemeral": true,
          "createdAt": 0
        }
        """

        let profile = try JSONDecoder().decode(BrowserProfile.self, from: Data(json.utf8))

        XCTAssertTrue(profile.isEphemeral)
        XCTAssertNil(profile.websiteDataStoreID)
        XCTAssertNil(profile.persistentWebsiteDataStoreID)
    }
}
