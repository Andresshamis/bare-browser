import AppKit
import OSLog
import SwiftUI

private let sidebarPerformanceLog = OSLog(
    subsystem: "app.meridianbrowser.MeridianBrowser",
    category: "SidebarPerformance"
)

private let sidebarLockControlAnimation = Animation.smooth(duration: 0.24, extraBounce: 0)

public struct SidebarView: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var webViewState: WebViewState
    @State private var isProfileCreatorPresented = false
    @State private var newProfileName = ""
    @State private var window: NSWindow?
    @State private var spaceCustomizationDraft: SpaceCustomizationDraft?

    public init(store: BrowserStore, webViewState: WebViewState) {
        self.store = store
        self.webViewState = webViewState
    }

    public var body: some View {
        VStack(spacing: 0) {
            browserControlsHeader
            compactAddressButton
            profileHeader
            Divider()
            spacePager
                .frame(maxHeight: .infinity)
            Divider()
            spaceSwitcher
        }
        .accessibilityLabel("Sidebar")
        .background {
            WindowReader { window in
                self.window = window
            }
            .accessibilityHidden(true)
        }
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
        .sheet(item: $spaceCustomizationDraft) { draft in
            SpaceCustomizationSheet(
                draft: draft,
                save: { name, symbolName, colorHex in
                    if store.customizeSpace(draft.id, name: name, symbolName: symbolName, colorHex: colorHex) {
                        spaceCustomizationDraft = nil
                    }
                },
                cancel: {
                    spaceCustomizationDraft = nil
                }
            )
        }
    }

    private var browserControlsHeader: some View {
        HStack(spacing: 8) {
            WindowTrafficLightGroup(window: window)

            SidebarPinButton(isLockedOpen: store.sidebarIsLockedOpen) {
                withAnimation(sidebarLockControlAnimation) {
                    store.toggleSidebarLock()
                }
            }

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
                        selectSpace(space.id)
                    } label: {
                        SpaceSwitcherButtonLabel(
                            space: space,
                            isSelected: store.selectedSpaceID == space.id
                        )
                    }
                    .buttonStyle(.plain)
                    .help(space.name)
                    .accessibilityLabel(space.name)
                    .contextMenu {
                        Button {
                            beginCustomizing(space)
                        } label: {
                            Label("Customize Space...", systemImage: "slider.horizontal.3")
                        }

                        Divider()

                        Button {
                            selectSpace(space.id)
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New space")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .animation(SidebarSpacePagerMetrics.selectionAnimation, value: store.selectedSpaceID)
    }

    @ViewBuilder
    private var spacePager: some View {
        SidebarSpacePagerView(
            snapshot: makeSpacePagerSnapshot(),
            selectTab: { store.selectTab($0) },
            closeTab: { store.closeTab($0.id) },
            setTabPlacement: { tabID, placement in store.setTabPlacement(placement, for: tabID) },
            moveTab: { tabID, direction in store.moveTab(tabID, direction) },
            moveTabBefore: { draggedTabID, placement, tabID in
                store.moveTab(draggedTabID, to: placement, before: tabID)
            },
            moveTabToPlacement: { draggedTabID, placement in
                store.moveTab(draggedTabID, to: placement)
            },
            selectAdjacentSpace: { store.selectAdjacentSpace($0) }
        )
    }

    private func selectSpace(_ id: SpaceID) {
        guard store.selectedSpaceID != id else {
            return
        }

        withAnimation(SidebarSpacePagerMetrics.selectionAnimation) {
            store.selectSpace(id)
        }
    }

    private func makeSpacePagerSnapshot() -> SidebarSpacePagerSnapshot {
        let activeSpaces = store.activeProfileSpaces
        let selectedIndex = selectedSpaceIndex(in: activeSpaces)
        let visibleIndices = SidebarSpacePagerWindow.visibleIndices(
            selectedIndex: selectedIndex,
            count: activeSpaces.count
        )
        let visibleSpaces = visibleIndices.map { activeSpaces[$0] }
        let visibleFolderIDs = Set(visibleSpaces.flatMap(\.folderIDs))
        let foldersByID = Dictionary(
            uniqueKeysWithValues: store.folders
                .lazy
                .filter { visibleFolderIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )
        let directTabIDs = visibleSpaces.flatMap { space in
            space.favoriteTabIDs + space.pinnedTabIDs + space.regularTabIDs
        }
        let folderTabIDs = foldersByID.values.flatMap(\.tabIDs)
        let visibleTabIDs = Set(directTabIDs + folderTabIDs)
        let tabsByID = Dictionary(
            uniqueKeysWithValues: store.tabs
                .lazy
                .filter { visibleTabIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )
        let pages = visibleIndices.map { index in
            let space = activeSpaces[index]
            return SidebarSpacePageSnapshot(
                index: index,
                space: space,
                favoriteTabs: tabItems(for: space.favoriteTabIDs, tabsByID: tabsByID),
                pinnedTabs: tabItems(for: space.pinnedTabIDs, tabsByID: tabsByID),
                folders: folderItems(for: space.folderIDs, foldersByID: foldersByID, tabsByID: tabsByID),
                regularTabs: tabItems(for: space.regularTabIDs, tabsByID: tabsByID)
            )
        }

        return SidebarSpacePagerSnapshot(
            selectedIndex: selectedIndex,
            spaceCount: activeSpaces.count,
            pages: pages
        )
    }

    private func selectedSpaceIndex(in activeSpaces: [BrowserSpace]) -> Int? {
        guard let selectedSpaceID = store.selectedSpaceID else {
            return nil
        }
        return activeSpaces.firstIndex { $0.id == selectedSpaceID }
    }

    private func tabItems(
        for ids: [TabID],
        tabsByID: [TabID: BrowserTab]
    ) -> [SidebarTabItemSnapshot] {
        let orderedTabs = ids.compactMap { tabsByID[$0] }
        return orderedTabs.enumerated().map { index, tab in
            return SidebarTabItemSnapshot(
                tab: tab,
                isSelected: tab.id == store.selectedTabID,
                canMoveUp: index > 0,
                canMoveDown: index < orderedTabs.count - 1
            )
        }
    }

    private func folderItems(
        for ids: [FolderID],
        foldersByID: [FolderID: BrowserFolder],
        tabsByID: [TabID: BrowserTab]
    ) -> [SidebarFolderItemSnapshot] {
        ids.compactMap { id in
            guard let folder = foldersByID[id] else {
                return nil
            }
            return SidebarFolderItemSnapshot(
                folder: folder,
                tabs: tabItems(for: folder.tabIDs, tabsByID: tabsByID)
            )
        }
    }

    private func close(_ tab: BrowserTab) {
        store.closeTab(tab.id)
    }

    private func beginCreatingProfile() {
        newProfileName = store.suggestedPersistentProfileName
        isProfileCreatorPresented = true
    }

    private func beginCustomizing(_ space: BrowserSpace) {
        spaceCustomizationDraft = SpaceCustomizationDraft(
            id: space.id,
            name: space.name,
            symbolName: space.symbolName,
            colorHex: space.colorHex
        )
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

private struct SpaceCustomizationDraft: Identifiable {
    var id: SpaceID
    var name: String
    var symbolName: String
    var colorHex: String
}

private struct SpaceSwitcherButtonLabel: View {
    let space: BrowserSpace
    let isSelected: Bool

    var body: some View {
        let color = Color(hex: space.colorHex)

        ZStack {
            if isSelected {
                SpaceIconGlyph(
                    symbolName: space.symbolName,
                    colorHex: space.colorHex,
                    size: 32,
                    foregroundColor: color
                )
                .scaleEffect(1.45)
                .blur(radius: 6)
                .opacity(0.72)
            }

            SpaceIconGlyph(
                symbolName: space.symbolName,
                colorHex: space.colorHex,
                size: 32,
                foregroundColor: isSelected ? .white : color
            )
            .opacity(isSelected ? 1 : 0.74)
            .scaleEffect(isSelected ? 1.08 : 1)
            .frame(width: 24, height: 24)
        }
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }
}

private struct SpaceIconGlyph: View {
    let symbolName: String
    let colorHex: String
    let size: CGFloat
    var foregroundColor: Color? = nil
    var usesMutedIcon = false

    var body: some View {
        let color = foregroundColor ?? (usesMutedIcon ? Color.secondary : Color(hex: colorHex))

        if symbolName == BrowserSpace.defaultSymbolName {
            Circle()
                .fill(color)
                .frame(width: size * 0.34, height: size * 0.34)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

private struct SpaceCustomizationSheet: View {
    let draft: SpaceCustomizationDraft
    let save: (String, String, String) -> Void
    let cancel: () -> Void

    @State private var name: String
    @State private var selectedSymbolName: String
    @State private var selectedColorHex: String

    init(
        draft: SpaceCustomizationDraft,
        save: @escaping (String, String, String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.save = save
        self.cancel = cancel
        _name = State(initialValue: draft.name)
        _selectedSymbolName = State(initialValue: draft.symbolName)
        _selectedColorHex = State(initialValue: draft.colorHex)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    customizationPreview

                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.subheadline.weight(.semibold))
                        LazyVGrid(columns: iconColumns, alignment: .leading, spacing: 8) {
                            ForEach(Self.symbolOptions.indices, id: \.self) { index in
                                let symbolName = Self.symbolOptions[index]
                                SpaceIconOptionButton(
                                    symbolName: symbolName,
                                    colorHex: selectedColorHex,
                                    isSelected: symbolName == selectedSymbolName
                                ) {
                                    selectedSymbolName = symbolName
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.subheadline.weight(.semibold))
                        LazyVGrid(columns: colorColumns, alignment: .leading, spacing: 8) {
                            ForEach(Self.colorOptions.indices, id: \.self) { index in
                                let colorHex = Self.colorOptions[index]
                                SpaceColorSwatchButton(
                                    colorHex: colorHex,
                                    isSelected: colorHex == selectedColorHex
                                ) {
                                    selectedColorHex = colorHex
                                }
                            }
                        }
                    }
                }
                .padding(22)
            }
            .scrollIndicators(.visible)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(name, selectedSymbolName, selectedColorHex)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 428, height: 540)
    }

    private var customizationPreview: some View {
        let color = Color(hex: selectedColorHex)
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Space" : name

        return HStack(spacing: 14) {
            ZStack {
                SpaceIconGlyph(
                    symbolName: selectedSymbolName,
                    colorHex: selectedColorHex,
                    size: 44,
                    foregroundColor: color
                )
                .scaleEffect(1.45)
                .blur(radius: 8)
                .opacity(0.72)

                SpaceIconGlyph(
                    symbolName: selectedSymbolName,
                    colorHex: selectedColorHex,
                    size: 44,
                    foregroundColor: .white
                )
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text("Selected space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.58), color.opacity(0.08), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 190)
                        .allowsHitTesting(false)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.34), lineWidth: 0.5)
        }
    }

    private var iconColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(40), spacing: 8), count: 8)
    }

    private var colorColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(28), spacing: 8), count: 8)
    }

    private static let symbolOptions = [
        BrowserSpace.defaultSymbolName,
        "sparkles",
        "bolt.fill",
        "flame.fill",
        "moon.stars.fill",
        "sun.max.fill",
        "leaf.fill",
        "drop.fill",
        "waveform",
        "globe.americas.fill",
        "paperplane.fill",
        "map.fill",
        "location.fill",
        "book.closed.fill",
        "graduationcap.fill",
        "terminal.fill",
        "curlybraces",
        "paintbrush.pointed.fill",
        "paintpalette.fill",
        "camera.fill",
        "music.note",
        "headphones",
        "gamecontroller.fill",
        "cart.fill",
        "creditcard.fill",
        "heart.fill",
        "star.fill",
        "flag.fill",
        "shield.fill",
        "lock.fill",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "folder.fill"
    ]

    private static let colorOptions = [
        "#0A84FF",
        "#64D2FF",
        "#30D158",
        "#FFD60A",
        "#FFB340",
        "#FF9F0A",
        "#FF453A",
        "#FF375F",
        "#BF5AF2",
        "#5E5CE6",
        "#7D7AFF",
        "#AC8E68",
        "#8E8E93"
    ]
}

private struct SpaceIconOptionButton: View {
    let symbolName: String
    let colorHex: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let color = Color(hex: colorHex)

        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? color.opacity(0.92) : isHovered ? color.opacity(0.12) : .clear)

                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.36), lineWidth: 0.8)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(color.opacity(0.34), lineWidth: 0.7)
                }

                SpaceIconGlyph(
                    symbolName: symbolName,
                    colorHex: colorHex,
                    size: 34,
                    foregroundColor: isSelected ? .white : color
                )
                .opacity(isSelected ? 1 : 0.86)
            }
            .frame(width: 40, height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct SpaceColorSwatchButton: View {
    let colorHex: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let color = Color(hex: colorHex)

        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(isSelected ? 0.95 : 0), lineWidth: 2)
                        .padding(3)
                }
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? color.opacity(0.86) : Color(nsColor: .separatorColor).opacity(isHovered ? 0.7 : 0.28),
                            lineWidth: isSelected ? 2 : 0.8
                        )
                }
                .shadow(color: isSelected ? color.opacity(0.42) : .clear, radius: 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
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

private struct SidebarPinButton: View {
    let isLockedOpen: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var label: String {
        isLockedOpen ? "Use auto-hide sidebar" : "Pin sidebar open"
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "pin")
                    .opacity(isLockedOpen ? 0 : 1)
                Image(systemName: "pin.fill")
                    .opacity(isLockedOpen ? 1 : 0)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 24)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
        .animation(sidebarLockControlAnimation, value: isLockedOpen)
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

struct SidebarSpacePagerSnapshot: Equatable {
    let selectedIndex: Int?
    let spaceCount: Int
    let pages: [SidebarSpacePageSnapshot]
}

struct SidebarSpacePageSnapshot: Identifiable, Equatable {
    var id: SpaceID { space.id }

    let index: Int
    let space: BrowserSpace
    let favoriteTabs: [SidebarTabItemSnapshot]
    let pinnedTabs: [SidebarTabItemSnapshot]
    let folders: [SidebarFolderItemSnapshot]
    let regularTabs: [SidebarTabItemSnapshot]
}

struct SidebarFolderItemSnapshot: Identifiable, Equatable {
    var id: FolderID { folder.id }

    let folder: BrowserFolder
    let tabs: [SidebarTabItemSnapshot]
}

struct SidebarTabItemSnapshot: Identifiable, Equatable {
    var id: TabID { tab.id }

    let tab: BrowserTab
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
}

private struct SidebarSpacePagerView: View {
    let snapshot: SidebarSpacePagerSnapshot
    let selectTab: (TabID) -> Void
    let closeTab: (BrowserTab) -> Void
    let setTabPlacement: (TabID, BrowserTabPlacement) -> Void
    let moveTab: (TabID, BrowserTabReorderDirection) -> Void
    let moveTabBefore: (TabID, BrowserTabPlacement, TabID) -> Bool
    let moveTabToPlacement: (TabID, BrowserTabPlacement) -> Bool
    let selectAdjacentSpace: (SpaceNavigationDirection) -> Bool

    @State private var spaceSwipeDeltaX: CGFloat = 0
    @State private var isSpaceSwipeTracking = false

    var body: some View {
        GeometryReader { proxy in
            let pageWidth = max(proxy.size.width, 1)

            ZStack(alignment: .topLeading) {
                ForEach(snapshot.pages) { page in
                    SidebarSpacePageView(
                        page: page,
                        selectTab: selectTab,
                        closeTab: closeTab,
                        setTabPlacement: setTabPlacement,
                        moveTab: moveTab,
                        moveTabBefore: moveTabBefore,
                        moveTabToPlacement: moveTabToPlacement
                    )
                    .equatable()
                    .id(page.id)
                    .frame(width: pageWidth, height: proxy.size.height, alignment: .top)
                    .offset(x: pageOffset(pageIndex: page.index, pageWidth: pageWidth))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .animation(
                isSpaceSwipeTracking ? nil : SidebarSpacePagerMetrics.selectionAnimation,
                value: snapshot.selectedIndex
            )
            .background {
                SidebarSpaceSwipeMonitor(
                    updateSwipeProgress: updateSpaceSwipeProgress,
                    finishSwipe: finishSpaceSwipe,
                    cancelSwipe: cancelSpaceSwipe
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            }
        }
    }

    private func pageOffset(pageIndex: Int, pageWidth: CGFloat) -> CGFloat {
        guard let selectedIndex = snapshot.selectedIndex else {
            return 0
        }

        let interactiveOffset = SidebarSpacePagerWindow.visualOffset(
            for: spaceSwipeDeltaX,
            pageWidth: pageWidth,
            canMovePrevious: selectedIndex > 0,
            canMoveNext: selectedIndex < snapshot.spaceCount - 1
        )

        return CGFloat(pageIndex - selectedIndex) * pageWidth + interactiveOffset
    }

    private func updateSpaceSwipeProgress(_ deltaX: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isSpaceSwipeTracking = true
            spaceSwipeDeltaX = deltaX
        }
    }

    @discardableResult
    private func finishSpaceSwipe(_ direction: SpaceNavigationDirection) -> Bool {
        var didSelect = false
        withAnimation(SidebarSpacePagerMetrics.selectionAnimation) {
            didSelect = selectAdjacentSpace(direction)
            spaceSwipeDeltaX = 0
            isSpaceSwipeTracking = false
        }
        return didSelect
    }

    private func cancelSpaceSwipe() {
        withAnimation(SidebarSpacePagerMetrics.selectionAnimation) {
            spaceSwipeDeltaX = 0
            isSpaceSwipeTracking = false
        }
    }
}

private struct SidebarSpacePageView: View, Equatable {
    let page: SidebarSpacePageSnapshot
    let selectTab: (TabID) -> Void
    let closeTab: (BrowserTab) -> Void
    let setTabPlacement: (TabID, BrowserTabPlacement) -> Void
    let moveTab: (TabID, BrowserTabReorderDirection) -> Void
    let moveTabBefore: (TabID, BrowserTabPlacement, TabID) -> Bool
    let moveTabToPlacement: (TabID, BrowserTabPlacement) -> Bool

    nonisolated static func == (lhs: SidebarSpacePageView, rhs: SidebarSpacePageView) -> Bool {
        lhs.page == rhs.page
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                tabSection(
                    "Essentials",
                    tabs: page.favoriteTabs,
                    symbolName: "sparkle",
                    placement: .favorite
                )
                tabSection(
                    "Pinned",
                    tabs: page.pinnedTabs,
                    symbolName: "pin.fill",
                    placement: .pinned
                )
                folderSection
                tabSection(
                    "Tabs",
                    tabs: page.regularTabs,
                    symbolName: "rectangle.stack",
                    placement: .regular
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func tabSection(
        _ title: String,
        tabs: [SidebarTabItemSnapshot],
        symbolName: String,
        placement: BrowserTabPlacement
    ) -> some View {
        if !tabs.isEmpty {
            SidebarSectionHeader(title: title, symbolName: symbolName)
            ForEach(tabs) { item in
                tabRow(item, placement: placement, allowsDropBefore: true)
            }

            Color.clear
                .frame(height: 8)
                .dropDestination(for: String.self) { values, _ in
                    guard let value = values.first,
                          let draggedTabID = UUID(uuidString: value) else {
                        return false
                    }
                    return moveTabToPlacement(draggedTabID, placement)
                }
        }
    }

    @ViewBuilder
    private var folderSection: some View {
        if !page.folders.isEmpty {
            SidebarSectionHeader(title: "Folders", symbolName: "folder")
            ForEach(page.folders) { folderItem in
                DisclosureGroup(isExpanded: .constant(!folderItem.folder.isCollapsed)) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(folderItem.tabs) { item in
                            tabRow(item, placement: .regular, allowsDropBefore: false)
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
                        Text(folderItem.folder.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func tabRow(
        _ item: SidebarTabItemSnapshot,
        placement: BrowserTabPlacement,
        allowsDropBefore: Bool
    ) -> some View {
        SidebarTabRow(
            tab: item.tab,
            isSelected: item.isSelected,
            select: { selectTab(item.tab.id) },
            close: { closeTab(item.tab) },
            setPlacement: { placement in setTabPlacement(item.tab.id, placement) },
            move: { direction in moveTab(item.tab.id, direction) },
            canMoveUp: item.canMoveUp,
            canMoveDown: item.canMoveDown,
            moveBefore: { draggedTabID in
                guard allowsDropBefore else {
                    return false
                }
                return moveTabBefore(draggedTabID, placement, item.tab.id)
            }
        )
    }
}

enum SidebarSpacePagerMetrics {
    static let commitDelta: CGFloat = 58
    static let edgeResistanceRatio: CGFloat = 0.22
    static let selectionAnimation: Animation = .interpolatingSpring(
        mass: 0.85,
        stiffness: 340,
        damping: 34,
        initialVelocity: 0.2
    )
}

struct SidebarSpacePagerWindow {
    static func visibleIndices(selectedIndex: Int?, count: Int) -> [Int] {
        guard let selectedIndex,
              count > 0,
              (0..<count).contains(selectedIndex) else {
            return []
        }

        let lowerBound = max(0, selectedIndex - 1)
        let upperBound = min(count - 1, selectedIndex + 1)
        return Array(lowerBound...upperBound)
    }

    static func visualOffset(
        for deltaX: CGFloat,
        pageWidth: CGFloat,
        canMovePrevious: Bool,
        canMoveNext: Bool
    ) -> CGFloat {
        guard pageWidth > 0 else {
            return 0
        }

        let maxTravel = max(pageWidth * 0.44, SidebarSpacePagerMetrics.commitDelta)
        let rawOffset = (-deltaX).clamped(to: -maxTravel...maxTravel)

        if rawOffset < 0, !canMoveNext {
            return rawOffset * SidebarSpacePagerMetrics.edgeResistanceRatio
        }
        if rawOffset > 0, !canMovePrevious {
            return rawOffset * SidebarSpacePagerMetrics.edgeResistanceRatio
        }

        return rawOffset
    }
}

private struct SidebarSpaceSwipeMonitor: NSViewRepresentable {
    let updateSwipeProgress: @MainActor (CGFloat) -> Void
    let finishSwipe: @MainActor (SpaceNavigationDirection) -> Bool
    let cancelSwipe: @MainActor () -> Void

    func makeNSView(context: Context) -> SidebarSpaceSwipeMonitorNSView {
        let nsView = SidebarSpaceSwipeMonitorNSView()
        nsView.updateSwipeProgress = updateSwipeProgress
        nsView.finishSwipe = finishSwipe
        nsView.cancelSwipe = cancelSwipe
        return nsView
    }

    func updateNSView(_ nsView: SidebarSpaceSwipeMonitorNSView, context: Context) {
        nsView.updateSwipeProgress = updateSwipeProgress
        nsView.finishSwipe = finishSwipe
        nsView.cancelSwipe = cancelSwipe
        nsView.installEventMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: SidebarSpaceSwipeMonitorNSView, coordinator: ()) {
        nsView.removeEventMonitor()
    }
}

@MainActor
private final class SidebarSpaceSwipeMonitorNSView: NSView {
    var updateSwipeProgress: (@MainActor (CGFloat) -> Void)?
    var finishSwipe: (@MainActor (SpaceNavigationDirection) -> Bool)?
    var cancelSwipe: (@MainActor () -> Void)?

    private let horizontalDominanceRatio: CGFloat = 1.35
    private let minimumProgressInterval: TimeInterval = 1.0 / 120.0
    private var eventMonitor: Any?
    private var accumulatedHorizontalDelta: CGFloat = 0
    private var isTrackingHorizontalGesture = false
    private var didTriggerInCurrentGesture = false
    private var lastProgressTimestamp: TimeInterval = -Double.infinity
    private var activeSwipeSignpostID: OSSignpostID?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installEventMonitorIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            removeEventMonitor()
        }
    }

    func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else {
            return
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  self.shouldHandle(event) else {
                return event
            }

            return self.handleScrollWheel(event) ? nil : event
        }
    }

    func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        endSwipeSignpostIfNeeded(outcome: "removed")
        resetSwipeState()
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard event.window === window else {
            return false
        }

        let location = convert(event.locationInWindow, from: nil)
        return bounds.contains(location)
    }

    private func handleScrollWheel(_ event: NSEvent) -> Bool {
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            endSwipeSignpostIfNeeded(outcome: "restarted")
            resetSwipeState()
        }

        if isEnding(event) {
            let shouldConsume = isTrackingHorizontalGesture || didTriggerInCurrentGesture
            if isTrackingHorizontalGesture, !didTriggerInCurrentGesture {
                cancelSwipe?()
            }
            endSwipeSignpostIfNeeded(outcome: didTriggerInCurrentGesture ? "completed" : "cancelled")
            resetSwipeState()
            return shouldConsume
        }

        let horizontalDelta = event.scrollingDeltaX
        let verticalDelta = event.scrollingDeltaY
        let hasHorizontalIntent = abs(horizontalDelta) > abs(verticalDelta) * horizontalDominanceRatio
        guard hasHorizontalIntent else {
            return false
        }

        if didTriggerInCurrentGesture {
            return true
        }

        isTrackingHorizontalGesture = true
        accumulatedHorizontalDelta += horizontalDelta
        beginSwipeSignpostIfNeeded()
        publishSwipeProgress(accumulatedHorizontalDelta, event: event, force: false)

        guard abs(accumulatedHorizontalDelta) >= SidebarSpacePagerMetrics.commitDelta else {
            cancelUnphasedGestureIfNeeded(event)
            return true
        }

        publishSwipeProgress(accumulatedHorizontalDelta, event: event, force: true)
        let direction: SpaceNavigationDirection = accumulatedHorizontalDelta > 0 ? .next : .previous
        let didFinish = finishSwipe?(direction) ?? false
        if !didFinish {
            cancelSwipe?()
            endSwipeSignpostIfNeeded(outcome: "edge")
            resetSwipeState()
            return true
        }

        let directionName = direction == .next ? "next" : "previous"
        emitSwipeCommitSignpost(direction: directionName)
        didTriggerInCurrentGesture = true
        if event.phase.isEmpty, event.momentumPhase.isEmpty {
            endSwipeSignpostIfNeeded(outcome: "completed")
            resetSwipeState()
        }
        return true
    }

    private func beginSwipeSignpostIfNeeded() {
        guard activeSwipeSignpostID == nil else {
            return
        }

        let signpostID = OSSignpostID(log: sidebarPerformanceLog)
        activeSwipeSignpostID = signpostID
        os_signpost(.begin, log: sidebarPerformanceLog, name: "SidebarSpaceSwipe", signpostID: signpostID)
    }

    private func emitSwipeCommitSignpost(direction: String) {
        guard let activeSwipeSignpostID else {
            return
        }

        os_signpost(
            .event,
            log: sidebarPerformanceLog,
            name: "SidebarSpaceSwipeCommit",
            signpostID: activeSwipeSignpostID,
            "%{public}s",
            direction
        )
    }

    private func endSwipeSignpostIfNeeded(outcome: String) {
        guard let activeSwipeSignpostID else {
            return
        }

        os_signpost(
            .end,
            log: sidebarPerformanceLog,
            name: "SidebarSpaceSwipe",
            signpostID: activeSwipeSignpostID,
            "%{public}s",
            outcome
        )
        self.activeSwipeSignpostID = nil
    }

    private func publishSwipeProgress(_ deltaX: CGFloat, event: NSEvent, force: Bool) {
        guard force || event.timestamp - lastProgressTimestamp >= minimumProgressInterval else {
            return
        }

        lastProgressTimestamp = event.timestamp
        updateSwipeProgress?(deltaX)
    }

    private func isEnding(_ event: NSEvent) -> Bool {
        event.phase.contains(.ended)
            || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled)
    }

    private func cancelUnphasedGestureIfNeeded(_ event: NSEvent) {
        guard event.phase.isEmpty,
              event.momentumPhase.isEmpty,
              isTrackingHorizontalGesture else {
            return
        }

        cancelSwipe?()
        endSwipeSignpostIfNeeded(outcome: "unphased")
        resetSwipeState()
    }

    private func resetSwipeState() {
        accumulatedHorizontalDelta = 0
        isTrackingHorizontalGesture = false
        didTriggerInCurrentGesture = false
        lastProgressTimestamp = -Double.infinity
        activeSwipeSignpostID = nil
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
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
