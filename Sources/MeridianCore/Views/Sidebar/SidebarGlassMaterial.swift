import AppKit
import QuartzCore
import SwiftUI

struct SidebarGlassMaterial<ClipShape: Shape>: View {
    let shape: ClipShape
    let tintColor: Color
    let settings: SidebarGlassSettings

    var body: some View {
        SidebarGlassSystemMaterial(
            shape: shape,
            tintColor: tintColor,
            settings: settings
        )
            .overlay {
                SidebarGlassTintOverlay(shape: shape, tintColor: tintColor, settings: settings)
            }
            .overlay {
                SidebarColorNoiseOverlay(
                    level: settings.colorNoiseLevel,
                    scale: settings.colorNoiseScale,
                    shape: shape
                )
            }
    }
}

/// The native system-glass surface without Meridian's color treatment.
///
/// Keeping this view separate lets the sidebar retain one stable Liquid Glass
/// render surface while its inexpensive color layers track paging progress.
struct SidebarGlassSystemMaterial<ClipShape: Shape>: View {
    let shape: ClipShape
    let tintColor: Color
    let settings: SidebarGlassSettings

    var body: some View {
        shape
            .fill(.clear)
            .glassEffect(
                .regular
                    .tint(tintColor.opacity(SidebarGlassRendering.glassTintOpacity(for: settings)))
                    .interactive(false),
                in: shape
            )
            .compositingGroup()
    }
}

/// One theme-independent native glass surface for the live browser sidebar.
///
/// All hue is supplied by `SidebarChromeLiveTintOverlay`, so reaching the end
/// of a page spring never has to swap the native material's tint.
struct SidebarNeutralGlassSystemMaterial<ClipShape: Shape>: View {
    let shape: ClipShape

    var body: some View {
        shape
            .fill(.clear)
            .glassEffect(
                .regular.interactive(false),
                in: shape
            )
            .compositingGroup()
    }
}

@MainActor
private protocol SidebarChromeLiveStyleRendering: AnyObject {
    func setLiveStyle(_ style: SidebarChromeLiveStyle?)
}

@MainActor
private final class SidebarChromeWeakRenderer {
    weak var renderer: (any SidebarChromeLiveStyleRendering)?

    init(_ renderer: any SidebarChromeLiveStyleRendering) {
        self.renderer = renderer
    }
}

/// A reference-only bridge for display-rate sidebar chrome updates.
///
/// This deliberately does not conform to `ObservableObject`: every live sample
/// terminates at retained Core Animation layers and cannot invalidate tabs.
@MainActor
final class SidebarChromeLiveStyleController {
    private var style: SidebarChromeLiveStyle?
    private var renderers: [SidebarChromeWeakRenderer] = []

    func update(_ style: SidebarChromeLiveStyle?) {
        guard self.style != style else {
            return
        }

        self.style = style
        renderers.removeAll { $0.renderer == nil }
        for renderer in renderers {
            renderer.renderer?.setLiveStyle(style)
        }
    }

    fileprivate func attach(_ renderer: any SidebarChromeLiveStyleRendering) {
        renderers.removeAll {
            guard let attachedRenderer = $0.renderer else {
                return true
            }
            return attachedRenderer === renderer
        }
        renderers.append(SidebarChromeWeakRenderer(renderer))
        renderer.setLiveStyle(style)
    }

    fileprivate func detach(_ renderer: any SidebarChromeLiveStyleRendering) {
        renderers.removeAll {
            guard let attachedRenderer = $0.renderer else {
                return true
            }
            return attachedRenderer === renderer
        }
    }
}

/// A compositor-only color treatment for the live sidebar chrome.
///
/// Its retained mask owns clipping for fills, texture, and edge geometry.
/// Pinned/floating presentation is stable SwiftUI configuration; only
/// `SidebarChromeLiveStyleController.update(_:)` is expected at display rate.
struct SidebarChromeLiveTintOverlay: NSViewRepresentable {
    let controller: SidebarChromeLiveStyleController
    let fallbackStyle: SidebarChromeLiveStyle
    let pinnedOpacity: Double
    let floatingOpacity: Double
    let cornerRadii: SidebarChromeCornerRadii

    func makeNSView(context: Context) -> NSView {
        let view = SidebarChromeLiveTintView()
        view.updateConfiguration(
            fallbackStyle: fallbackStyle,
            pinnedOpacity: pinnedOpacity,
            floatingOpacity: floatingOpacity,
            cornerRadii: cornerRadii
        )
        view.attach(to: controller)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let tintView = nsView as? SidebarChromeLiveTintView else {
            assertionFailure("Unexpected sidebar live tint renderer")
            return
        }

        tintView.updateConfiguration(
            fallbackStyle: fallbackStyle,
            pinnedOpacity: pinnedOpacity,
            floatingOpacity: floatingOpacity,
            cornerRadii: cornerRadii
        )
        tintView.attach(to: controller)
    }

    static func dismantleNSView(
        _ nsView: NSView,
        coordinator: ()
    ) {
        (nsView as? SidebarChromeLiveTintView)?.detachFromController()
    }
}

@MainActor
private final class SidebarChromeLiveTintView: NSView, SidebarChromeLiveStyleRendering {
    private struct Configuration: Equatable {
        let fallbackStyle: SidebarChromeLiveStyle
        let pinnedOpacity: Double
        let floatingOpacity: Double
        let cornerRadii: SidebarChromeCornerRadii
    }

    private let interiorLayer = CALayer()
    private let baseTreatment = SidebarChromeTintTreatment()
    private let pinnedTreatment = SidebarChromeTintTreatment()
    private let edgeLayer = CAShapeLayer()
    private weak var styleController: SidebarChromeLiveStyleController?
    private var configuration: Configuration?
    private var liveStyle: SidebarChromeLiveStyle?
    private var neutralColor: CGColor?
    private var separatorColor: CGColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayerTree()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayerTree()
    }

    override func layout() {
        super.layout()

        withoutImplicitLayerActions {
            interiorLayer.frame = bounds
            baseTreatment.setFrame(bounds)
            pinnedTreatment.setFrame(bounds)
            updateLayerGeometry()
            updateLayerContentsScale()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        neutralColor = resolvedWindowBackgroundColor()
        separatorColor = resolvedSeparatorColor()
        applyPresentation()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        withoutImplicitLayerActions {
            updateLayerContentsScale()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func updateConfiguration(
        fallbackStyle: SidebarChromeLiveStyle,
        pinnedOpacity: Double,
        floatingOpacity: Double,
        cornerRadii: SidebarChromeCornerRadii
    ) {
        let newConfiguration = Configuration(
            fallbackStyle: fallbackStyle,
            pinnedOpacity: Self.normalizedOpacity(pinnedOpacity),
            floatingOpacity: Self.normalizedOpacity(floatingOpacity),
            cornerRadii: cornerRadii
        )
        guard configuration != newConfiguration else {
            return
        }

        configuration = newConfiguration
        if neutralColor == nil {
            neutralColor = resolvedWindowBackgroundColor()
        }
        if separatorColor == nil {
            separatorColor = resolvedSeparatorColor()
        }
        withoutImplicitLayerActions {
            updateLayerGeometry()
        }
        applyPresentation()
    }

    func attach(to controller: SidebarChromeLiveStyleController) {
        guard styleController !== controller else {
            return
        }

        styleController?.detach(self)
        styleController = controller
        controller.attach(self)
    }

    func detachFromController() {
        styleController?.detach(self)
        styleController = nil
    }

    func setLiveStyle(_ style: SidebarChromeLiveStyle?) {
        guard liveStyle != style else {
            return
        }

        liveStyle = style
        applyPresentation()
    }

    private func configureLayerTree() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        guard let layer else {
            return
        }

        withoutImplicitLayerActions {
            layer.masksToBounds = false
            interiorLayer.masksToBounds = true
            interiorLayer.cornerCurve = .continuous
            interiorLayer.addSublayer(baseTreatment.layer)
            interiorLayer.addSublayer(pinnedTreatment.layer)
            layer.addSublayer(interiorLayer)

            edgeLayer.fillColor = nil
            edgeLayer.lineWidth = 0.5
            layer.addSublayer(edgeLayer)
        }
    }

    private func applyPresentation() {
        guard let configuration,
              let neutralColor,
              let separatorColor else {
            return
        }

        let style = liveStyle ?? configuration.fallbackStyle
        let tintColor = Self.tintColor(for: style.color)
        let usesSharedTreatment = style.baseTreatment == style.pinnedTreatment

        withoutImplicitLayerActions {
            if usesSharedTreatment || configuration.pinnedOpacity <= 0 {
                baseTreatment.update(
                    treatment: style.baseTreatment,
                    recipe: SidebarGlassRendering.recipe(for: style.baseTreatment),
                    neutralColor: neutralColor,
                    tintColor: tintColor
                )
                Self.setOpacity(1, on: baseTreatment.layer)
                Self.setOpacity(0, on: pinnedTreatment.layer)
            } else if configuration.floatingOpacity <= 0 {
                baseTreatment.update(
                    treatment: style.pinnedTreatment,
                    recipe: SidebarGlassRendering.recipe(for: style.pinnedTreatment),
                    neutralColor: neutralColor,
                    tintColor: tintColor
                )
                Self.setOpacity(1, on: baseTreatment.layer)
                Self.setOpacity(0, on: pinnedTreatment.layer)
            } else {
                baseTreatment.update(
                    treatment: style.baseTreatment,
                    recipe: SidebarGlassRendering.recipe(for: style.baseTreatment),
                    neutralColor: neutralColor,
                    tintColor: tintColor
                )
                pinnedTreatment.update(
                    treatment: style.pinnedTreatment,
                    recipe: SidebarGlassRendering.recipe(for: style.pinnedTreatment),
                    neutralColor: neutralColor,
                    tintColor: tintColor
                )
                Self.setOpacity(Float(configuration.floatingOpacity), on: baseTreatment.layer)
                Self.setOpacity(Float(configuration.pinnedOpacity), on: pinnedTreatment.layer)
            }

            if edgeLayer.strokeColor != separatorColor {
                edgeLayer.strokeColor = separatorColor
            }
            Self.setOpacity(Float(
                Self.normalizedOpacity(style.baseTreatment.edgeOpacity)
                    * configuration.floatingOpacity
            ), on: edgeLayer)
        }
    }

    private func updateLayerGeometry() {
        guard let configuration else {
            return
        }

        interiorLayer.cornerRadius = configuration.cornerRadii.maximumRadius
        interiorLayer.maskedCorners = configuration.cornerRadii.layerMaskedCorners
        edgeLayer.frame = bounds
        edgeLayer.path = configuration.cornerRadii.path(in: bounds.insetBy(dx: 0.25, dy: 0.25))
    }

    private func updateLayerContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        edgeLayer.contentsScale = scale
        baseTreatment.setContentsScale(scale)
        pinnedTreatment.setContentsScale(scale)
    }

    private func resolvedWindowBackgroundColor() -> CGColor {
        var resolvedColor = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = NSColor.windowBackgroundColor.cgColor
        }
        return resolvedColor
    }

    private func resolvedSeparatorColor() -> CGColor {
        var resolvedColor = NSColor.separatorColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = NSColor.separatorColor.cgColor
        }
        return resolvedColor
    }

    private static func tintColor(for color: SidebarChromeColor) -> CGColor {
        return NSColor(
            srgbRed: CGFloat(color.redComponent),
            green: CGFloat(color.greenComponent),
            blue: CGFloat(color.blueComponent),
            alpha: 1
        ).cgColor
    }

    private static func normalizedOpacity(_ opacity: Double) -> Double {
        guard opacity.isFinite else {
            return 0
        }

        return min(max(opacity, 0), 1)
    }

    private static func setOpacity(_ opacity: Float, on layer: CALayer) {
        guard layer.opacity != opacity else {
            return
        }
        layer.opacity = opacity
    }
}

private extension SidebarChromeCornerRadii {
    var layerMaskedCorners: CACornerMask {
        var corners: CACornerMask = []
        if bottomLeading > 0 {
            corners.insert(.layerMinXMinYCorner)
        }
        if topLeading > 0 {
            corners.insert(.layerMinXMaxYCorner)
        }
        if bottomTrailing > 0 {
            corners.insert(.layerMaxXMinYCorner)
        }
        if topTrailing > 0 {
            corners.insert(.layerMaxXMaxYCorner)
        }
        return corners
    }
}

/// The live shadow stays behind the neutral glass surface and uses an explicit
/// path, avoiding per-frame offscreen alpha analysis of the full sidebar.
struct SidebarChromeLiveShadowOverlay: NSViewRepresentable {
    let controller: SidebarChromeLiveStyleController
    let fallbackStyle: SidebarChromeLiveStyle
    let floatingOpacity: Double
    let cornerRadii: SidebarChromeCornerRadii

    func makeNSView(context: Context) -> NSView {
        let view = SidebarChromeLiveShadowView()
        view.updateConfiguration(
            fallbackStyle: fallbackStyle,
            floatingOpacity: floatingOpacity,
            cornerRadii: cornerRadii
        )
        view.attach(to: controller)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let shadowView = nsView as? SidebarChromeLiveShadowView else {
            assertionFailure("Unexpected sidebar live shadow renderer")
            return
        }

        shadowView.updateConfiguration(
            fallbackStyle: fallbackStyle,
            floatingOpacity: floatingOpacity,
            cornerRadii: cornerRadii
        )
        shadowView.attach(to: controller)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? SidebarChromeLiveShadowView)?.detachFromController()
    }
}

@MainActor
private final class SidebarChromeLiveShadowView: NSView, SidebarChromeLiveStyleRendering {
    private struct Configuration: Equatable {
        let fallbackStyle: SidebarChromeLiveStyle
        let floatingOpacity: Double
        let cornerRadii: SidebarChromeCornerRadii
    }

    private struct ShadowMaskKey: Equatable {
        let size: CGSize
        let cornerRadii: SidebarChromeCornerRadii
        let backingScale: CGFloat
    }

    private static let shadowRadius: CGFloat = 18
    // CALayer vertically flips bitmap `contents` relative to this unflipped
    // AppKit view. Draw the halo upward in the mask so it displays downward.
    private static let shadowOffset = CGSize(width: 0, height: 8)
    private static let shadowOutset: CGFloat = 64

    private let shadowColorLayer = CALayer()
    private let shadowMaskLayer = CALayer()
    private weak var styleController: SidebarChromeLiveStyleController?
    private var configuration: Configuration?
    private var liveStyle: SidebarChromeLiveStyle?
    private var shadowMaskKey: ShadowMaskKey?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayerTree()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayerTree()
    }

    override func layout() {
        super.layout()
        withoutImplicitLayerActions {
            updateShadowMaskIfNeeded()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        shadowMaskKey = nil
        withoutImplicitLayerActions {
            updateShadowMaskIfNeeded()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func updateConfiguration(
        fallbackStyle: SidebarChromeLiveStyle,
        floatingOpacity: Double,
        cornerRadii: SidebarChromeCornerRadii
    ) {
        let configuration = Configuration(
            fallbackStyle: fallbackStyle,
            floatingOpacity: min(max(floatingOpacity.isFinite ? floatingOpacity : 0, 0), 1),
            cornerRadii: cornerRadii
        )
        guard self.configuration != configuration else {
            return
        }

        self.configuration = configuration
        shadowMaskKey = nil
        withoutImplicitLayerActions {
            updateShadowMaskIfNeeded()
        }
        applyPresentation()
    }

    func attach(to controller: SidebarChromeLiveStyleController) {
        guard styleController !== controller else {
            return
        }
        styleController?.detach(self)
        styleController = controller
        controller.attach(self)
    }

    func detachFromController() {
        styleController?.detach(self)
        styleController = nil
    }

    func setLiveStyle(_ style: SidebarChromeLiveStyle?) {
        guard liveStyle != style else {
            return
        }
        liveStyle = style
        applyPresentation()
    }

    private func configureLayerTree() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let layer else {
            return
        }

        withoutImplicitLayerActions {
            layer.masksToBounds = false
            shadowColorLayer.masksToBounds = false
            shadowColorLayer.mask = shadowMaskLayer
            layer.addSublayer(shadowColorLayer)
        }
    }

    private func updateShadowMaskIfNeeded() {
        guard let configuration,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let key = ShadowMaskKey(
            size: bounds.size,
            cornerRadii: configuration.cornerRadii,
            backingScale: backingScale
        )
        guard shadowMaskKey != key else {
            return
        }
        shadowMaskKey = key

        let outset = Self.shadowOutset
        let expandedSize = CGSize(
            width: bounds.width + outset * 2,
            height: bounds.height + outset * 2
        )
        shadowColorLayer.frame = CGRect(
            x: -outset,
            y: -outset,
            width: expandedSize.width,
            height: expandedSize.height
        )
        shadowMaskLayer.frame = shadowColorLayer.bounds
        shadowMaskLayer.contentsScale = backingScale
        shadowMaskLayer.contentsGravity = .resize
        shadowMaskLayer.contents = makeExteriorShadowMask(
            size: bounds.size,
            cornerRadii: configuration.cornerRadii,
            backingScale: backingScale
        )
    }

    private func applyPresentation() {
        guard let configuration else {
            return
        }

        guard configuration.floatingOpacity > 0 else {
            if shadowColorLayer.opacity != 0 {
                withoutImplicitLayerActions {
                    shadowColorLayer.opacity = 0
                }
            }
            return
        }

        let style = liveStyle ?? configuration.fallbackStyle
        let recipe = SidebarGlassRendering.recipe(for: style.baseTreatment)
        let opacity = Float(
            min(max(recipe.shadowOpacity, 0), 1) * configuration.floatingOpacity
        )

        withoutImplicitLayerActions {
            if shadowColorLayer.opacity != opacity {
                shadowColorLayer.opacity = opacity
            }
            guard opacity > 0 else {
                return
            }

            let shadowColor = NSColor(
                srgbRed: CGFloat(style.color.redComponent),
                green: CGFloat(style.color.greenComponent),
                blue: CGFloat(style.color.blueComponent),
                alpha: 1
            ).cgColor
            if shadowColorLayer.backgroundColor != shadowColor {
                shadowColorLayer.backgroundColor = shadowColor
            }
        }
    }

    private func makeExteriorShadowMask(
        size: CGSize,
        cornerRadii: SidebarChromeCornerRadii,
        backingScale: CGFloat
    ) -> CGImage? {
        let outset = Self.shadowOutset
        let expandedSize = CGSize(
            width: size.width + outset * 2,
            height: size.height + outset * 2
        )
        let pixelWidth = max(1, Int(ceil(expandedSize.width * backingScale)))
        let pixelHeight = max(1, Int(ceil(expandedSize.height * backingScale)))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 2,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: backingScale, y: backingScale)
        let shapeRect = CGRect(
            x: outset,
            y: outset,
            width: size.width,
            height: size.height
        )
        let shapePath = cornerRadii.path(in: shapeRect)

        let opaqueMaskColor = CGColor(gray: 1, alpha: 1)
        context.setFillColor(opaqueMaskColor)
        context.setShadow(
            // Core Graphics evaluates shadow metrics in device space even
            // though the caster path uses the point-scaled CTM.
            offset: CGSize(
                width: Self.shadowOffset.width * backingScale,
                height: Self.shadowOffset.height * backingScale
            ),
            blur: Self.shadowRadius * backingScale,
            color: opaqueMaskColor
        )
        context.addPath(shapePath)
        context.fillPath()

        // Remove the caster itself. The resulting mask contains only exterior
        // shadow alpha, so no fill can leak through the translucent glass.
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setBlendMode(.clear)
        context.addPath(shapePath)
        context.fillPath()

        return context.makeImage()
    }
}

@MainActor
private final class SidebarChromeTintTreatment {
    let layer = CALayer()
    private let fillLayer = CALayer()
    private let neutralHighlightLayer = CAGradientLayer()
    private let themeHighlightLayer = CAGradientLayer()
    private let noiseTreatment = SidebarChromeNoiseTreatment()
    private var treatment: SidebarChromeColorTreatment?
    private var neutralColor: CGColor?
    private var tintColor: CGColor?

    private struct RGBA {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init() {
        configureLayers()
    }

    func setFrame(_ frame: CGRect) {
        layer.frame = frame
        fillLayer.frame = layer.bounds
        neutralHighlightLayer.frame = layer.bounds
        themeHighlightLayer.frame = layer.bounds
        noiseTreatment.setFrame(layer.bounds)
    }

    func update(
        treatment: SidebarChromeColorTreatment,
        recipe: SidebarGlassRecipe,
        neutralColor: CGColor,
        tintColor: CGColor
    ) {
        let treatmentChanged = self.treatment != treatment
        let neutralColorChanged = self.neutralColor != neutralColor
        let tintColorChanged = self.tintColor != tintColor
        guard treatmentChanged || neutralColorChanged || tintColorChanged else {
            return
        }

        self.treatment = treatment
        self.neutralColor = neutralColor
        self.tintColor = tintColor

        // Precompose the neutral and themed solids. The previous two full-size
        // layers produced the same source-over result at twice the fill cost.
        let fillColor = Self.compositedFillColor(
            neutralColor: neutralColor,
            neutralOpacity: recipe.neutralFillOpacity,
            tintColor: tintColor,
            tintOpacity: SidebarGlassRendering.liveThemeColorOpacity(for: recipe)
        )
        if fillLayer.backgroundColor != fillColor {
            fillLayer.backgroundColor = fillColor
        }

        if treatmentChanged {
            let neutralHighlightOpacity = Float(recipe.neutralHighlightOpacity)
            if neutralHighlightLayer.opacity != neutralHighlightOpacity {
                neutralHighlightLayer.opacity = neutralHighlightOpacity
            }
            let themeHighlightOpacity = Float(recipe.themeHighlightOpacity)
            if themeHighlightLayer.opacity != themeHighlightOpacity {
                themeHighlightLayer.opacity = themeHighlightOpacity
            }
            noiseTreatment.update(
                level: treatment.colorNoiseLevel,
                scale: treatment.colorNoiseScale
            )
        }

        if tintColorChanged {
            let clearTint = tintColor.copy(alpha: 0) ?? NSColor.clear.cgColor
            themeHighlightLayer.colors = [clearTint, tintColor, clearTint]
        }
    }

    func setContentsScale(_ scale: CGFloat) {
        fillLayer.contentsScale = scale
        neutralHighlightLayer.contentsScale = scale
        themeHighlightLayer.contentsScale = scale
        noiseTreatment.setContentsScale(scale)
    }

    private func configureLayers() {
        layer.masksToBounds = false
        layer.needsDisplayOnBoundsChange = false

        configureHighlightGradient(
            neutralHighlightLayer,
            colors: [
                CGColor(gray: 1, alpha: 1),
                CGColor(gray: 1, alpha: 0),
                CGColor(gray: 1, alpha: 0),
            ]
        )
        configureHighlightGradient(
            themeHighlightLayer,
            colors: [
                CGColor(gray: 1, alpha: 0),
                CGColor(gray: 1, alpha: 1),
                CGColor(gray: 1, alpha: 0),
            ]
        )

        layer.addSublayer(fillLayer)
        layer.addSublayer(neutralHighlightLayer)
        layer.addSublayer(themeHighlightLayer)
        layer.addSublayer(noiseTreatment.layer)
    }

    private func configureHighlightGradient(
        _ gradient: CAGradientLayer,
        colors: [CGColor]
    ) {
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.locations = [0, 0.5, 1]
        gradient.colors = colors
    }

    private static func compositedFillColor(
        neutralColor: CGColor,
        neutralOpacity: Double,
        tintColor: CGColor,
        tintOpacity: Double
    ) -> CGColor {
        let neutral = rgba(neutralColor)
        let tint = rgba(tintColor)
        let neutralAlpha = clamped(neutralOpacity) * neutral.alpha
        let tintAlpha = clamped(tintOpacity) * tint.alpha
        let survivingNeutralAlpha = neutralAlpha * (1 - tintAlpha)
        let outputAlpha = tintAlpha + survivingNeutralAlpha

        guard outputAlpha > 0.000_001 else {
            return CGColor(colorSpace: sRGBColorSpace, components: [0, 0, 0, 0])
                ?? NSColor.clear.cgColor
        }

        let red = (tint.red * tintAlpha + neutral.red * survivingNeutralAlpha) / outputAlpha
        let green = (tint.green * tintAlpha + neutral.green * survivingNeutralAlpha) / outputAlpha
        let blue = (tint.blue * tintAlpha + neutral.blue * survivingNeutralAlpha) / outputAlpha
        return CGColor(
            colorSpace: sRGBColorSpace,
            components: [red, green, blue, outputAlpha]
        ) ?? tintColor
    }

    private static func rgba(_ color: CGColor) -> RGBA {
        let converted = color.converted(
            to: sRGBColorSpace,
            intent: .defaultIntent,
            options: nil
        ) ?? color
        let components = converted.components ?? []

        if components.count >= 3 {
            return RGBA(
                red: components[0],
                green: components[1],
                blue: components[2],
                alpha: converted.alpha
            )
        }

        let white = components.first ?? 0
        return RGBA(red: white, green: white, blue: white, alpha: converted.alpha)
    }

    private static func clamped(_ value: Double) -> CGFloat {
        guard value.isFinite else {
            return 0
        }
        return CGFloat(min(max(value, 0), 1))
    }
}

@MainActor
private final class SidebarChromeNoiseTreatment {
    let layer = CALayer()
    private let textureLayer = CALayer()
    private var tileLayers: [CALayer] = []
    private var appliedOpacity: Float?
    private var appliedScaleFactor: CGFloat?
    private let tilePointSize = SidebarColorNoiseTextureCache.tilePointSizeForLayer
    // One point is exactly representable at both 1x and 2x. The live transform
    // then expresses the requested visual cell size without raster rounding.
    private let rasterCellSize: CGFloat = 1

    init() {
        layer.masksToBounds = true
        layer.needsDisplayOnBoundsChange = false
        textureLayer.anchorPoint = CGPoint(x: 0, y: 0)
        textureLayer.position = .zero
        layer.addSublayer(textureLayer)
    }

    func setFrame(_ frame: CGRect) {
        layer.frame = frame
        rebuildTilesIfNeeded(for: layer.bounds.size)
    }

    func update(level: Double, scale: Double) {
        let opacity = Float(SidebarGlassRendering.colorNoiseOpacity(forLevel: level))
        if appliedOpacity != opacity {
            appliedOpacity = opacity
            layer.opacity = opacity
        }

        // An invisible texture needs no transform churn. When it becomes
        // visible again, the nilled cache applies the latest requested scale.
        guard opacity > 0 else {
            appliedScaleFactor = nil
            return
        }

        let cellSize = SidebarGlassRendering.colorNoiseCellSize(forScale: scale)
        let scaleFactor = max(cellSize / rasterCellSize, 0.001)
        guard appliedScaleFactor != scaleFactor else {
            return
        }
        appliedScaleFactor = scaleFactor
        textureLayer.transform = CATransform3DMakeScale(scaleFactor, scaleFactor, 1)
    }

    func setContentsScale(_ scale: CGFloat) {
        layer.contentsScale = scale
        textureLayer.contentsScale = scale
        for tileLayer in tileLayers {
            tileLayer.contentsScale = scale
        }
    }

    private func rebuildTilesIfNeeded(for size: CGSize) {
        let columnCount = max(1, Int(ceil(size.width / tilePointSize)))
        let rowCount = max(1, Int(ceil(size.height / tilePointSize)))
        let requiredCount = columnCount * rowCount

        while tileLayers.count < requiredCount {
            let tileLayer = CALayer()
            tileLayer.contents = SidebarColorNoiseTextureCache.cgImage(
                cellSize: rasterCellSize
            )
            tileLayer.contentsGravity = .resize
            tileLayer.minificationFilter = .nearest
            tileLayer.magnificationFilter = .nearest
            tileLayer.needsDisplayOnBoundsChange = false
            textureLayer.addSublayer(tileLayer)
            tileLayers.append(tileLayer)
        }

        for index in tileLayers.indices {
            let isVisible = index < requiredCount
            tileLayers[index].isHidden = !isVisible
            guard isVisible else {
                continue
            }
            let column = index % columnCount
            let row = index / columnCount
            tileLayers[index].frame = CGRect(
                x: CGFloat(column) * tilePointSize,
                y: CGFloat(row) * tilePointSize,
                width: tilePointSize,
                height: tilePointSize
            )
        }

        textureLayer.bounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: CGFloat(columnCount) * tilePointSize,
                height: CGFloat(rowCount) * tilePointSize
            )
        )
        textureLayer.position = .zero
    }
}

private func withoutImplicitLayerActions(_ updates: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    updates()
    CATransaction.commit()
}

private struct SidebarGlassTintOverlay<ClipShape: Shape>: View {
    let shape: ClipShape
    let tintColor: Color
    let settings: SidebarGlassSettings

    var body: some View {
        let recipe = SidebarGlassRendering.recipe(for: settings)

        ZStack {
            shape
                .fill(Color(nsColor: .windowBackgroundColor).opacity(recipe.neutralFillOpacity))

            shape
                .fill(tintColor.opacity(recipe.themeFillOpacity))

            shape.fill(
                LinearGradient(
                    colors: [
                        .white.opacity(recipe.neutralHighlightOpacity),
                        tintColor.opacity(recipe.themeHighlightOpacity),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .allowsHitTesting(false)
    }
}
