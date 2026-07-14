@testable import MeridianCore
import JavaScriptCore
import XCTest

final class PasswordAutofillScriptTests: XCTestCase {
    func testAutofillObserverCanBeAssignedAfterDelayedLoginFormRender() {
        XCTAssertTrue(BrowserPasswordCaptureScript.source.contains("var savedAutofillCredentials = [];"))
        XCTAssertTrue(BrowserPasswordCaptureScript.source.contains("var autofillObserver = null;"))
        XCTAssertFalse(BrowserPasswordCaptureScript.source.contains("let savedAutofillCredentials = [];"))
        XCTAssertFalse(BrowserPasswordCaptureScript.source.contains("let autofillObserver = null;"))
    }

    func testAutofillInstallsVisibleAccountPickerBeforePasswordValueCheck() throws {
        let source = BrowserPasswordCaptureScript.source

        XCTAssertTrue(source.contains("bare-browser-password-account-picker"))
        XCTAssertTrue(source.contains("showAccountPicker"))
        XCTAssertTrue(source.contains("input.addEventListener(\"focus\", showAccountPickerForInput, true);"))
        XCTAssertTrue(source.contains("backdrop-filter: blur(42px) saturate(1.95) contrast(1.08)"))
        XCTAssertTrue(source.contains("border-radius: 18px"))
        XCTAssertTrue(source.contains("accountOptionHighlightedStyle"))
        XCTAssertTrue(source.contains("rgba(9,14,24,0.14)"))
        XCTAssertTrue(source.contains("option.addEventListener(\"mouseenter\""))
        XCTAssertTrue(source.contains("option.addEventListener(\"focus\""))
        XCTAssertFalse(source.contains("document.createElement(\"datalist\")"))
        XCTAssertFalse(source.contains("credentials.length < 2"))
        XCTAssertFalse(source.contains("meridian-password-account-picker"))

        let installRange = try XCTUnwrap(source.range(of: "installAccountPicker(usernameInput, passwordInput, credentials);"))
        let passwordValueRange = try XCTUnwrap(source.range(of: "if (normalized(passwordInput.value))"))
        let installOffset = source.distance(from: source.startIndex, to: installRange.lowerBound)
        let passwordValueOffset = source.distance(from: source.startIndex, to: passwordValueRange.lowerBound)

        XCTAssertLessThan(installOffset, passwordValueOffset)
    }

    func testAutofillAttemptsEveryPasswordScope() {
        let source = BrowserPasswordCaptureScript.source

        XCTAssertTrue(source.contains("for (const scope of scopes)"))
        XCTAssertFalse(source.contains("return scopes.some(scope => autofillScope(scope, credentials));"))
    }

    func testPasswordCaptureScriptParsesAndInstallsAutofillFunction() throws {
        let context = try XCTUnwrap(JSContext())
        var exception: JSValue?
        context.exceptionHandler = { _, value in
            exception = value
        }

        context.evaluateScript("""
        var window = {
            __meridianPasswordCaptureInstalled: false,
            webkit: {
                messageHandlers: {
                    meridianPasswordCredential: { postMessage: function(_) {} }
                }
            },
            addEventListener: function() {},
            getComputedStyle: function(_) { return { visibility: "visible", display: "block" }; },
            setTimeout: function(_, __) { return 0; }
        };
        var document = {
            body: { appendChild: function(_) {} },
            documentElement: { appendChild: function(_) {} },
            addEventListener: function() {},
            querySelectorAll: function(_) { return []; }
        };
        function MutationObserver(_) {
            this.observe = function() {};
        }
        function Node() {}
        function Element() {}
        function HTMLInputElement() {}
        function HTMLFormElement() {}
        """)
        XCTAssertNil(exception?.toString())

        context.evaluateScript(BrowserPasswordCaptureScript.source)

        XCTAssertNil(exception?.toString())
        XCTAssertEqual(context.evaluateScript("typeof window.__meridianPasswordAutofill").toString(), "function")
        XCTAssertFalse(context.evaluateScript("window.__meridianPasswordAutofill([])").toBool())
    }
}
