import AppKit
import SwiftUI

public struct SidebarView: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var webViewState: WebViewState
    @State private var isProfileCreatorPresented = false
    @State private var newProfileName = ""
    @State private var window: NSWindow?

    public init(store: BrowserStore, webViewState: WebViewState) {
        self.store = store
        self.webViewState = webViewState
    }

    public var body: some View {
        VStack(spacing: 0) {
            browserControlsHeader
            compactAddressButton
            profileHeader
            spaceSwitcher
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    tabSection("Essentials", ids: store.selectedSpace?.favoriteTabIDs ?? [], symbolName: "sparkle", placement: .favorite)
                    tabSection("Pinned", ids: store.selectedSpace?.pinnedTabIDs ?? [], symbolName: "pin.fill", placement: .pinned)
                    folderSection
                    tabSection("Tabs", ids: store.selectedSpace?.regularTabIDs ?? [], symbolName: "rectangle.stack", placement: .regular)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
        }
        .accessibilityLabel("Sidebar")
        .background(
            WindowReader { window in
                self.window = window
            }
            .accessibilityHidden(true)
        )
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

    private var browserControlsHeader: some View {
        HStack(spacing: 8) {
            WindowTrafficLightGroup(window: window)

            Button {
                store.toggleSidebarLock()
            } label: {
                Image(systemName: store.sidebarIsLockedOpen ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(store.sidebarIsLockedOpen ? "Use auto-hide sidebar" : "Pin sidebar open")
            .accessibilityLabel(store.sidebarIsLockedOpen ? "Use auto-hide sidebar" : "Pin sidebar open")

            Spacer(minLength: 0)

            SidebarNavigationButton(
                systemName: "chevron.left",
                help: "Back",
                isDisabled: !webViewState.canGoBack
            ) {
                webViewState.dispatch(.goBack)
            }

            SidebarNavigationButton(
                systemName: "chevron.right",
                help: "Forward",
                isDisabled: !webViewState.canGoForward
            ) {
                webViewState.dispatch(.goForward)
            }

            SidebarNavigationButton(
                systemName: webViewState.isLoading ? "xmark" : "arrow.clockwise",
                help: webViewState.isLoading ? "Stop" : "Reload",
                isDisabled: store.activeTab?.url == nil
            ) {
                webViewState.dispatch(webViewState.isLoading ? .stopLoading : .reload)
            }

            SidebarNavigationButton(
                systemName: "plus",
                help: "New Tab",
                isDisabled: false
            ) {
                store.beginNewTab()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 7)
        .background(WindowTitlebarInteractionZone().accessibilityHidden(true))
    }

    private var compactAddressButton: some View {
        HStack(spacing: 6) {
            Button {
                store.showCommandBar()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: siteSymbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text(addressText)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    Image(systemName: "command")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("T")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.separator.opacity(0.35), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .help("Open command bar")
            .accessibilityLabel("Search or enter address")
            .accessibilityValue(addressText)

            sitePermissionsMenu
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
                    .contextMenu {
                        Button {
                            store.selectSpace(space.id)
                        } label: {
                            Label("Switch to Space", systemImage: "arrow.right.circle")
                        }
                        .disabled(store.selectedSpaceID == space.id)

                        Divider()

                        Button(role: .destructive) {
                            _ = store.deleteSpace(space.id)
                        } label: {
                            Label("Delete Space", systemImage: "trash")
                        }
                        .disabled(!store.canDeleteSpace(space.id))
                    }
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
    private func tabSection(_ title: String, ids: [TabID], symbolName: String, placement: BrowserTabPlacement) -> some View {
        if !ids.isEmpty {
            SidebarSectionHeader(title: title, symbolName: symbolName)
            ForEach(tabs(for: ids)) { tab in
                SidebarTabRow(
                    tab: tab,
                    isSelected: tab.id == store.selectedTabID,
                    select: { store.selectTab(tab.id) },
                    close: { close(tab) },
                    setPlacement: { placement in store.setTabPlacement(placement, for: tab.id) },
                    move: { direction in store.moveTab(tab.id, direction) },
                    canMoveUp: store.canMoveTab(tab.id, .up),
                    canMoveDown: store.canMoveTab(tab.id, .down),
                    moveBefore: { draggedTabID in
                        store.moveTab(draggedTabID, to: placement, before: tab.id)
                    }
                )
            }

            Color.clear
                .frame(height: 8)
                .dropDestination(for: String.self) { values, _ in
                    guard let value = values.first,
                          let draggedTabID = UUID(uuidString: value) else {
                        return false
                    }
                    return store.moveTab(draggedTabID, to: placement)
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
                    setTabPlacement: { tabID, placement in store.setTabPlacement(placement, for: tabID) },
                    moveTab: { tabID, direction in store.moveTab(tabID, direction) },
                    canMoveTab: { tabID, direction in store.canMoveTab(tabID, direction) }
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
        store.closeTab(tab.id)
    }

    private func beginCreatingProfile() {
        newProfileName = store.suggestedPersistentProfileName
        isProfileCreatorPresented = true
    }

    private var addressText: String {
        if let url = store.activeTab?.url {
            return url.absoluteString
        }
        return "Search or enter address"
    }

    private var siteSymbolName: String {
        guard let url = store.activeTab?.url else {
            return "magnifyingglass"
        }
        return store.urlSecurityPolicy.isInsecureTransport(url) ? "exclamationmark.triangle" : "lock"
    }

    private var sitePermissionsMenu: some View {
        Menu {
            if let context = activeSitePermissionContext {
                Section("Site") {
                    Label(context.origin.displayString, systemImage: "globe")
                }

                Section("Permissions") {
                    ForEach(Self.manageableSitePermissionKinds, id: \.self) { kind in
                        Menu {
                            sitePermissionDecisionButton(.ask, kind: kind, context: context)
                            sitePermissionDecisionButton(.allow, kind: kind, context: context)
                            sitePermissionDecisionButton(.deny, kind: kind, context: context)
                        } label: {
                            Label(
                                "\(permissionTitle(for: kind)): \(permissionDecisionTitle(for: decision(for: kind, context: context)))",
                                systemImage: permissionSymbolName(for: kind)
                            )
                        }
                    }
                }

                Section("Limited by WebKit") {
                    disabledPermissionItem("Location: Unsupported", symbolName: "location.slash")
                    disabledPermissionItem("Notifications: Unsupported", symbolName: "bell.slash")
                    disabledPermissionItem("Autoplay: User gesture required", symbolName: "play.slash")
                }
            } else {
                disabledPermissionItem("No active site", symbolName: "globe.badge.chevron.backward")
            }
        } label: {
            Image(systemName: sitePermissionMenuSymbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.separator.opacity(0.35), lineWidth: 0.5)
                }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("Site permissions")
        .accessibilityLabel("Site permissions")
    }

    private func sitePermissionDecisionButton(
        _ decision: SitePermissionDecision,
        kind: SitePermissionKind,
        context: ActiveSitePermissionContext
    ) -> some View {
        Button {
            _ = store.setSitePermissionDecision(
                decision,
                for: kind,
                origin: context.origin,
                profileID: context.profileID
            )
        } label: {
            Label(
                permissionDecisionTitle(for: decision),
                systemImage: self.decision(for: kind, context: context) == decision ? "checkmark.circle.fill" : "circle"
            )
        }
        .accessibilityLabel("\(permissionTitle(for: kind)) \(permissionDecisionTitle(for: decision))")
    }

    private func disabledPermissionItem(_ title: String, symbolName: String) -> some View {
        Button {} label: {
            Label(title, systemImage: symbolName)
        }
        .disabled(true)
    }

    private var sitePermissionMenuSymbolName: String {
        guard let context = activeSitePermissionContext else {
            return "shield"
        }

        let hasStoredDecision = Self.manageableSitePermissionKinds.contains { kind in
            decision(for: kind, context: context) != store.sitePermissionPolicy.defaultDecision(for: kind)
        }
        return hasStoredDecision ? "shield.lefthalf.filled" : "shield"
    }

    private var activeSitePermissionContext: ActiveSitePermissionContext? {
        guard let tab = store.activeTab,
              let url = tab.url,
              let origin = SitePermissionOrigin(url: url) else {
            return nil
        }
        return ActiveSitePermissionContext(origin: origin, profileID: tab.profileID)
    }

    private func decision(
        for kind: SitePermissionKind,
        context: ActiveSitePermissionContext
    ) -> SitePermissionDecision {
        store.sitePermissionDecision(for: kind, origin: context.origin, profileID: context.profileID)
            ?? store.sitePermissionPolicy.defaultDecision(for: kind)
    }

    private func permissionDecisionTitle(for decision: SitePermissionDecision) -> String {
        switch decision {
        case .ask:
            "Ask Every Time"
        case .allow:
            "Allow"
        case .deny:
            "Block"
        }
    }

    private func permissionTitle(for kind: SitePermissionKind) -> String {
        switch kind {
        case .camera:
            "Camera"
        case .microphone:
            "Microphone"
        case .cameraAndMicrophone:
            "Camera & Microphone"
        case .popupWindow:
            "Pop-ups"
        case .geolocation:
            "Location"
        case .notifications:
            "Notifications"
        case .autoplay:
            "Autoplay"
        }
    }

    private func permissionSymbolName(for kind: SitePermissionKind) -> String {
        switch kind {
        case .camera:
            "camera"
        case .microphone:
            "mic"
        case .cameraAndMicrophone:
            "video.badge.waveform"
        case .popupWindow:
            "macwindow.badge.plus"
        case .geolocation:
            "location"
        case .notifications:
            "bell"
        case .autoplay:
            "play"
        }
    }

    private static let manageableSitePermissionKinds: [SitePermissionKind] = [
        .camera,
        .microphone,
        .cameraAndMicrophone,
        .popupWindow
    ]
}

private struct ActiveSitePermissionContext {
    var origin: SitePermissionOrigin
    var profileID: ProfileID
}

private struct WindowTrafficLightGroup: View {
    let window: NSWindow?

    var body: some View {
        HStack(spacing: 7) {
            WindowTrafficLightButton(
                color: Color(red: 1.00, green: 0.37, blue: 0.33),
                systemName: "xmark",
                help: "Close"
            ) {
                window?.performClose(nil)
            }

            WindowTrafficLightButton(
                color: Color(red: 1.00, green: 0.74, blue: 0.24),
                systemName: "minus",
                help: "Minimize"
            ) {
                window?.miniaturize(nil)
            }

            WindowTrafficLightButton(
                color: Color(red: 0.20, green: 0.80, blue: 0.32),
                systemName: "plus",
                help: "Full Screen"
            ) {
                window?.toggleFullScreen(nil)
            }
        }
    }
}

private struct WindowTrafficLightButton: View {
    let color: Color
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay {
                    if isHovered {
                        Image(systemName: systemName)
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovered = $0 }
    }
}

private struct SidebarNavigationButton: View {
    let systemName: String
    let help: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct WindowReader: NSViewRepresentable {
    let update: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            update(nsView.window)
        }
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
