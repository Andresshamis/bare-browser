import SwiftUI

public struct SidebarTabRow: View {
    private let tab: BrowserTab
    private let isSelected: Bool
    private let select: () -> Void
    private let close: () -> Void
    private let setPlacement: (BrowserTabPlacement) -> Void
    private let move: (BrowserTabReorderDirection) -> Void
    private let canMoveUp: Bool
    private let canMoveDown: Bool
    private let moveBefore: (TabID) -> Bool
    @State private var isHovered = false

    public init(
        tab: BrowserTab,
        isSelected: Bool,
        select: @escaping () -> Void,
        close: @escaping () -> Void,
        setPlacement: @escaping (BrowserTabPlacement) -> Void,
        move: @escaping (BrowserTabReorderDirection) -> Void = { _ in },
        canMoveUp: Bool = false,
        canMoveDown: Bool = false,
        moveBefore: @escaping (TabID) -> Bool = { _ in false }
    ) {
        self.tab = tab
        self.isSelected = isSelected
        self.select = select
        self.close = close
        self.setPlacement = setPlacement
        self.move = move
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.moveBefore = moveBefore
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
                .opacity(isHovered ? 1 : 0)
                .accessibilityHidden(true)

            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(tab.title)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer(minLength: 4)

            if tab.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected ? 1 : 0)
            .help("Close tab")
            .accessibilityLabel("Close \(tab.title)")
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(selectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .draggable(tab.id.uuidString)
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first,
                  let draggedTabID = UUID(uuidString: value) else {
                return false
            }
            return moveBefore(draggedTabID)
        }
        .contextMenu {
            Button("Add to Essentials") {
                setPlacement(.favorite)
            }
            .disabled(tab.isFavorite && tab.parentFolderID == nil)

            Button("Pin Tab") {
                setPlacement(.pinned)
            }
            .disabled(tab.isPinned && tab.parentFolderID == nil)

            Button("Move to Tabs") {
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

            Divider()

            Button("Close Tab", role: .destructive, action: close)
        }
        .accessibilityLabel(tab.title)
    }

    private var selectionBackground: some ShapeStyle {
        isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)
    }

    private var iconName: String {
        if tab.isFavorite {
            return "sparkle"
        }
        if tab.isPinned {
            return "pin"
        }
        return "globe"
    }
}
