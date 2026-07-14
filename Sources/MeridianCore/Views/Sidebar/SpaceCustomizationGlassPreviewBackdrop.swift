import AppKit
import SwiftUI

enum SpaceCustomizationGlassPreviewBackdropSettings {
    static let storageKey = "SpaceCustomizationGlassPreviewBackdropIsEnabled"
}

struct SpaceCustomizationGlassPreviewBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                fallbackBackdrop

                if let image = SpaceCustomizationGlassPreviewBackdropImageCache.image(colorScheme: colorScheme) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: max(proxy.size.width, 1), height: max(proxy.size.height, 1))
                        .clipped()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var fallbackBackdrop: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.04, green: 0.06, blue: 0.11),
                    Color(red: 0.09, green: 0.13, blue: 0.16),
                    Color(red: 0.12, green: 0.10, blue: 0.15)
                ]
                : [
                    Color(red: 0.86, green: 0.91, blue: 0.96),
                    Color(red: 0.93, green: 0.95, blue: 0.92),
                    Color(red: 0.96, green: 0.90, blue: 0.84)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

@MainActor
private enum SpaceCustomizationGlassPreviewBackdropImageCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static let pointSize = CGSize(width: 1280, height: 900)
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    static func image(colorScheme: ColorScheme) -> NSImage? {
        if let desktopImage = desktopWallpaperImage() {
            return desktopImage
        }
        return fallbackImage(colorScheme: colorScheme)
    }

    private static func desktopWallpaperImage() -> NSImage? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return nil
        }

        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let key = NSString(string: "desktop-\(url.path)-\(modifiedAt)")

        if let image = cache.object(forKey: key) {
            return image
        }

        guard let image = NSImage(contentsOf: url) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    private static func fallbackImage(colorScheme: ColorScheme) -> NSImage? {
        let key = NSString(string: colorScheme == .dark ? "fallback-dark" : "fallback-light")
        if let image = cache.object(forKey: key) {
            return image
        }

        guard let image = makeFallbackImage(colorScheme: colorScheme) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    private static func makeFallbackImage(colorScheme: ColorScheme) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = max(1, Int((pointSize.width * scale).rounded()))
        let pixelHeight = max(1, Int((pointSize.height * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high

        let isDark = colorScheme == .dark
        drawSky(in: context, isDark: isDark)
        drawAtmosphere(in: context, isDark: isDark)
        drawLandscape(in: context, isDark: isDark)
        drawSubtleVignette(in: context, isDark: isDark)

        guard let cgImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: pointSize)
    }

    private static func drawSky(in context: CGContext, isDark: Bool) {
        drawLinearGradient(
            in: context,
            rect: CGRect(origin: .zero, size: pointSize),
            colors: isDark
                ? [
                    rgba(0.025, 0.035, 0.070, 1),
                    rgba(0.055, 0.095, 0.120, 1),
                    rgba(0.120, 0.095, 0.120, 1)
                ]
                : [
                    rgba(0.700, 0.810, 0.920, 1),
                    rgba(0.880, 0.910, 0.900, 1),
                    rgba(0.980, 0.850, 0.700, 1)
                ],
            start: CGPoint(x: 0, y: pointSize.height),
            end: CGPoint(x: pointSize.width, y: 0)
        )
    }

    private static func drawAtmosphere(in context: CGContext, isDark: Bool) {
        drawRadialGradient(
            in: context,
            center: CGPoint(x: pointSize.width * 0.78, y: pointSize.height * 0.72),
            radius: pointSize.width * 0.42,
            colors: isDark
                ? [rgba(0.35, 0.22, 0.36, 0.34), rgba(0.35, 0.22, 0.36, 0)]
                : [rgba(1.00, 0.63, 0.38, 0.44), rgba(1.00, 0.63, 0.38, 0)]
        )
        drawRadialGradient(
            in: context,
            center: CGPoint(x: pointSize.width * 0.22, y: pointSize.height * 0.78),
            radius: pointSize.width * 0.36,
            colors: isDark
                ? [rgba(0.10, 0.34, 0.42, 0.28), rgba(0.10, 0.34, 0.42, 0)]
                : [rgba(0.44, 0.72, 0.92, 0.30), rgba(0.44, 0.72, 0.92, 0)]
        )
    }

    private static func drawLandscape(in context: CGContext, isDark: Bool) {
        drawHill(
            in: context,
            baseline: pointSize.height * 0.40,
            amplitude: pointSize.height * 0.12,
            color: isDark ? rgba(0.09, 0.13, 0.16, 0.68) : rgba(0.55, 0.66, 0.62, 0.44),
            controlBias: 0.12
        )
        drawHill(
            in: context,
            baseline: pointSize.height * 0.30,
            amplitude: pointSize.height * 0.15,
            color: isDark ? rgba(0.07, 0.10, 0.13, 0.78) : rgba(0.42, 0.56, 0.55, 0.48),
            controlBias: -0.08
        )
        drawHill(
            in: context,
            baseline: pointSize.height * 0.19,
            amplitude: pointSize.height * 0.10,
            color: isDark ? rgba(0.035, 0.055, 0.070, 0.86) : rgba(0.34, 0.48, 0.46, 0.56),
            controlBias: 0.18
        )
    }

    private static func drawSubtleVignette(in context: CGContext, isDark: Bool) {
        context.setFillColor(isDark ? rgba(0, 0, 0, 0.18) : rgba(1, 1, 1, 0.10))
        context.fill(CGRect(origin: .zero, size: CGSize(width: pointSize.width, height: pointSize.height * 0.10)))
        context.setFillColor(isDark ? rgba(0, 0, 0, 0.16) : rgba(1, 1, 1, 0.06))
        context.fill(CGRect(x: 0, y: pointSize.height * 0.88, width: pointSize.width, height: pointSize.height * 0.12))
    }

    private static func drawHill(
        in context: CGContext,
        baseline: CGFloat,
        amplitude: CGFloat,
        color: CGColor,
        controlBias: CGFloat
    ) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: baseline))
        path.addCurve(
            to: CGPoint(x: pointSize.width * 0.34, y: baseline + amplitude * (0.70 + controlBias)),
            control1: CGPoint(x: pointSize.width * 0.12, y: baseline + amplitude * (0.80 - controlBias)),
            control2: CGPoint(x: pointSize.width * 0.22, y: baseline - amplitude * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: pointSize.width * 0.68, y: baseline + amplitude * (0.24 - controlBias)),
            control1: CGPoint(x: pointSize.width * 0.44, y: baseline + amplitude * 1.28),
            control2: CGPoint(x: pointSize.width * 0.56, y: baseline - amplitude * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: pointSize.width, y: baseline + amplitude * (0.58 + controlBias)),
            control1: CGPoint(x: pointSize.width * 0.78, y: baseline + amplitude * 0.82),
            control2: CGPoint(x: pointSize.width * 0.90, y: baseline - amplitude * 0.22)
        )
        path.addLine(to: CGPoint(x: pointSize.width, y: 0))
        path.closeSubpath()

        context.addPath(path)
        context.setFillColor(color)
        context.fillPath()
    }

    private static func drawLinearGradient(
        in context: CGContext,
        rect: CGRect,
        colors: [CGColor],
        start: CGPoint,
        end: CGPoint
    ) {
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) else {
            return
        }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }

    private static func drawRadialGradient(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        colors: [CGColor]
    ) {
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) else {
            return
        }
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
    }

    private static func rgba(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
