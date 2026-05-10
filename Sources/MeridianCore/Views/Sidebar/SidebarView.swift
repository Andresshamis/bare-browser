import SwiftUI

public struct SidebarView: View {
    @ObservedObject private var store: BrowserStore

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            profileHeader
            spaceSwitcher
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    tabSection("Essentials", ids: store.selectedSpace?.favoriteTabIDs ?? [], symbolName: "sparkle")
                    tabSection("Pinned", ids: store.selectedSpace?.pinnedTabIDs ?? [], symbolName: "pin.fill")
                    folderSection
                    tabSection("Tabs", ids: store.selectedSpace?.regularTabIDs ?? [], symbolName: "rectangle.stack")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
        }
        .background(.regularMaterial)
        .accessibilityLabel("Sidebar")
    }

    private var profileHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: store.activeProfile?.colorHex ?? "#4F7CAC"))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.activeProfile?.name ?? "Profile")
                    .font(.headline)
                    .lineLimit(1)
                Text(store.selectedSpace?.name ?? "No Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                store.showCommandBar()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Command bar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var spaceSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.spaces) { space in
                    Button {
                        store.selectSpace(space.id)
                    } label: {
                        Image(systemName: space.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color(hex: space.colorHex).opacity(store.selectedSpaceID == space.id ? 0.26 : 0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(space.name)
                    .accessibilityLabel(space.name)
                }

                Button {
                    _ = store.createSpace(name: "New Space")
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .help("New space")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func tabSection(_ title: String, ids: [TabID], symbolName: String) -> some View {
        if !ids.isEmpty {
            SidebarSectionHeader(title: title, symbolName: symbolName)
            ForEach(tabs(for: ids)) { tab in
                SidebarTabRow(
                    tab: tab,
                    isSelected: tab.id == store.selectedTabID,
                    select: { store.selectTab(tab.id) },
                    close: { close(tab) },
                    setPlacement: { placement in store.setTabPlacement(placement, for: tab.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var folderSection: some View {
        let folderIDs = store.selectedSpace?.folderIDs ?? []
        if !folderIDs.isEmpty {
            SidebarSectionHeader(title: "Folders", symbolName: "folder")
            ForEach(folders(for: folderIDs)) { folder in
                SidebarFolderRow(
                    folder: folder,
                    tabs: tabs(for: folder.tabIDs),
                    selectedTabID: store.selectedTabID,
                    selectTab: { store.selectTab($0) },
                    closeTab: { tab in close(tab) },
                    setTabPlacement: { tabID, placement in store.setTabPlacement(placement, for: tabID) }
                )
            }
        }
    }

    private func tabs(for ids: [TabID]) -> [BrowserTab] {
        ids.compactMap { id in
            store.tabs.first { $0.id == id }
        }
    }

    private func folders(for ids: [FolderID]) -> [BrowserFolder] {
        ids.compactMap { id in
            store.folders.first { $0.id == id }
        }
    }

    private func close(_ tab: BrowserTab) {
        if store.selectedTabID != tab.id {
            store.selectTab(tab.id)
        }
        store.closeSelectedTab()
    }
}
