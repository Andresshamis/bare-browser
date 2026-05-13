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
            if store.isPrivateBrowsingActive {
                privateBrowsingIndicator
            }
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

                Section("Private Browsing") {
                    Button {
                        startPrivateBrowsing()
                    } label: {
                        Label("New Private Session", systemImage: "lock.fill")
                    }
                    .accessibilityLabel("Start private browsing session")

                    ForEach(store.privateBrowsingSessions) { profile in
                        Button {
                            _ = store.switchProfile(profile.id)
                        } label: {
                            Label(
                                profile.name,
                                systemImage: profile.id == store.activeProfile?.id ? "checkmark.circle.fill" : "lock"
                            )
                        }
                        .accessibilityLabel("Switch to \(profile.name) private session")
                    }

                    if store.isPrivateBrowsingActive {
                        Button(role: .destructive) {
                            _ = store.discardPrivateBrowsingSession()
                        } label: {
                            Label("Close Private Session", systemImage: "xmark.circle")
                        }
                        .accessibilityLabel("Close current private browsing session")
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
                    profileHeaderIcon
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.activeProfile?.name ?? "Profile")
                            .font(.headline)
                            .lineLimit(1)
                        Text(profileHeaderSubtitle)
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
            .accessibilityValue(profileAccessibilityValue)

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

    private var profileHeaderIcon: some View {
        Group {
            if store.isPrivateBrowsingActive {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color(hex: store.activeProfile?.colorHex ?? "#5E5CE6")))
            } else {
                Circle()
                    .fill(Color(hex: store.activeProfile?.colorHex ?? "#4F7CAC"))
                    .frame(width: 12, height: 12)
            }
        }
    }

    private var privateBrowsingIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#5E5CE6"))
                .accessibilityHidden(true)

            Text("Private Browsing")
                .font(.caption.weight(.semibold))

            Spacer(minLength: 0)

            Button {
                _ = store.discardPrivateBrowsingSession()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close private session")
            .accessibilityLabel("Close private browsing session")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(hex: "#5E5CE6").opacity(0.12))
        .accessibilityElement(children: .combine)
    }

    private var profileHeaderSubtitle: String {
        store.isPrivateBrowsingActive ? "Private Browsing" : (store.selectedSpace?.name ?? "No Space")
    }

    private var profileAccessibilityValue: String {
        if store.isPrivateBrowsingActive {
            return "\(store.activeProfile?.name ?? "Private"), private browsing"
        }
        return store.activeProfile?.name ?? "Profile"
    }

    private var spaceSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.activeProfileSpaces) { space in
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

    private func beginCreatingProfile() {
        newProfileName = store.suggestedPersistentProfileName
        isProfileCreatorPresented = true
    }

    private func startPrivateBrowsing() {
        _ = store.createPrivateBrowsingSession()
        store.showCommandBar()
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
