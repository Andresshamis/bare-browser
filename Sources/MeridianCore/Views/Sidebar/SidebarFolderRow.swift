import SwiftUI

public struct SidebarFolderRow: View {
    private let folder: BrowserFolder
    private let tabs: [BrowserTab]
    private let selectedTabID: TabID?
    private let selectTab: (TabID) -> Void
    private let closeTab: (BrowserTab) -> Void
    private let setTabPlacement: (TabID, BrowserTabPlacement) -> Void
    private let moveTab: (TabID, BrowserTabReorderDirection) -> Void
    private let canMoveTab: (TabID, BrowserTabReorderDirection) -> Bool

    public init(
        folder: BrowserFolder,
        tabs: [BrowserTab],
        selectedTabID: TabID?,
        selectTab: @escaping (TabID) -> Void,
        closeTab: @escaping (BrowserTab) -> Void,
        setTabPlacement: @escaping (TabID, BrowserTabPlacement) -> Void,
        moveTab: @escaping (TabID, BrowserTabReorderDirection) -> Void,
        canMoveTab: @escaping (TabID, BrowserTabReorderDirection) -> Bool
    ) {
        self.folder = folder
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.selectTab = selectTab
        self.closeTab = closeTab
        self.setTabPlacement = setTabPlacement
        self.moveTab = moveTab
        self.canMoveTab = canMoveTab
    }

    public var body: some View {
        DisclosureGroup(isExpanded: .constant(!folder.isCollapsed)) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(tabs) { tab in
                    SidebarTabRow(
                        tab: tab,
                        isSelected: tab.id == selectedTabID,
                        select: { selectTab(tab.id) },
                        close: { closeTab(tab) },
                        setPlacement: { placement in setTabPlacement(tab.id, placement) },
                        move: { direction in moveTab(tab.id, direction) },
                        canMoveUp: canMoveTab(tab.id, .up),
                        canMoveDown: canMoveTab(tab.id, .down)
                    )
                    .padding(.leading, 14)
                }
            }
            .padding(.top, 2)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
