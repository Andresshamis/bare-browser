import Foundation
@testable import MeridianCore
import XCTest

final class NavigationFailureDiagnosticsTests: XCTestCase {
    func testSuppressesUserCanceledNavigationFailures() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

        let diagnostics = NavigationFailureDiagnostics(error: error)

        XCTAssertNil(diagnostics.userMessage)
    }

    func testSuppressesWebKitPolicyChangeInterruptions() {
        let error = NSError(domain: "WebKitErrorDomain", code: 102)

        let diagnostics = NavigationFailureDiagnostics(error: error)

        XCTAssertNil(diagnostics.userMessage)
    }

    func testMapsTimedOutNavigationFailures() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)

        let diagnostics = NavigationFailureDiagnostics(error: error)

        XCTAssertEqual(diagnostics.userMessage, "Navigation failed: request timed out.")
    }

    func testMapsSecureConnectionNavigationFailures() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)

        let diagnostics = NavigationFailureDiagnostics(error: error)

        XCTAssertEqual(diagnostics.userMessage, "Navigation failed: secure connection could not be verified.")
    }

    func testMapsUnknownNavigationFailuresToLogGuidance() {
        let error = NSError(domain: "CustomDomain", code: 123)

        let diagnostics = NavigationFailureDiagnostics(error: error)

        XCTAssertEqual(diagnostics.userMessage, "Navigation failed. Check Bare Browser logs for details.")
    }
}
