import Foundation
import MeridianCore
import XCTest

final class AddressResolverTests: XCTestCase {
    func testResolvesExplicitHTTPSURL() {
        let resolver = AddressResolver()

        XCTAssertEqual(resolver.resolve("https://example.com/path"), .url(URL(string: "https://example.com/path")!))
    }

    func testAddsHTTPSForBareHost() {
        let resolver = AddressResolver()

        XCTAssertEqual(resolver.resolve("example.com"), .url(URL(string: "https://example.com")!))
    }

    func testKeepsLocalhostOnHTTP() {
        let resolver = AddressResolver()

        XCTAssertEqual(resolver.resolve("localhost:5173"), .url(URL(string: "http://localhost:5173")!))
    }

    func testSearchesPlainTextQueriesWithGoogle() {
        let resolver = AddressResolver()

        guard case .search(let url, let query) = resolver.resolve("swift webkit profiles") else {
            return XCTFail("Expected a search resolution.")
        }

        XCTAssertEqual(query, "swift webkit profiles")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host(percentEncoded: false), "www.google.com")
        XCTAssertEqual(url.path(), "/search")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "q" })?.value, "swift webkit profiles")
        XCTAssertNil(components?.queryItems?.first(where: { $0.name == "btnI" }))
    }
}
