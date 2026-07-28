import SwiftUI

public struct SidebarTabRow: View {
    private let tab: BrowserTab
    private let isSelected: Bool
    private let select: () -> Void
    private let close: () -> Void
    private let setPlacement: (BrowserTabPlacement) -> Void
    private let move: (BrowserTabReorderDirection) -> Void
    private let showsLoadingIndicator: Bool
    private let canClose: Bool
    private let canMoveUp: Bool
    private let canMoveDown: Bool
    private let dragStarted: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sidebarForegroundColor) private var sidebarForegroundColor
    @State private var isHovered = false
    @State private var closeIsHovered = false

    public init(
        tab: BrowserTab,
        isSelected: Bool,
        select: @escaping () -> Void,
        close: @escaping () -> Void,
        setPlacement: @escaping (BrowserTabPlacement) -> Void,
        move: @escaping (BrowserTabReorderDirection) -> Void = { _ in },
        showsLoadingIndicator: Bool = true,
        canClose: Bool = true,
        canMoveUp: Bool = false,
        canMoveDown: Bool = false,
        dragStarted: @escaping () -> Void = {}
    ) {
        self.tab = tab
        self.isSelected = isSelected
        self.select = select
        self.close = close
        self.setPlacement = setPlacement
        self.move = move
        self.showsLoadingIndicator = showsLoadingIndicator
        self.canClose = canClose
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.dragStarted = dragStarted
    }

    public var body: some View {
        HStack(spacing: 9) {
            SidebarTabFaviconView(
                tab: tab,
                size: SidebarLayoutMetrics.rowIconSize,
                fallbackSymbolName: iconName
            )
                .frame(width: SidebarLayoutMetrics.rowIconSize)
                .accessibilityHidden(true)

            Text(tab.title)
                .font(.system(size: SidebarLayoutMetrics.rowFontSize))
                .lineLimit(1)

            Spacer(minLength: 4)

            if showsLoadingIndicator && tab.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }

            if canClose {
                Button(action: close) {
                    ZStack {
                        Color.clear

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                closeIsHovered
                                    ? sidebarForegroundColor.opacity(closeHoverBackgroundOpacity)
                                    : .clear
                            )
                            .opacity(isHovered || isSelected ? 1 : 0)

                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                closeIsHovered
                                    ? sidebarForegroundColor
                                    : sidebarForegroundColor.opacity(0.72)
                                )
                            .opacity(isHovered || isSelected ? 1 : 0)
                    }
                    .frame(width: 24, height: 24)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { closeIsHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: closeIsHovered)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .help("Close tab")
                .accessibilityLabel("Close \(tab.title)")
            }
        }
        .padding(.leading, SidebarLayoutMetrics.rowLeadingInset)
        .padding(.trailing, SidebarLayoutMetrics.rowTrailingInset)
        .padding(.vertical, SidebarLayoutMetrics.rowVerticalInset)
        .background(selectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: SidebarLayoutMetrics.rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onDrag {
            dragStarted()
            return NSItemProvider(object: tab.id.uuidString as NSString)
        } preview: {
            dragPreview
        }
        .contextMenu {
            Button("Add to Essentials") {
                setPlacement(.favorite)
            }
            .disabled(tab.isFavorite && tab.parentFolderID == nil)

            Button("Add to List Essentials") {
                setPlacement(.pinned)
            }
            .disabled(tab.isPinned && tab.parentFolderID == nil)

            Button(removePlacementTitle) {
                setPlacement(.regular)
            }
            .disabled(!tab.isPinned && !tab.isFavorite && tab.parentFolderID == nil)

            Divider()

            Button("Move Tab Up") {
                move(.up)
            }
            .disabled(!canMoveUp)

            Button("Move Tab Down") {
                move(.down)
            }
            .disabled(!canMoveDown)

            if canClose {
                Divider()

                Button("Close Tab", role: .destructive, action: close)
            }
        }
        .accessibilityLabel(tab.title)
    }

    private var dragPreview: some View {
        HStack(spacing: 9) {
            SidebarTabFaviconView(
                tab: tab,
                size: SidebarLayoutMetrics.rowIconSize,
                fallbackSymbolName: iconName
            )
                .frame(width: SidebarLayoutMetrics.rowIconSize)

            Text(tab.title)
                .font(.system(size: SidebarLayoutMetrics.rowFontSize, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: 236, height: 38, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    }

    private var selectionBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                sidebarForegroundColor.opacity(selectionBackgroundOpacity)
            )
        }
        if isHovered {
            return AnyShapeStyle(
                sidebarForegroundColor.opacity(hoverBackgroundOpacity)
            )
        }
        return AnyShapeStyle(.clear)
    }

    private var selectionBackgroundOpacity: Double {
        colorScheme == .dark ? 0.12 : 0.055
    }

    private var hoverBackgroundOpacity: Double {
        colorScheme == .dark ? 0.075 : 0.045
    }

    private var closeHoverBackgroundOpacity: Double {
        colorScheme == .dark ? 0.16 : 0.10
    }

    private var iconName: String {
        switch tab.content {
        case .spaceCustomization:
            return "slider.horizontal.3"
        case .passwordManager:
            return "key"
        case .web:
            break
        }
        if tab.isFavorite {
            return "sparkle"
        }
        if tab.isPinned {
            return "pin"
        }
        return "globe"
    }

    private var removePlacementTitle: String {
        if tab.isFavorite && tab.parentFolderID == nil {
            return "Remove from Essentials"
        }

        if tab.isPinned && tab.parentFolderID == nil {
            return "Remove from List Essentials"
        }

        return "Move to Tabs"
    }
}
