import SwiftUI

public struct SidebarView: View {
    @ObservedObject private var store: BrowserStore
    @State private var isProfileCreatorPresented = false
    @State private var newProfileName = ""

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
        .sheet(isPresented: $isProfileCreatorPresented) {
            ProfileCreationSheet(
                profileName: $newProfileName,
                create: {
                    _ = store.createPersistentProfile(name: newProfileName)
                    isProfileCreatorPresented = false
                    newProfileName = ""
                },
                cancel: {
                    isProfileCreatorPresented = false
                    newProfileName = ""
                }
            )
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 10) {
            Menu {
                Section("Profiles") {
                    ForEach(store.persistentProfiles) { profile in
                        Button {
                            _ = store.switchProfile(profile.id)
                        } label: {
                            Label(
                                profile.name,
                                systemImage: profile.id == store.activeProfile?.id ? "checkmark.circle.fill" : "person.circle"
                            )
                        }
                        .accessibilityLabel("Switch to \(profile.name) profile")
                    }
                }

                Divider()

                Button {
                    beginCreatingProfile()
                } label: {
                    Label("New Profile...", systemImage: "person.crop.circle.badge.plus")
                }
                .accessibilityLabel("Create new persistent profile")
            } label: {
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

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .help("Switch or create profile")
            .accessibilityLabel("Profile menu")
            .accessibilityValue(store.activeProfile?.name ?? "Profile")

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
                    close: { close(tab) }
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
                    closeTab: { tab in close(tab) }
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

    private func beginCreatingProfile() {
        newProfileName = store.suggestedPersistentProfileName
        isProfileCreatorPresented = true
    }
}

private struct ProfileCreationSheet: View {
    @Binding var profileName: String
    var create: () -> Void
    var cancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Profile")
                .font(.headline)

            TextField("Profile name", text: $profileName)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(create)
                .accessibilityLabel("Profile name")

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            isFocused = true
        }
    }
}
