import Foundation

struct SidebarGlassRecipe: Equatable {
    let density: Double
    let colorMix: Double
    let totalFillOpacity: Double
    let neutralFillOpacity: Double
    let themeFillOpacity: Double
    let themeGlassTintOpacity: Double
    let neutralHighlightOpacity: Double
    let themeHighlightOpacity: Double
    let shadowOpacity: Double
}

enum SidebarSelectedIconContrast: Equatable {
    case adaptive
    case dark
    case light
}

enum SidebarGlassRendering {
    private static let fixedColorNoiseScale = 0.0

    static func recipe(for settings: SidebarGlassSettings) -> SidebarGlassRecipe {
        let density = clamped(settings.glassOpacity)
        let colorMix = clamped(settings.tintOpacity)
        let densityResponse = pow(density, 1.2)
        let clearThemeResponse = pow(1 - densityResponse, 1.15)
        let neutralFillOpacity = clamped(densityResponse * (1 - colorMix))
        let themeFillOpacity = clamped((densityResponse + clearThemeResponse * 0.24) * colorMix)
        let totalFillOpacity = clamped(neutralFillOpacity + themeFillOpacity)
        let totalHighlightOpacity = clamped(settings.highlightOpacity * densityResponse * 0.45)

        return SidebarGlassRecipe(
            density: density,
            colorMix: colorMix,
            totalFillOpacity: totalFillOpacity,
            neutralFillOpacity: neutralFillOpacity,
            themeFillOpacity: themeFillOpacity,
            themeGlassTintOpacity: clamped((0.16 * clearThemeResponse + 0.34 * densityResponse) * colorMix),
            neutralHighlightOpacity: totalHighlightOpacity * (1 - colorMix),
            themeHighlightOpacity: totalHighlightOpacity * colorMix,
            shadowOpacity: clamped(settings.shadowOpacity * densityResponse)
        )
    }

    static func glassTintOpacity(for settings: SidebarGlassSettings) -> Double {
        recipe(for: settings).themeGlassTintOpacity
    }

    static func neutralMaterialOpacity(for settings: SidebarGlassSettings) -> Double {
        recipe(for: settings).neutralFillOpacity
    }

    static func themeColorOpacity(for settings: SidebarGlassSettings) -> Double {
        recipe(for: settings).themeFillOpacity
    }

    static func neutralHighlightOpacity(for settings: SidebarGlassSettings) -> Double {
        recipe(for: settings).neutralHighlightOpacity
    }

    static func themeHighlightOpacity(for settings: SidebarGlassSettings) -> Double {
        recipe(for: settings).themeHighlightOpacity
    }

    static func shadowOpacity(for settings: SidebarGlassSettings) -> Double {
        recipe(for: settings).shadowOpacity
    }

    static func colorNoiseOpacity(for settings: SidebarGlassSettings) -> Double {
        colorNoiseOpacity(forLevel: settings.colorNoiseLevel)
    }

    static func colorNoiseOpacity(forLevel level: Double) -> Double {
        pow(clamped(level), 1.10) * 0.30
    }

    static func colorNoiseCellSize(for settings: SidebarGlassSettings) -> CGFloat {
        colorNoiseCellSize()
    }

    static func colorNoiseCellSize() -> CGFloat {
        colorNoiseCellSize(forScale: fixedColorNoiseScale)
    }

    static func colorNoiseCellSize(forScale scale: Double) -> CGFloat {
        CGFloat(1.2 + pow(clamped(scale), 1.8) * 10)
    }

    static func colorNoiseTextureCellSize() -> CGFloat {
        colorNoiseTextureCellSize(forScale: fixedColorNoiseScale)
    }

    static func colorNoiseTextureCellSize(forScale scale: Double) -> CGFloat {
        let rawCellSize = colorNoiseCellSize(forScale: scale)
        let quantizationStep: CGFloat = 0.25
        return max(1, (rawCellSize / quantizationStep).rounded() * quantizationStep)
    }

    static func selectedSpaceIconContrast(for settings: SidebarGlassSettings, tintHex: String) -> SidebarSelectedIconContrast {
        let recipe = recipe(for: settings)
        let tintInfluence = recipe.themeFillOpacity + recipe.themeGlassTintOpacity

        guard tintInfluence >= 0.18 else {
            return .adaptive
        }

        return relativeLuminance(forHex: tintHex) >= 0.72 ? .dark : .light
    }

    private static func relativeLuminance(forHex hex: String) -> Double {
        let fallback = RGBComponents(red: 0.31, green: 0.49, blue: 0.67)
        let components = RGBComponents(hex: hex) ?? fallback

        let red = linearized(components.red)
        let green = linearized(components.green)
        let blue = linearized(components.blue)

        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.03928
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private struct RGBComponents {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            return nil
        }

        red = Double((value >> 16) & 0xff) / 255
        green = Double((value >> 8) & 0xff) / 255
        blue = Double(value & 0xff) / 255
    }
}
