import AppKit
import Foundation
import ImageIO
import SwiftUI

struct SidebarFavoriteTabGrid: View {
    let tabs: [SidebarTabItemSnapshot]
    let selectTab: (TabID) -> Void
    let closeTab: (BrowserTab) -> Void
    let setTabPlacement: (TabID, BrowserTabPlacement) -> Void
    let moveTab: (TabID, BrowserTabReorderDirection) -> Void
    let moveTabBefore: (TabID, BrowserTabPlacement, TabID) -> Bool
    let moveTabToPlacement: (TabID, BrowserTabPlacement) -> Bool
    @Binding var tabDropState: SidebarTabDropState

    var body: some View {
        responsiveGrid
            .padding(.horizontal, SidebarFavoriteGridLayout.horizontalPadding)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onDrop(
                of: SidebarTabDragPayload.acceptedTypes,
                delegate: SidebarFavoriteTabDropDelegate(
                    tabDropState: $tabDropState,
                    moveTab: { draggedTabID in
                        moveTabToPlacement(draggedTabID, .favorite)
                    }
                )
            )
    }

    @ViewBuilder
    private var responsiveGrid: some View {
        switch SidebarFavoriteGridLayout.preferredColumnCount(for: tabs.count) {
        case 4:
            ViewThatFits(in: .horizontal) {
                grid(columnCount: 4)
                grid(columnCount: 3)
                grid(columnCount: 2)
            }
        case 3:
            ViewThatFits(in: .horizontal) {
                grid(columnCount: 3)
                grid(columnCount: 2)
            }
        case 2:
            grid(columnCount: 2)
        default:
            EmptyView()
        }
    }

    private func grid(columnCount: Int) -> some View {
        LazyVGrid(
            columns: SidebarFavoriteGridLayout.columns(count: columnCount),
            alignment: .center,
            spacing: SidebarFavoriteGridLayout.spacing
        ) {
            ForEach(tabs) { item in
                SidebarFavoriteTabTile(
                    item: item,
                    select: { selectTab(item.tab.id) },
                    close: { closeTab(item.tab) },
                    setPlacement: { placement in setTabPlacement(item.tab.id, placement) },
                    move: { direction in moveTab(item.tab.id, direction) },
                    canClose: item.canClose,
                    canMoveUp: item.canMoveUp,
                    canMoveDown: item.canMoveDown,
                    dragStarted: { tabDropState.beginDrag() }
                )
                .onDrop(
                    of: SidebarTabDragPayload.acceptedTypes,
                    delegate: SidebarFavoriteTabDropDelegate(
                        tabDropState: $tabDropState,
                        moveTab: { draggedTabID in
                            moveTabBefore(draggedTabID, .favorite, item.tab.id)
                        }
                    )
                )
            }
        }
        .frame(
            minWidth: SidebarFavoriteGridLayout.minimumWidth(forColumnCount: columnCount),
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private func clearDropTargetAfterDrop() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            tabDropState.finishDrop()
        }
    }
}

private struct SidebarFavoriteTabDropDelegate: DropDelegate {
    @Binding var tabDropState: SidebarTabDropState
    let moveTab: (TabID) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: SidebarTabDragPayload.acceptedTypes)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        finishDrop()

        SidebarTabDragPayload.loadTabID(from: info) { draggedTabID in
            guard let draggedTabID else {
                finishDrop()
                return
            }

            _ = moveTab(draggedTabID)
            finishDrop()
        }

        return true
    }

    private func finishDrop() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            tabDropState.finishDrop()
        }
    }
}

struct SidebarFavoriteGridLayout {
    static let minColumnCount = 2
    static let maxColumnCount = 4
    static let tileSize: CGFloat = 34
    static let spacing: CGFloat = 7
    static let horizontalPadding: CGFloat = 2

    static func preferredColumnCount(for itemCount: Int) -> Int {
        guard itemCount > 0 else {
            return 0
        }
        return min(max(itemCount, minColumnCount), maxColumnCount)
    }

    static func columns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: tileSize), spacing: spacing, alignment: .center),
            count: count
        )
    }

    static func minimumWidth(forColumnCount columnCount: Int) -> CGFloat {
        guard columnCount > 0 else {
            return 0
        }
        return CGFloat(columnCount) * tileSize + CGFloat(columnCount - 1) * spacing
    }

    static func columnCount(forAvailableWidth availableWidth: CGFloat, itemCount: Int) -> Int {
        let preferredColumnCount = preferredColumnCount(for: itemCount)
        guard preferredColumnCount > minColumnCount else {
            return preferredColumnCount
        }

        return stride(from: preferredColumnCount, through: minColumnCount, by: -1)
            .first { availableWidth >= minimumWidth(forColumnCount: $0) }
            ?? minColumnCount
    }

    static func rowCount(for itemCount: Int, columnCount: Int) -> Int {
        guard itemCount > 0, columnCount > 0 else {
            return 0
        }
        return Int(ceil(Double(itemCount) / Double(columnCount)))
    }
}

private struct SidebarFavoriteTabTile: View {
    let item: SidebarTabItemSnapshot
    let select: () -> Void
    let close: () -> Void
    let setPlacement: (BrowserTabPlacement) -> Void
    let move: (BrowserTabReorderDirection) -> Void
    let canClose: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let dragStarted: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sidebarForegroundColor) private var sidebarForegroundColor
    @Environment(\.sidebarUsesDarkForeground) private var sidebarUsesDarkForeground
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            SidebarTabFaviconView(tab: item.tab, size: 18)
                .frame(width: SidebarFavoriteGridLayout.tileSize, height: SidebarFavoriteGridLayout.tileSize)
                .frame(maxWidth: .infinity, minHeight: SidebarFavoriteGridLayout.tileSize)
                .background(tileBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tileBorderColor, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
        .onDrag {
            dragStarted()
            return NSItemProvider(object: item.tab.id.uuidString as NSString)
        } preview: {
            dragPreview
        }
        .contextMenu {
            Button("Open", action: select)

            Divider()

            Button("Add to List Essentials") {
                setPlacement(.pinned)
            }

            Button("Remove from Essentials") {
                setPlacement(.regular)
            }

            Divider()

            Button("Move Left") {
                move(.up)
            }
            .disabled(!canMoveUp)

            Button("Move Right") {
                move(.down)
            }
            .disabled(!canMoveDown)

            if canClose {
                Divider()

                Button("Close Tab", role: .destructive, action: close)
            }
        }
        .help(helpText)
        .accessibilityLabel("Open \(item.tab.title)")
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }

    private var dragPreview: some View {
        SidebarTabFaviconView(tab: item.tab, size: 20)
            .frame(width: 38, height: 38)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    }

    private var tileBackground: some ShapeStyle {
        if item.isSelected {
            return AnyShapeStyle(sidebarForegroundColor.opacity(selectionBackgroundOpacity))
        }
        if isHovered {
            return AnyShapeStyle(Color.primary.opacity(hoverBackgroundOpacity))
        }
        return AnyShapeStyle(.clear)
    }

    private var tileBorderColor: Color {
        if sidebarUsesDarkForeground {
            return .clear
        }
        if item.isSelected {
            return sidebarForegroundColor.opacity(colorScheme == .dark ? 0.24 : 0.18)
        }
        return Color.primary.opacity(isHovered ? 0.14 : 0.06)
    }

    private var selectionBackgroundOpacity: Double {
        colorScheme == .dark ? 0.14 : 0.07
    }

    private var hoverBackgroundOpacity: Double {
        colorScheme == .dark ? 0.08 : 0.045
    }

    private var helpText: String {
        guard let url = item.tab.url?.absoluteString else {
            return item.tab.title
        }
        return "\(item.tab.title)\n\(url)"
    }
}

struct SidebarTabFaviconSource {
    static func url(for tab: BrowserTab) -> URL? {
        tab.faviconURL ?? rootFaviconURL(for: tab.url)
    }

    private static func rootFaviconURL(for url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/favicon.ico"
        return components.url
    }
}

struct SidebarTabFaviconView: View {
    let tab: BrowserTab
    let size: CGFloat
    var fallbackSymbolName: String? = nil
    @StateObject private var loader = SidebarFaviconImageLoader()

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .task(id: faviconURL) {
            await loader.load(faviconURL)
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: resolvedFallbackSymbolName)
            .font(.system(size: size * 0.78, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }

    private var resolvedFallbackSymbolName: String {
        if let fallbackSymbolName {
            return fallbackSymbolName
        }
        switch tab.content {
        case .spaceCustomization:
            return "slider.horizontal.3"
        case .passwordManager:
            return "key"
        case .web:
            break
        }
        return "globe"
    }

    private var faviconURL: URL? {
        SidebarTabFaviconSource.url(for: tab)
    }
}

@MainActor
private final class SidebarFaviconImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    private var loadedURL: URL?

    func load(_ url: URL?) async {
        guard loadedURL != url else {
            return
        }

        loadedURL = url
        image = nil

        guard let url else {
            return
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 8

            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled,
                  (response as? HTTPURLResponse).map({ 200..<400 ~= $0.statusCode }) ?? true else {
                return
            }

            image = Self.image(from: data)
        } catch {
            image = nil
        }
    }

    private static func image(from data: Data) -> NSImage? {
        if let image = NSImage(data: data),
           image.isValid {
            return image
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let imageIndex = bestImageIndex(in: source)
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, imageIndex, nil) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: .zero)
    }

    private static func bestImageIndex(in source: CGImageSource) -> Int {
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            return 0
        }

        return (0..<count).max { lhs, rhs in
            pixelArea(at: lhs, in: source) < pixelArea(at: rhs, in: source)
        } ?? 0
    }

    private static func pixelArea(at index: Int, in source: CGImageSource) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        return width * height
    }
}
