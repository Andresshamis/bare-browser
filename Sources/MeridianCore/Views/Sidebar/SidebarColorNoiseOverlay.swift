import AppKit
import SwiftUI

struct SidebarColorNoiseOverlay<ClipShape: Shape>: View {
    let level: Double
    let shape: ClipShape

    var body: some View {
        let opacity = SidebarGlassRendering.colorNoiseOpacity(forLevel: level)
        let cellSize = SidebarGlassRendering.colorNoiseTextureCellSize()

        if opacity > 0,
           let texture = SidebarColorNoiseTextureCache.image(cellSize: cellSize) {
            GeometryReader { proxy in
                Image(nsImage: texture)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .opacity(opacity)
            .blendMode(.color)
            .clipShape(shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

@MainActor
private enum SidebarColorNoiseTextureCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static let tilePointSize: CGFloat = 256

    static func image(cellSize: CGFloat) -> NSImage? {
        let key = NSString(format: "%.2f", Double(cellSize))

        if let image = cache.object(forKey: key) {
            return image
        }

        guard let image = makeImage(cellSize: cellSize) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    private static func makeImage(cellSize: CGFloat) -> NSImage? {
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelSize = max(1, Int((tilePointSize * backingScale).rounded()))
        let cellPixelSize = max(1, Int((cellSize * backingScale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: pixelSize * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.setAllowsAntialiasing(false)
        context.interpolationQuality = .none

        let columns = max(1, Int(ceil(Double(pixelSize) / Double(cellPixelSize))))
        let rows = max(1, Int(ceil(Double(pixelSize) / Double(cellPixelSize))))

        for row in 0..<rows {
            for column in 0..<columns {
                let color = SidebarColorNoisePalette.rgb(column: column, row: row)
                context.setFillColor(
                    red: color.red,
                    green: color.green,
                    blue: color.blue,
                    alpha: 1
                )
                context.fill(CGRect(
                    x: column * cellPixelSize,
                    y: row * cellPixelSize,
                    width: cellPixelSize,
                    height: cellPixelSize
                ))
            }
        }

        guard let cgImage = context.makeImage() else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: tilePointSize, height: tilePointSize)
        )
    }
}

private enum SidebarColorNoisePalette {
    static func rgb(column: Int, row: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let first = unitValue(column: column, row: row, salt: 0x4D657269)
        let second = unitValue(column: column, row: row, salt: 0x6469616E)

        return rgb(
            hue: first,
            saturation: 0.78 + second * 0.20,
            brightness: 0.68
        )
    }

    private static func rgb(
        hue: Double,
        saturation: Double,
        brightness: Double
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let normalizedHue = hue - floor(hue)
        let sector = normalizedHue * 6
        let chroma = brightness * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = brightness - chroma

        let components: (red: Double, green: Double, blue: Double)
        switch sector {
        case 0..<1:
            components = (chroma, x, 0)
        case 1..<2:
            components = (x, chroma, 0)
        case 2..<3:
            components = (0, chroma, x)
        case 3..<4:
            components = (0, x, chroma)
        case 4..<5:
            components = (x, 0, chroma)
        default:
            components = (chroma, 0, x)
        }

        return (
            CGFloat(components.red + match),
            CGFloat(components.green + match),
            CGFloat(components.blue + match)
        )
    }

    private static func unitValue(column: Int, row: Int, salt: UInt64) -> Double {
        var value = UInt64(bitPattern: Int64(column))
        value &*= 0x9E37_79B9_7F4A_7C15
        value &+= UInt64(bitPattern: Int64(row)) &* 0xBF58_476D_1CE4_E5B9
        value &+= salt
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double((value >> 11) & 0x1F_FFFF) / Double(0x1F_FFFF)
    }
}
