@testable import MeridianCore
import JavaScriptCore
import XCTest

final class BrowserPasskeyUnavailableScriptTests: XCTestCase {
    func testPublicKeyRequestsAreRejectedAndNotifyLumen() throws {
        let context = try XCTUnwrap(JSContext())
        var exception: JSValue?
        context.exceptionHandler = { _, value in
            exception = value
        }

        context.evaluateScript("""
        var originalGetCount = 0;
        var originalCreateCount = 0;
        var passkeyNoticeCount = 0;
        var lastRejectedError = null;
        var window = {
            __meridianPasskeyUnavailableInstalled: false,
            webkit: {
                messageHandlers: {
                    meridianPasskeyUnavailable: {
                        postMessage: function(token) {
                            if (token === "public-key-credential") {
                                passkeyNoticeCount += 1;
                            }
                        }
                    }
                }
            }
        };
        var navigator = {
            credentials: {
                get: function(_) {
                    originalGetCount += 1;
                    return "original-get";
                },
                create: function(_) {
                    originalCreateCount += 1;
                    return "original-create";
                }
            }
        };
        var Promise = {
            reject: function(error) {
                lastRejectedError = error;
                return "rejected";
            }
        };
        function DOMException(message, name) {
            this.message = message;
            this.name = name;
        }
        """)
        XCTAssertNil(exception?.toString())

        context.evaluateScript(BrowserPasskeyUnavailableScript.source)
        XCTAssertNil(exception?.toString())

        XCTAssertEqual(
            context.evaluateScript("navigator.credentials.get({ password: true })").toString(),
            "original-get"
        )
        XCTAssertEqual(context.evaluateScript("originalGetCount").toInt32(), 1)

        XCTAssertEqual(
            context.evaluateScript("navigator.credentials.get({ publicKey: {} })").toString(),
            "rejected"
        )
        XCTAssertEqual(context.evaluateScript("originalGetCount").toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("passkeyNoticeCount").toInt32(), 1)
        XCTAssertEqual(
            context.evaluateScript("lastRejectedError.name").toString(),
            "NotSupportedError"
        )
        XCTAssertEqual(
            context.evaluateScript("lastRejectedError.message").toString(),
            BrowserPasskeyUnavailableScript.userMessage
        )
    }

    func testCreateRequestsAreAlsoRejected() throws {
        let context = try configuredContext()

        context.evaluateScript(BrowserPasskeyUnavailableScript.source)

        XCTAssertEqual(
            context.evaluateScript("navigator.credentials.create({ publicKey: {} })").toString(),
            "rejected"
        )
        XCTAssertEqual(context.evaluateScript("originalCreateCount").toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("passkeyNoticeCount").toInt32(), 1)
    }

    private func configuredContext() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var originalCreateCount = 0;
        var passkeyNoticeCount = 0;
        var window = {
            __meridianPasskeyUnavailableInstalled: false,
            webkit: {
                messageHandlers: {
                    meridianPasskeyUnavailable: {
                        postMessage: function(_) {
                            passkeyNoticeCount += 1;
                        }
                    }
                }
            }
        };
        var navigator = {
            credentials: {
                get: function(_) { return "original-get"; },
                create: function(_) {
                    originalCreateCount += 1;
                    return "original-create";
                }
            }
        };
        var Promise = {
            reject: function(_) { return "rejected"; }
        };
        function DOMException(message, name) {
            this.message = message;
            this.name = name;
        }
        """)
        return context
    }
}
