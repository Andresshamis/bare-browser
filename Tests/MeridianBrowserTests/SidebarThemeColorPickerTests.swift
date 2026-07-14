import AppKit
@testable import MeridianCore
import XCTest

@MainActor
final class SidebarThemeColorPickerTests: XCTestCase {
    func testHexConversionNormalizesCaseAndFormat() {
        XCTAssertEqual(SidebarThemeColorComponents(hex: "#ff375f").hexString, "#FF375F")
        XCTAssertEqual(SidebarThemeColorComponents(hex: "30d158").hexString, "#30D158")
    }

    func testInvalidHexFallsBackToDefaultColor() {
        XCTAssertEqual(SidebarThemeColorComponents.normalizedHex("not-a-color"), "#4F7CAC")
    }

    func testHSBComponentsConvertBackToHex() {
        XCTAssertEqual(
            SidebarThemeColorComponents(hue: 0, saturation: 1, brightness: 1).hexString,
            "#FF0000"
        )
        XCTAssertEqual(
            SidebarThemeColorComponents(hue: 1.0 / 3.0, saturation: 1, brightness: 1).hexString,
            "#00FF00"
        )
    }

    func testSampledColorNormalizesToSRGBHexAndIgnoresAlpha() throws {
        let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.3)

        XCTAssertEqual(SidebarThemeColorComponents.hexString(from: color), "#336699")
    }

    func testSamplerCallbackUpdatesWhenActive() {
        let fakeSampler = FakeSidebarThemeColorSampler()
        let controller = SidebarThemeColorSamplerController { fakeSampler }
        var sampledHex: String?

        controller.beginSampling { sampledHex = $0 }
        fakeSampler.complete(NSColor(srgbRed: 1, green: 0.2, blue: 0, alpha: 1))

        XCTAssertEqual(sampledHex, "#FF3300")
        XCTAssertFalse(controller.isSampling)
    }

    func testSamplerCallbackIsIgnoredAfterCancellation() {
        let fakeSampler = FakeSidebarThemeColorSampler()
        let controller = SidebarThemeColorSamplerController { fakeSampler }
        var sampledHex: String?

        controller.beginSampling { sampledHex = $0 }
        controller.cancelSampling()
        fakeSampler.complete(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))

        XCTAssertNil(sampledHex)
        XCTAssertFalse(controller.isSampling)
    }

    func testRepeatedSamplingIgnoresStaleSamplerCallback() throws {
        var fakeSamplers: [FakeSidebarThemeColorSampler] = []
        let controller = SidebarThemeColorSamplerController {
            let sampler = FakeSidebarThemeColorSampler()
            fakeSamplers.append(sampler)
            return sampler
        }
        var sampledHexes: [String] = []

        controller.beginSampling { sampledHexes.append($0) }
        controller.beginSampling { sampledHexes.append($0) }

        try XCTUnwrap(fakeSamplers.first).complete(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertTrue(sampledHexes.isEmpty)
        XCTAssertTrue(controller.isSampling)

        try XCTUnwrap(fakeSamplers.last).complete(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        XCTAssertEqual(sampledHexes, ["#00FF00"])
        XCTAssertFalse(controller.isSampling)
    }

    func testNilSampleEndsSamplingWithoutUpdatingColor() {
        let fakeSampler = FakeSidebarThemeColorSampler()
        let controller = SidebarThemeColorSamplerController { fakeSampler }
        var sampledHex: String?

        controller.beginSampling { sampledHex = $0 }
        fakeSampler.complete(nil)

        XCTAssertNil(sampledHex)
        XCTAssertFalse(controller.isSampling)
    }
}

@MainActor
private final class FakeSidebarThemeColorSampler: SidebarThemeColorSampling {
    private var selectionHandler: (@MainActor (NSColor?) -> Void)?

    func show(selectionHandler: @escaping @MainActor (NSColor?) -> Void) {
        self.selectionHandler = selectionHandler
    }

    func complete(_ color: NSColor?) {
        selectionHandler?(color)
    }
}
