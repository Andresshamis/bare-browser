import SwiftUI

public struct SidebarTabRow: View {
    private let tab: BrowserTab
    private let isSelected: Bool
    private let select: () -> Void
    private let close: () -> Void
    private let setPlacement: (BrowserTabPlacement) -> Void

    public init(
        tab: BrowserTab,
        isSelected: Bool,
        select: @escaping () -> Void,
        close: @escaping () -> Void,
        setPlacement: @escaping (BrowserTabPlacement) -> Void
    ) {
        self.tab = tab
        self.isSelected = isSelected
        self.select = select
        self.close = close
        self.setPlacement = setPlacement
    }

    public var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
