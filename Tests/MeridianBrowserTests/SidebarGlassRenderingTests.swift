@testable import MeridianCore
import XCTest

final class SidebarGlassRenderingTests: XCTestCase {
    func testClearNeutralRecipeHasNoThemeColorAndMinimumDensity() {
        let settings = SidebarGlassSettings(
            glassOpacity: 0,
            tintOpacity: 0,
            edgeOpacity: 0.3,
            shadowOpacity: 0,
            highlightOpacity: 0.2
        )

        let recipe = SidebarGlassRendering.recipe(for: settings)

        XCTAssertEqual(recipe.density, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.colorMix, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.themeFillOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.themeGlassTintOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.neutralFillOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.neutralHighlightOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.themeHighlightOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.shadowOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.totalFillOpacity, 0, accuracy: 0.001)
    }

    func testClearDensityUsesThemeColorWhenColorSliderIsMaxed() {
        let settings = SidebarGlassSettings(
            glassOpacity: 0,
            tintOpacity: 1,
            edgeOpacity: 0.3,
            shadowOpacity: 0.2,
            highlightOpacity: 0.2
        )

        let recipe = SidebarGlassRendering.recipe(for: settings)

        XCTAssertEqual(recipe.density, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.colorMix, 1, accuracy: 0.001)
        XCTAssertEqual(recipe.neutralFillOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.themeFillOpacity, 0.24, accuracy: 0.001)
        XCTAssertEqual(recipe.totalFillOpacity, 0.24, accuracy: 0.001)
        XCTAssertEqual(recipe.themeGlassTintOpacity, 0.16, accuracy: 0.001)
        XCTAssertEqual(recipe.neutralHighlightOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.themeHighlightOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(recipe.shadowOpacity, 0, accuracy: 0.001)
    }

    func testColorOnlySplitsFillBetweenNeutralAndTheme() {
        let neutral = SidebarGlassSettings(
            glassOpacity: 0.42,
            tintOpacity: 0,
            edgeOpacity: 0.34,
            shadowOpacity: 0.14,
            highlightOpacity: 0.16
        )
        let color = SidebarGlassSettings(
            glassOpacity: 0.42,
            tintOpacity: 1,
            edgeOpacity: 0.54,
            shadowOpacity: 0.30,
            highlightOpacity: 0.30
        )

        let neutralRecipe = SidebarGlassRendering.recipe(for: neutral)
        let colorRecipe = SidebarGlassRendering.recipe(for: color)

        XCTAssertEqual(neutralRecipe.neutralFillOpacity, neutralRecipe.totalFillOpacity, accuracy: 0.001)
        XCTAssertEqual(neutralRecipe.themeFillOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(colorRecipe.neutralFillOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(colorRecipe.themeFillOpacity, colorRecipe.totalFillOpacity, accuracy: 0.001)
        XCTAssertGreaterThan(colorRecipe.themeFillOpacity, neutralRecipe.neutralFillOpacity)
    }

    func testDensityRaisesFillWithoutChangingColorMix() {
        let clear = SidebarGlassSettings(
            glassOpacity: 0,
            tintOpacity: 0.25,
            edgeOpacity: 0.34,
            shadowOpacity: 0.14,
            highlightOpacity: 0.16
        )
        let dense = SidebarGlassSettings(
            glassOpacity: 1,
            tintOpacity: 0.25,
            edgeOpacity: 0.54,
            shadowOpacity: 0.30,
            highlightOpacity: 0.30
        )

        let clearRecipe = SidebarGlassRendering.recipe(for: clear)
        let denseRecipe = SidebarGlassRendering.recipe(for: dense)

        XCTAssertEqual(clearRecipe.colorMix, denseRecipe.colorMix, accuracy: 0.001)
        XCTAssertEqual(clearRecipe.totalFillOpacity, 0.06, accuracy: 0.001)
        XCTAssertEqual(clearRecipe.neutralFillOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(clearRecipe.themeFillOpacity, 0.06, accuracy: 0.001)
        XCTAssertEqual(denseRecipe.themeFillOpacity / denseRecipe.totalFillOpacity, 0.25, accuracy: 0.001)
        XCTAssertEqual(denseRecipe.totalFillOpacity, 1, accuracy: 0.001)
        XCTAssertGreaterThan(denseRecipe.shadowOpacity, clearRecipe.shadowOpacity)
    }

    func testColorNoiseOpacityTracksLevel() {
        let clean = SidebarGlassSettings(
            glassOpacity: 0.60,
            tintOpacity: 0.20,
            colorNoiseLevel: 0,
            edgeOpacity: 0.40,
            shadowOpacity: 0.20,
            highlightOpacity: 0.20
        )
        let grain = SidebarGlassSettings(
            glassOpacity: 0.60,
            tintOpacity: 0.20,
            colorNoiseLevel: 1,
            edgeOpacity: 0.40,
            shadowOpacity: 0.20,
            highlightOpacity: 0.20
        )

        XCTAssertEqual(SidebarGlassRendering.colorNoiseOpacity(for: clean), 0, accuracy: 0.001)
        XCTAssertEqual(SidebarGlassRendering.colorNoiseOpacity(for: grain), 0.30, accuracy: 0.001)
    }

    func testColorNoiseCellSizeTracksScale() {
        XCTAssertEqual(SidebarGlassRendering.colorNoiseCellSize(forScale: 0), 1.2, accuracy: 0.001)
        XCTAssertEqual(SidebarGlassRendering.colorNoiseCellSize(forScale: 0.30), 2.345, accuracy: 0.001)
        XCTAssertEqual(SidebarGlassRendering.colorNoiseCellSize(forScale: 1), 11.2, accuracy: 0.001)
    }

    func testColorNoiseTextureCellSizeIsQuantizedForCaching() {
        XCTAssertEqual(SidebarGlassRendering.colorNoiseTextureCellSize(forScale: 0), 1.25, accuracy: 0.001)
        XCTAssertEqual(SidebarGlassRendering.colorNoiseTextureCellSize(forScale: 0.30), 2.25, accuracy: 0.001)
        XCTAssertEqual(SidebarGlassRendering.colorNoiseTextureCellSize(forScale: 1), 11.25, accuracy: 0.001)
    }

    func testSelectedSpaceIconUsesDarkForegroundForVeryLightTint() {
        let settings = SidebarGlassSettings(
            glassOpacity: 0.60,
            tintOpacity: 1,
            edgeOpacity: 0.40,
            shadowOpacity: 0.20,
            highlightOpacity: 0.20
        )

        let contrast = SidebarGlassRendering.selectedSpaceIconContrast(for: settings, tintHex: "#F2F7FF")

        XCTAssertEqual(contrast, .dark)
    }

    func testSelectedSpaceIconUsesLightForegroundForSaturatedTint() {
        let settings = SidebarGlassSettings(
            glassOpacity: 0.60,
            tintOpacity: 1,
            edgeOpacity: 0.40,
            shadowOpacity: 0.20,
            highlightOpacity: 0.20
        )

        let contrast = SidebarGlassRendering.selectedSpaceIconContrast(for: settings, tintHex: "#4F7CAC")

        XCTAssertEqual(contrast, .light)
    }

    func testSelectedSpaceIconUsesAdaptiveForegroundForNeutralSidebar() {
        let settings = SidebarGlassSettings(
            glassOpacity: 0.60,
            tintOpacity: 0,
            edgeOpacity: 0.40,
            shadowOpacity: 0.20,
            highlightOpacity: 0.20
        )

        let contrast = SidebarGlassRendering.selectedSpaceIconContrast(for: settings, tintHex: "#F2F7FF")

        XCTAssertEqual(contrast, .adaptive)
    }

}
