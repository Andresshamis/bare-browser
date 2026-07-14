import AppKit
import SwiftUI

struct SidebarThemeColorEditorButton: View {
    let colorHex: String
    @Binding var settings: SidebarGlassSettings
    var openPersistentPicker: (() -> Void)? = nil
    let colorChanged: (String) -> Void

    @StateObject private var samplerController = SidebarThemeColorSamplerController()
    @State private var isPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            if let openPersistentPicker {
                openPersistentPicker()
            } else {
                isPresented.toggle()
            }
        } label: {
            Label("Edit", systemImage: "paintpalette")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.34), lineWidth: 0.6)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Edit theme color")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            SidebarThemeColorPickerPopover(
                colorHex: colorHex,
                settings: $settings,
                samplerController: samplerController,
                colorChanged: colorChanged,
                onClose: { isPresented = false }
            )
        }
        .onDisappear {
            samplerController.cancelSampling()
        }
    }
}

struct SidebarThemeColorPickerPopover: View {
    let colorHex: String
    @Binding var settings: SidebarGlassSettings
    @ObservedObject var samplerController: SidebarThemeColorSamplerController
    let colorChanged: (String) -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var colorComponents: SidebarThemeColorComponents

    init(
        colorHex: String,
        settings: Binding<SidebarGlassSettings>,
        samplerController: SidebarThemeColorSamplerController,
        colorChanged: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.colorHex = colorHex
        self._settings = settings
        self.samplerController = samplerController
        self.colorChanged = colorChanged
        self.onClose = onClose
        self._colorComponents = State(initialValue: SidebarThemeColorComponents(hex: colorHex))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            saturationBrightnessPicker
            huePicker
            materialControls
        }
        .padding(14)
        .frame(width: 304)
        .foregroundStyle(pickerPrimaryTextColor)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(pickerContrastBackingColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.32), lineWidth: 0.6)
        }
        .onChange(of: colorHex) { _, newValue in
            syncColorComponents(with: newValue)
        }
        .onDisappear {
            samplerController.cancelSampling()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: colorComponents.hexString))
                .frame(width: 58, height: 58)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.42), lineWidth: 0.8)
                }
                .shadow(color: Color(hex: colorComponents.hexString).opacity(0.30), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text("Theme Color")
                    .font(.subheadline.weight(.semibold))
                Text(colorComponents.hexString)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(pickerSecondaryTextColor)
            }

            Spacer(minLength: 0)

            Button {
                sampleScreenColor()
            } label: {
                Label(samplerController.isSampling ? "Sampling" : "Sample", systemImage: "eyedropper")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .help("Sample screen color")
            .disabled(samplerController.isSampling)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Close picker")
        }
    }

    private var saturationBrightnessPicker: some View {
        HStack {
            Spacer(minLength: 0)
            SidebarThemeSaturationBrightnessPlane(
                color: colorComponents,
                updateColor: commitColor
            )
            .frame(width: 218, height: 218)
            Spacer(minLength: 0)
        }
    }

    private var huePicker: some View {
        SidebarThemeHueRail(
            color: colorComponents,
            updateColor: commitColor
        )
        .frame(height: 18)
    }

    private var materialControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Material")
                .font(.caption.weight(.semibold))
                .foregroundStyle(pickerSecondaryTextColor)

            SidebarThemeMaterialSlider(
                title: "Color",
                value: settingBinding(\.tintOpacity),
                lowLabel: "Neutral",
                highLabel: "Color"
            )
            SidebarThemeMaterialSlider(
                title: "Density",
                value: settingBinding(\.glassOpacity),
                lowLabel: "Clear",
                highLabel: "Dense"
            )
            SidebarThemeMaterialSlider(
                title: "Texture",
                value: settingBinding(\.colorNoiseLevel),
                lowLabel: "Clean",
                highLabel: "Grain"
            )
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(pickerInsetBackingColor)
        }
    }

    private var pickerPrimaryTextColor: Color {
        Color(nsColor: .labelColor)
    }

    private var pickerSecondaryTextColor: Color {
        Color(nsColor: .labelColor)
            .opacity(colorScheme == .dark ? 0.78 : 0.68)
    }

    private var pickerContrastBackingColor: Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.74 : 0.56)
    }

    private var pickerInsetBackingColor: Color {
        Color(nsColor: .labelColor)
            .opacity(colorScheme == .dark ? 0.075 : 0.045)
    }

    private func settingBinding(_ keyPath: WritableKeyPath<SidebarGlassSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                settings[keyPath: keyPath] = min(max(value, 0), 1)
            }
        )
    }

    private func commitColor(_ color: SidebarThemeColorComponents) {
        colorComponents = color
        colorChanged(color.hexString)
    }

    private func sampleScreenColor() {
        samplerController.beginSampling { colorHex in
            commitColor(SidebarThemeColorComponents(hex: colorHex))
        }
    }

    private func syncColorComponents(with hex: String) {
        let normalizedHex = SidebarThemeColorComponents.normalizedHex(hex)
        guard normalizedHex != colorComponents.hexString else {
            return
        }

        colorComponents = SidebarThemeColorComponents(hex: normalizedHex)
    }
}

struct SidebarThemeColorComponents: Equatable, Sendable {
    private static let fallbackHex = "#4F7CAC"

    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = Self.clamped(hue)
        self.saturation = Self.clamped(saturation)
        self.brightness = Self.clamped(brightness)
    }

    init(hex: String) {
        let components = Self.parsedRGBComponents(from: hex) ?? Self.parsedRGBComponents(from: Self.fallbackHex)!
        let hsb = Self.hsbComponents(red: components.red, green: components.green, blue: components.blue)

        self.init(
            hue: hsb.hue,
            saturation: hsb.saturation,
            brightness: hsb.brightness
        )
    }

    var color: NSColor {
        let rgb = rgbComponents
        return NSColor(
            srgbRed: rgb.red,
            green: rgb.green,
            blue: rgb.blue,
            alpha: 1
        )
    }

    var hexString: String {
        let rgb = rgbComponents
        return Self.hexString(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func normalizedHex(_ hex: String) -> String {
        SidebarThemeColorComponents(hex: hex).hexString
    }

    static func hexString(from color: NSColor) -> String? {
        guard let rgbColor = color.usingColorSpace(.sRGB) else {
            return nil
        }

        return Self.hexString(
            red: Self.clamped(Double(rgbColor.redComponent)),
            green: Self.clamped(Double(rgbColor.greenComponent)),
            blue: Self.clamped(Double(rgbColor.blueComponent))
        )
    }

    func replacing(hue: Double? = nil, saturation: Double? = nil, brightness: Double? = nil) -> Self {
        Self(
            hue: hue ?? self.hue,
            saturation: saturation ?? self.saturation,
            brightness: brightness ?? self.brightness
        )
    }

    private var rgbComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let hue = hue >= 1 ? 0 : hue
        let scaledHue = hue * 6
        let sector = Int(scaledHue.rounded(.down))
        let fraction = scaledHue - Double(sector)
        let value = brightness
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * fraction)
        let t = value * (1 - saturation * (1 - fraction))

        let rgb: (red: Double, green: Double, blue: Double)
        switch sector % 6 {
        case 0:
            rgb = (value, t, p)
        case 1:
            rgb = (q, value, p)
        case 2:
            rgb = (p, value, t)
        case 3:
            rgb = (p, q, value)
        case 4:
            rgb = (t, p, value)
        default:
            rgb = (value, p, q)
        }

        return (CGFloat(rgb.red), CGFloat(rgb.green), CGFloat(rgb.blue))
    }

    private static func parsedRGBComponents(from hex: String) -> (red: Double, green: Double, blue: Double)? {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))

        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            return nil
        }

        return (
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    private static func hsbComponents(
        red: Double,
        green: Double,
        blue: Double
    ) -> (hue: Double, saturation: Double, brightness: Double) {
        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let delta = maxComponent - minComponent

        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maxComponent == red {
            hue = (((green - blue) / delta).truncatingRemainder(dividingBy: 6)) / 6
        } else if maxComponent == green {
            hue = ((blue - red) / delta + 2) / 6
        } else {
            hue = ((red - green) / delta + 4) / 6
        }

        return (
            hue: hue < 0 ? hue + 1 : hue,
            saturation: maxComponent == 0 ? 0 : delta / maxComponent,
            brightness: maxComponent
        )
    }

    private static func hexString(red: CGFloat, green: CGFloat, blue: CGFloat) -> String {
        hexString(red: Double(red), green: Double(green), blue: Double(blue))
    }

    private static func hexString(red: Double, green: Double, blue: Double) -> String {
        let red = Int((clamped(red) * 255).rounded())
        let green = Int((clamped(green) * 255).rounded())
        let blue = Int((clamped(blue) * 255).rounded())

        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

@MainActor
protocol SidebarThemeColorSampling: AnyObject {
    func show(selectionHandler: @escaping @MainActor (NSColor?) -> Void)
}

@MainActor
final class AppKitSidebarThemeColorSampler: SidebarThemeColorSampling {
    private let sampler = NSColorSampler()

    func show(selectionHandler: @escaping @MainActor (NSColor?) -> Void) {
        sampler.show { color in
            Task { @MainActor in
                selectionHandler(color)
            }
        }
    }
}

@MainActor
final class SidebarThemeColorSamplerController: ObservableObject {
    @Published private(set) var isSampling = false

    private let makeSampler: () -> SidebarThemeColorSampling
    private var activeSampler: SidebarThemeColorSampling?
    private var activeToken: UInt64 = 0

    init(makeSampler: @escaping () -> SidebarThemeColorSampling = { AppKitSidebarThemeColorSampler() }) {
        self.makeSampler = makeSampler
    }

    func beginSampling(colorChanged: @escaping (String) -> Void) {
        activeToken &+= 1
        let token = activeToken
        let sampler = makeSampler()
        activeSampler = sampler
        isSampling = true

        sampler.show { [weak self] color in
            guard let self,
                  self.activeToken == token else {
                return
            }

            self.activeSampler = nil
            self.isSampling = false

            guard let color,
                  let hexString = SidebarThemeColorComponents.hexString(from: color) else {
                return
            }

            colorChanged(hexString)
        }
    }

    func cancelSampling() {
        activeToken &+= 1
        activeSampler = nil
        isSampling = false
    }

}

private struct SidebarThemeSaturationBrightnessPlane: View {
    let color: SidebarThemeColorComponents
    let updateColor: (SidebarThemeColorComponents) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                Rectangle()
                    .fill(Color(nsColor: color.replacing(saturation: 1, brightness: 1).color))
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.white, .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.black.opacity(0), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    ))

                Circle()
                    .stroke(.black.opacity(0.45), lineWidth: 3)
                    .frame(width: 15, height: 15)
                    .position(selectorPosition(in: size))
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 15, height: 15)
                    .position(selectorPosition(in: size))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.separator.opacity(0.32), lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateColor(color(at: value.location, in: size))
                    }
            )
        }
    }

    private func selectorPosition(in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(CGFloat(color.saturation) * size.width, 0), size.width),
            y: min(max((1 - CGFloat(color.brightness)) * size.height, 0), size.height)
        )
    }

    private func color(at location: CGPoint, in size: CGSize) -> SidebarThemeColorComponents {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let saturation = min(max(location.x / width, 0), 1)
        let brightness = 1 - min(max(location.y / height, 0), 1)
        return color.replacing(saturation: Double(saturation), brightness: Double(brightness))
    }
}

private struct SidebarThemeHueRail: View {
    let color: SidebarThemeColorComponents
    let updateColor: (SidebarThemeColorComponents) -> Void

    private let hueStops: [Color] = [
        .red,
        .yellow,
        .green,
        .cyan,
        .blue,
        .purple,
        .red
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: hueStops, startPoint: .leading, endPoint: .trailing))

                Circle()
                    .fill(Color(nsColor: color.replacing(saturation: 1, brightness: 1).color))
                    .frame(width: 16, height: 16)
                    .overlay {
                        Circle()
                            .stroke(.white, lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
                    .position(x: selectorX(in: size), y: size.height / 2)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateColor(color(at: value.location, in: size))
                    }
            )
        }
    }

    private func selectorX(in size: CGSize) -> CGFloat {
        min(max(CGFloat(color.hue) * size.width, 0), size.width)
    }

    private func color(at location: CGPoint, in size: CGSize) -> SidebarThemeColorComponents {
        let width = max(size.width, 1)
        let hue = min(max(location.x / width, 0), 1)
        return color.replacing(hue: Double(hue))
    }
}

private struct SidebarThemeMaterialSlider: View {
    let title: String
    @Binding var value: Double
    var lowLabel: String? = nil
    var highLabel: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(titleColor)
                    .frame(width: 56, alignment: .leading)

                Slider(value: $value, in: 0...1, step: 0.01)

                Text("\(Int((value * 100).rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(valueColor)
                    .frame(width: 30, alignment: .trailing)
            }

            if lowLabel != nil || highLabel != nil {
                HStack {
                    Text(lowLabel ?? "")
                    Spacer()
                    Text(highLabel ?? "")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(rangeLabelColor)
                .padding(.leading, 66)
                .padding(.trailing, 40)
            }
        }
    }

    private var titleColor: Color {
        Color(nsColor: .labelColor)
            .opacity(colorScheme == .dark ? 0.82 : 0.70)
    }

    private var valueColor: Color {
        Color(nsColor: .labelColor)
            .opacity(colorScheme == .dark ? 0.76 : 0.64)
    }

    private var rangeLabelColor: Color {
        Color(nsColor: .labelColor)
            .opacity(colorScheme == .dark ? 0.62 : 0.50)
    }
}
