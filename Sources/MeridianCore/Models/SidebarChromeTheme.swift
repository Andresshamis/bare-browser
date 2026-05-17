import Foundation

public struct SidebarChromeTheme: Equatable, Sendable {
    public static let standard = SidebarChromeTheme(
        appearance: .standard,
        spaceColorHex: "#4F7CAC"
    )

    public var appearance: SidebarAppearance
    public var spaceColorHex: String

    public init(
        appearance: SidebarAppearance,
        spaceColorHex: String
    ) {
        self.appearance = appearance
        self.spaceColorHex = spaceColorHex
    }

    public var tintHex: String {
        appearance.tintHex(forSpaceColorHex: spaceColorHex)
    }

    public static func theme(for space: BrowserSpace) -> SidebarChromeTheme {
        SidebarChromeTheme(
            appearance: space.sidebarAppearance,
            spaceColorHex: space.colorHex
        )
    }

    public static func interpolated(
        spaces: [BrowserSpace],
        fractionalIndex: Double
    ) -> SidebarChromeTheme? {
        guard !spaces.isEmpty else {
            return nil
        }

        let lastIndex = spaces.count - 1
        let boundedIndex = min(
            max(fractionalIndex.isFinite ? fractionalIndex : 0, 0),
            Double(lastIndex)
        )
        let lowerIndex = Int(floor(boundedIndex))
        let upperIndex = Int(ceil(boundedIndex))

        guard lowerIndex != upperIndex else {
            return theme(for: spaces[lowerIndex])
        }

        let progress = boundedIndex - Double(lowerIndex)
        let lowerSpace = spaces[lowerIndex]
        let upperSpace = spaces[upperIndex]
        let lowerAppearance = lowerSpace.sidebarAppearance
        let upperAppearance = upperSpace.sidebarAppearance
        let lowerTint = RGBHexColor(hex: lowerAppearance.tintHex(forSpaceColorHex: lowerSpace.colorHex))
        let upperTint = RGBHexColor(hex: upperAppearance.tintHex(forSpaceColorHex: upperSpace.colorHex))
        let blendedTintHex = RGBHexColor.interpolated(from: lowerTint, to: upperTint, progress: progress).hexString
        let blendedSpaceColorHex = RGBHexColor.interpolated(
            from: RGBHexColor(hex: lowerSpace.colorHex),
            to: RGBHexColor(hex: upperSpace.colorHex),
            progress: progress
        ).hexString

        return SidebarChromeTheme(
            appearance: SidebarAppearance(
                tintSource: .custom,
                tintHex: blendedTintHex,
                base: SidebarGlassSettings.interpolated(
                    from: lowerAppearance.base,
                    to: upperAppearance.base,
                    progress: progress
                ),
                pinnedOverride: SidebarGlassSettings.interpolated(
                    from: lowerAppearance.pinnedSettings,
                    to: upperAppearance.pinnedSettings,
                    progress: progress
                )
            ),
            spaceColorHex: blendedSpaceColorHex
        )
    }
}

extension SidebarGlassSettings {
    static func interpolated(
        from lower: SidebarGlassSettings,
        to upper: SidebarGlassSettings,
        progress: Double
    ) -> SidebarGlassSettings {
        SidebarGlassSettings(
            glassOpacity: lerp(lower.glassOpacity, upper.glassOpacity, progress: progress),
            tintOpacity: lerp(lower.tintOpacity, upper.tintOpacity, progress: progress),
            colorNoiseLevel: lerp(lower.colorNoiseLevel, upper.colorNoiseLevel, progress: progress),
            colorNoiseScale: lerp(lower.colorNoiseScale, upper.colorNoiseScale, progress: progress),
            edgeOpacity: lerp(lower.edgeOpacity, upper.edgeOpacity, progress: progress),
            shadowOpacity: lerp(lower.shadowOpacity, upper.shadowOpacity, progress: progress),
            highlightOpacity: lerp(lower.highlightOpacity, upper.highlightOpacity, progress: progress)
        )
    }

    private static func lerp(_ lower: Double, _ upper: Double, progress: Double) -> Double {
        lower + (upper - lower) * min(max(progress, 0), 1)
    }
}

private struct RGBHexColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
    }

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = cleaned.count == 6 ? UInt64(cleaned, radix: 16) ?? 0x4F7CAC : 0x4F7CAC

        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    static func interpolated(
        from lower: RGBHexColor,
        to upper: RGBHexColor,
        progress: Double
    ) -> RGBHexColor {
        let boundedProgress = min(max(progress, 0), 1)

        return RGBHexColor(
            red: lower.red + (upper.red - lower.red) * boundedProgress,
            green: lower.green + (upper.green - lower.green) * boundedProgress,
            blue: lower.blue + (upper.blue - lower.blue) * boundedProgress
        )
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
