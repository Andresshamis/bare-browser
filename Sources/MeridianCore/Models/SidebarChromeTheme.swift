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
        interpolated(themes: spaces.map(theme(for:)), fractionalIndex: fractionalIndex)
    }

    public static func interpolated(
        themes: [SidebarChromeTheme],
        fractionalIndex: Double
    ) -> SidebarChromeTheme? {
        guard !themes.isEmpty else {
            return nil
        }

        let lastIndex = themes.count - 1
        let boundedIndex = min(
            max(fractionalIndex.isFinite ? fractionalIndex : 0, 0),
            Double(lastIndex)
        )
        let lowerIndex = Int(floor(boundedIndex))
        let upperIndex = Int(ceil(boundedIndex))

        guard lowerIndex != upperIndex else {
            return themes[lowerIndex]
        }

        let progress = boundedIndex - Double(lowerIndex)
        let lowerTheme = themes[lowerIndex]
        let upperTheme = themes[upperIndex]
        let lowerAppearance = lowerTheme.appearance
        let upperAppearance = upperTheme.appearance
        let lowerTint = RGBHexColor(hex: lowerTheme.tintHex)
        let upperTint = RGBHexColor(hex: upperTheme.tintHex)
        let blendedTintHex = RGBHexColor.interpolated(from: lowerTint, to: upperTint, progress: progress).hexString
        let blendedSpaceColorHex = RGBHexColor.interpolated(
            from: RGBHexColor(hex: lowerTheme.spaceColorHex),
            to: RGBHexColor(hex: upperTheme.spaceColorHex),
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

/// The resolved color needed for the sidebar's live paging transition.
///
/// This deliberately excludes glass settings so a scroll-linked color update
/// does not require rebuilding the heavier glass configuration every frame.
public struct SidebarChromeColor: Equatable, Sendable {
    let redComponent: Double
    let greenComponent: Double
    let blueComponent: Double

    public var tintHex: String {
        RGBHexColor(
            red: redComponent,
            green: greenComponent,
            blue: blueComponent
        ).hexString
    }

    public init(tintHex: String) {
        let color = RGBHexColor(hex: tintHex)
        redComponent = color.red
        greenComponent = color.green
        blueComponent = color.blue
    }

    public init(theme: SidebarChromeTheme) {
        self.init(tintHex: theme.tintHex)
    }

    public static func interpolated(
        themes: [SidebarChromeTheme],
        fractionalIndex: Double
    ) -> SidebarChromeColor? {
        guard !themes.isEmpty else {
            return nil
        }

        let lastIndex = themes.count - 1
        let finiteIndex = fractionalIndex.isFinite ? fractionalIndex : 0
        let boundedIndex = min(max(finiteIndex, 0), Double(lastIndex))
        let lowerIndex = Int(boundedIndex)
        let progress = boundedIndex - Double(lowerIndex)

        guard lowerIndex < lastIndex, progress > 0 else {
            return SidebarChromeColor(theme: themes[lowerIndex])
        }

        return interpolated(
            from: themes[lowerIndex],
            to: themes[lowerIndex + 1],
            progress: progress
        )
    }

    static func interpolated(
        from lowerTheme: SidebarChromeTheme,
        to upperTheme: SidebarChromeTheme,
        progress: Double
    ) -> SidebarChromeColor {
        interpolated(
            from: SidebarChromeColor(theme: lowerTheme),
            to: SidebarChromeColor(theme: upperTheme),
            progress: progress
        )
    }

    static func interpolated(
        from lowerColor: SidebarChromeColor,
        to upperColor: SidebarChromeColor,
        progress: Double
    ) -> SidebarChromeColor {
        SidebarChromeColor(
            rgbColor: RGBHexColor.interpolated(
                from: RGBHexColor(
                    red: lowerColor.redComponent,
                    green: lowerColor.greenComponent,
                    blue: lowerColor.blueComponent
                ),
                to: RGBHexColor(
                    red: upperColor.redComponent,
                    green: upperColor.greenComponent,
                    blue: upperColor.blueComponent
                ),
                progress: progress
            )
        )
    }

    private init(rgbColor: RGBHexColor) {
        redComponent = rgbColor.red
        greenComponent = rgbColor.green
        blueComponent = rgbColor.blue
    }
}

/// The scalar appearance values that can be applied by the lightweight live
/// compositor while paging. Native glass structure and the tab-row tree remain
/// settled so display-cadence updates do not rebuild either one.
public struct SidebarChromeColorTreatment: Equatable, Sendable {
    public let glassOpacity: Double
    public let tintOpacity: Double
    public let colorNoiseLevel: Double
    public let colorNoiseScale: Double
    public let edgeOpacity: Double
    public let shadowOpacity: Double
    public let highlightOpacity: Double

    public init(settings: SidebarGlassSettings) {
        glassOpacity = settings.glassOpacity
        tintOpacity = settings.tintOpacity
        colorNoiseLevel = settings.colorNoiseLevel
        colorNoiseScale = settings.colorNoiseScale
        edgeOpacity = settings.edgeOpacity
        shadowOpacity = settings.shadowOpacity
        highlightOpacity = settings.highlightOpacity
    }

    fileprivate static func interpolated(
        from lower: SidebarChromeColorTreatment,
        to upper: SidebarChromeColorTreatment,
        progress: Double
    ) -> SidebarChromeColorTreatment {
        let progress = min(max(progress, 0), 1)
        return SidebarChromeColorTreatment(
            glassOpacity: lower.glassOpacity
                + (upper.glassOpacity - lower.glassOpacity) * progress,
            tintOpacity: lower.tintOpacity
                + (upper.tintOpacity - lower.tintOpacity) * progress,
            colorNoiseLevel: lower.colorNoiseLevel
                + (upper.colorNoiseLevel - lower.colorNoiseLevel) * progress,
            colorNoiseScale: lower.colorNoiseScale
                + (upper.colorNoiseScale - lower.colorNoiseScale) * progress,
            edgeOpacity: lower.edgeOpacity
                + (upper.edgeOpacity - lower.edgeOpacity) * progress,
            shadowOpacity: lower.shadowOpacity
                + (upper.shadowOpacity - lower.shadowOpacity) * progress,
            highlightOpacity: lower.highlightOpacity
                + (upper.highlightOpacity - lower.highlightOpacity) * progress
        )
    }

    private init(
        glassOpacity: Double,
        tintOpacity: Double,
        colorNoiseLevel: Double,
        colorNoiseScale: Double,
        edgeOpacity: Double,
        shadowOpacity: Double,
        highlightOpacity: Double
    ) {
        self.glassOpacity = glassOpacity
        self.tintOpacity = tintOpacity
        self.colorNoiseLevel = colorNoiseLevel
        self.colorNoiseScale = colorNoiseScale
        self.edgeOpacity = edgeOpacity
        self.shadowOpacity = shadowOpacity
        self.highlightOpacity = highlightOpacity
    }
}

/// The resolved light/dark-mode endpoints for theme-aware sidebar foregrounds.
///
/// These values are resolved once per page and interpolated as simple scalars.
/// That avoids both threshold jumps in a blended tint and display-rate work in
/// the tab-row tree.
public struct SidebarChromeForegroundTreatment: Equatable, Sendable {
    public let lightModeWhiteAmount: Double
    public let darkModeWhiteAmount: Double

    init(settings: SidebarGlassSettings, tintHex: String) {
        lightModeWhiteAmount = SidebarGlassRendering.foregroundWhiteAmount(
            for: settings,
            tintHex: tintHex,
            baseWhiteAmount: 0
        )
        darkModeWhiteAmount = SidebarGlassRendering.foregroundWhiteAmount(
            for: settings,
            tintHex: tintHex,
            baseWhiteAmount: 1
        )
    }

    fileprivate static func interpolated(
        from lower: SidebarChromeForegroundTreatment,
        to upper: SidebarChromeForegroundTreatment,
        progress: Double
    ) -> SidebarChromeForegroundTreatment {
        let progress = min(max(progress, 0), 1)
        return SidebarChromeForegroundTreatment(
            lightModeWhiteAmount: lower.lightModeWhiteAmount
                + (upper.lightModeWhiteAmount - lower.lightModeWhiteAmount) * progress,
            darkModeWhiteAmount: lower.darkModeWhiteAmount
                + (upper.darkModeWhiteAmount - lower.darkModeWhiteAmount) * progress
        )
    }

    private init(
        lightModeWhiteAmount: Double,
        darkModeWhiteAmount: Double
    ) {
        self.lightModeWhiteAmount = lightModeWhiteAmount
        self.darkModeWhiteAmount = darkModeWhiteAmount
    }
}

/// The complete payload consumed by the compositor-only paging treatment.
///
/// It intentionally cannot carry native glass structure or tab-row styling, so
/// interpolating it at display cadence stays isolated from the expensive tree.
public struct SidebarChromeLiveStyle: Equatable, Sendable {
    public let color: SidebarChromeColor
    public let baseTreatment: SidebarChromeColorTreatment
    public let pinnedTreatment: SidebarChromeColorTreatment
    public let baseForeground: SidebarChromeForegroundTreatment
    public let pinnedForeground: SidebarChromeForegroundTreatment

    public init(theme: SidebarChromeTheme) {
        color = SidebarChromeColor(theme: theme)
        baseTreatment = SidebarChromeColorTreatment(settings: theme.appearance.base)
        pinnedTreatment = SidebarChromeColorTreatment(settings: theme.appearance.pinnedSettings)
        baseForeground = SidebarChromeForegroundTreatment(
            settings: theme.appearance.base,
            tintHex: theme.tintHex
        )
        pinnedForeground = SidebarChromeForegroundTreatment(
            settings: theme.appearance.pinnedSettings,
            tintHex: theme.tintHex
        )
    }

    public static func interpolated(
        themes: [SidebarChromeTheme],
        fractionalIndex: Double
    ) -> SidebarChromeLiveStyle? {
        interpolated(
            styles: themes.map(SidebarChromeLiveStyle.init(theme:)),
            fractionalIndex: fractionalIndex
        )
    }

    public static func interpolated(
        styles: [SidebarChromeLiveStyle],
        fractionalIndex: Double
    ) -> SidebarChromeLiveStyle? {
        guard !styles.isEmpty else {
            return nil
        }

        let lastIndex = styles.count - 1
        let finiteIndex = fractionalIndex.isFinite ? fractionalIndex : 0
        let boundedIndex = min(max(finiteIndex, 0), Double(lastIndex))
        let lowerIndex = Int(boundedIndex)
        let progress = boundedIndex - Double(lowerIndex)

        guard lowerIndex < lastIndex, progress > 0 else {
            return styles[lowerIndex]
        }

        let lowerStyle = styles[lowerIndex]
        let upperStyle = styles[lowerIndex + 1]
        let color = SidebarChromeColor.interpolated(
            from: lowerStyle.color,
            to: upperStyle.color,
            progress: progress
        )

        return SidebarChromeLiveStyle(
            color: color,
            baseTreatment: SidebarChromeColorTreatment.interpolated(
                from: lowerStyle.baseTreatment,
                to: upperStyle.baseTreatment,
                progress: progress
            ),
            pinnedTreatment: SidebarChromeColorTreatment.interpolated(
                from: lowerStyle.pinnedTreatment,
                to: upperStyle.pinnedTreatment,
                progress: progress
            ),
            baseForeground: SidebarChromeForegroundTreatment.interpolated(
                from: lowerStyle.baseForeground,
                to: upperStyle.baseForeground,
                progress: progress
            ),
            pinnedForeground: SidebarChromeForegroundTreatment.interpolated(
                from: lowerStyle.pinnedForeground,
                to: upperStyle.pinnedForeground,
                progress: progress
            )
        )
    }

    private init(
        color: SidebarChromeColor,
        baseTreatment: SidebarChromeColorTreatment,
        pinnedTreatment: SidebarChromeColorTreatment,
        baseForeground: SidebarChromeForegroundTreatment,
        pinnedForeground: SidebarChromeForegroundTreatment
    ) {
        self.color = color
        self.baseTreatment = baseTreatment
        self.pinnedTreatment = pinnedTreatment
        self.baseForeground = baseForeground
        self.pinnedForeground = pinnedForeground
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
