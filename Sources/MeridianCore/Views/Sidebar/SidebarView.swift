import AppKit
import OSLog
import SwiftUI

private let sidebarPerformanceLog = OSLog(
    subsystem: "app.meridianbrowser.MeridianBrowser",
    category: "SidebarPerformance"
)

private let sidebarLockControlAnimation = Animation.smooth(duration: 0.24, extraBounce: 0)

private enum SidebarHeaderMetrics {
    static let trafficLightEdgeInset: CGFloat = 12
    static let controlRowHeight: CGFloat = 24
    static let inlineControlHeight: CGFloat = 14
}

public struct SidebarView: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var webViewState: WebViewState
    @State private var window: NSWindow?

    public init(
        store: BrowserStore,
        webViewState: WebViewState
    ) {
        self.store = store
        self.webViewState = webViewState
    }

    public var body: some View {
        VStack(spacing: 0) {
            browserControlsHeader
            compactAddressButton
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
    }

    private var browserControlsHeader: some View {
        HStack(alignment: .top, spacing: 8) {
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
                dispatchWebViewCommand(.goBack)
            }

            SidebarNavigationButton(
                systemName: "chevron.right",
                help: "Forward",
                isDisabled: !webViewState.canGoForward
            ) {
                dispatchWebViewCommand(.goForward)
            }

            SidebarNavigationButton(
                systemName: webViewState.isLoading ? "xmark" : "arrow.clockwise",
                help: webViewState.isLoading ? "Stop" : "Reload",
                isDisabled: store.activeTab?.url == nil
            ) {
                dispatchWebViewCommand(webViewState.isLoading ? .stopLoading : .reload)
            }

            SidebarNavigationButton(
                systemName: "plus",
                help: "New Tab",
                isDisabled: false
            ) {
                store.beginNewTab()
            }
        }
        .frame(height: SidebarHeaderMetrics.controlRowHeight, alignment: .top)
        .padding(.horizontal, SidebarHeaderMetrics.trafficLightEdgeInset)
        .padding(.top, SidebarHeaderMetrics.trafficLightEdgeInset)
        .padding(.bottom, 7)
        .background(WindowTitlebarInteractionZone().accessibilityHidden(true))
    }

    private func dispatchWebViewCommand(_ command: WebViewState.Command) {
        webViewState.dispatch(command, targetTabID: store.selectedTabID)
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

    private var spaceSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.sidebarSpaces) { space in
                    Button {
                        selectSpace(space.id)
                    } label: {
                        SpaceSwitcherButtonLabel(
                            space: space,
                            sidebarSettings: store.sidebarIsLockedOpen
                                ? space.sidebarAppearance.pinnedSettings
                                : space.sidebarAppearance.base,
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
                            Label("Customize Space", systemImage: "slider.horizontal.3")
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
            moveTabToFolder: { draggedTabID, folderID, targetTabID in
                store.moveTab(draggedTabID, toFolder: folderID, before: targetTabID)
            },
            createFolder: { name, spaceID, parentFolderID in
                store.createFolder(name: name, in: spaceID, parentFolderID: parentFolderID)
            },
            customizeSpace: { beginCustomizing($0) },
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
        let activeSpaces = store.sidebarSpaces
        let selectedIndex = selectedSpaceIndex(in: activeSpaces)
        let visibleIndices = SidebarSpacePagerWindow.visibleIndices(
            selectedIndex: selectedIndex,
            count: activeSpaces.count
        )
        let visibleSpaces = visibleIndices.map { activeSpaces[$0] }
        let visibleSpaceIDs = Set(visibleSpaces.map(\.id))
        let foldersByID = Dictionary(
            uniqueKeysWithValues: store.folders
                .lazy
                .filter { visibleSpaceIDs.contains($0.parentSpaceID) }
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
                tabs: tabItems(for: folder.tabIDs, tabsByID: tabsByID),
                childFolders: folderItems(for: folder.childFolderIDs, foldersByID: foldersByID, tabsByID: tabsByID)
            )
        }
    }

    private func close(_ tab: BrowserTab) {
        store.closeTab(tab.id)
    }

    private func beginCustomizing(_ space: BrowserSpace) {
        _ = store.openSpaceCustomizer(for: space.id)
    }

    private var addressText: String {
        if let tab = store.activeTab,
           !tab.content.isWeb {
            return tab.title
        }
        if let url = store.activeTab?.url {
            return url.absoluteString
        }
        return "Search or enter address"
    }

    private var siteSymbolName: String {
        guard store.activeTab?.content.isWeb != false else {
            return "slider.horizontal.3"
        }
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

struct SpaceCustomizationDraft: Identifiable {
    var id: SpaceID
    var name: String
    var symbolName: String
    var colorHex: String
    var sidebarAppearance: SidebarAppearance
    var profileID: ProfileID
}

private struct SpaceSwitcherButtonLabel: View {
    let space: BrowserSpace
    let sidebarSettings: SidebarGlassSettings
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let selectedForegroundColor = selectedIconForegroundColor

        SpaceIconGlyph(
            symbolName: space.symbolName,
            colorHex: space.colorHex,
            size: 32,
            foregroundColor: isSelected ? selectedForegroundColor : .secondary
        )
        .opacity(isSelected ? 1 : 0.74)
        .scaleEffect(isSelected ? 1.08 : 1)
        .frame(width: 24, height: 24)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }

    private var selectedIconForegroundColor: Color {
        let tintHex = space.sidebarAppearance.tintHex(forSpaceColorHex: space.colorHex)

        switch SidebarGlassRendering.selectedSpaceIconContrast(for: sidebarSettings, tintHex: tintHex) {
        case .adaptive:
            return colorScheme == .dark ? .white : .black
        case .dark:
            return .black
        case .light:
            return .white
        }
    }
}

private struct SpaceIconGlyph: View {
    let symbolName: String
    let colorHex: String
    let size: CGFloat
    var foregroundColor: Color? = nil
    var usesMutedIcon = false

    var body: some View {
        let color = foregroundColor ?? (usesMutedIcon ? Color.secondary : Color.secondary)

        ZStack {
            if symbolName == BrowserSpace.defaultSymbolName {
                Circle()
                    .fill(color)
                    .frame(width: size * 0.34, height: size * 0.34)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: symbolPointSize, weight: .semibold))
                    .foregroundStyle(color)
                    .offset(y: SpaceIconOpticalCentering.yOffset(for: symbolName, pointSize: symbolPointSize))
            }
        }
        .frame(width: size, height: size)
    }

    private var symbolPointSize: CGFloat {
        size * 0.45
    }
}

private enum SpaceIconOpticalCentering {
    static func yOffset(for symbolName: String, pointSize: CGFloat) -> CGFloat {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)) else {
            return 0
        }

        let offset = image.alignmentRect.midY - image.size.height / 2
        return abs(offset) < 0.25 ? 0 : offset
    }
}

private struct SidebarTintPreset: Identifiable {
    let id: String
    let name: String
    let tintSource: SidebarTintSource
    let tintHex: String

    var usesSpaceColor: Bool {
        tintSource == .spaceColor
    }
}

private struct SpaceIconCategory: Identifiable {
    let id: String
    let name: String
    let symbolNames: [String]
}

struct SpaceCustomizationSheet: View {
    let draft: SpaceCustomizationDraft
    let profiles: [BrowserProfile]
    let save: (String, String, String, ProfileID, SidebarAppearance) -> Void
    let cancel: () -> Void

    @State private var name: String
    @State private var selectedSymbolName: String
    @State private var selectedColorHex: String
    @State private var selectedProfileID: ProfileID
    @State private var sidebarAppearance: SidebarAppearance
    @State private var selectedIconCategoryID: String

    init(
        draft: SpaceCustomizationDraft,
        profiles: [BrowserProfile],
        save: @escaping (String, String, String, ProfileID, SidebarAppearance) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.profiles = profiles
        self.save = save
        self.cancel = cancel
        _name = State(initialValue: draft.name)
        _selectedSymbolName = State(initialValue: draft.symbolName)
        _selectedColorHex = State(initialValue: draft.colorHex)
        _selectedIconCategoryID = State(initialValue: Self.initialIconCategoryID(for: draft.symbolName))
        let initialProfileID = profiles.contains { $0.id == draft.profileID }
            ? draft.profileID
            : profiles.first?.id ?? draft.profileID
        _selectedProfileID = State(initialValue: initialProfileID)
        var unifiedAppearance = draft.sidebarAppearance
        unifiedAppearance.pinnedOverride = nil
        _sidebarAppearance = State(initialValue: unifiedAppearance)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile")
                            .font(.subheadline.weight(.semibold))
                        Picker("Profile", selection: $selectedProfileID) {
                            ForEach(profiles) { profile in
                                Text(profile.name)
                                    .tag(profile.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    sidebarAppearanceSection

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Icon")
                                .font(.subheadline.weight(.semibold))

                            Spacer()

                            Picker("Icon Set", selection: $selectedIconCategoryID) {
                                ForEach(Self.iconCategories) { category in
                                    Text(category.name).tag(category.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 168)
                        }

                        LazyVGrid(columns: iconColumns, alignment: .leading, spacing: 8) {
                            ForEach(visibleSymbolOptions, id: \.self) { symbolName in
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
                    var unifiedAppearance = sidebarAppearance
                    unifiedAppearance.pinnedOverride = nil
                    save(name, selectedSymbolName, selectedColorHex, selectedProfileID, unifiedAppearance)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 540, height: 720)
    }

    private var sidebarAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sidebar")
                    .font(.subheadline.weight(.semibold))
            }

            themeColorControl

            VStack(alignment: .leading, spacing: 8) {
                Text("Theme Presets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: tintPresetColumns, alignment: .leading, spacing: 8) {
                    ForEach(Self.tintPresets) { preset in
                        SidebarTintPresetButton(
                            preset: preset,
                            colorHex: preset.usesSpaceColor ? selectedColorHex : preset.tintHex,
                            isSelected: isTintPresetSelected(preset)
                        ) {
                            applyTintPreset(preset)
                        }
                    }
                }
            }

            sharedSidebarControls
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.28), lineWidth: 0.5)
        }
    }

    private var themeColorControl: some View {
        let themeColor = Color(hex: themeColorHex)

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(themeColor)
                .frame(width: 44, height: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(.white.opacity(0.40), lineWidth: 0.8)
                }
                .shadow(color: themeColor.opacity(0.34), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text("Theme Color")
                    .font(.subheadline.weight(.semibold))
                Text(themeColorSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ThemeColorEditorButton(colorHex: themeColorHex) { colorHex in
                sidebarAppearance.tintSource = .custom
                sidebarAppearance.tintHex = colorHex
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(themeColor.opacity(0.18))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(themeColor.opacity(0.48), lineWidth: 0.8)
        }
    }

    private var sharedSidebarControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Material")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            SidebarGlassSlider(
                title: "Color",
                value: settingBinding(\.tintOpacity),
                lowLabel: "Neutral",
                highLabel: "Color"
            )
            SidebarGlassSlider(
                title: "Density",
                value: settingBinding(\.glassOpacity),
                lowLabel: "Clear",
                highLabel: "Dense"
            )
            SidebarColorNoiseControl(
                level: settingBinding(\.colorNoiseLevel),
                cellScale: settingBinding(\.colorNoiseScale)
            )
        }
    }

    private var iconColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(40), spacing: 8), count: 8)
    }

    private var tintPresetColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 88), spacing: 8)]
    }

    private func settingBinding(_ keyPath: WritableKeyPath<SidebarGlassSettings, Double>) -> Binding<Double> {
        Binding(
            get: { sidebarAppearance.base[keyPath: keyPath] },
            set: { value in
                sidebarAppearance.base[keyPath: keyPath] = value
                sidebarAppearance.pinnedOverride = nil
            }
        )
    }

    private func isTintPresetSelected(_ preset: SidebarTintPreset) -> Bool {
        if preset.usesSpaceColor {
            return sidebarAppearance.tintSource == .spaceColor
        }
        return sidebarAppearance.tintSource == .custom
            && sidebarAppearance.tintHex.caseInsensitiveCompare(preset.tintHex) == .orderedSame
    }

    private func applyTintPreset(_ preset: SidebarTintPreset) {
        sidebarAppearance.tintSource = preset.tintSource
        sidebarAppearance.tintHex = preset.tintHex
    }

    private var themeColorHex: String {
        sidebarAppearance.tintHex(forSpaceColorHex: selectedColorHex)
    }

    private var themeColorSubtitle: String {
        switch sidebarAppearance.tintSource {
        case .spaceColor:
            return "Uses saved space color"
        case .custom:
            return sidebarAppearance.tintHex.uppercased()
        }
    }

    private var visibleSymbolOptions: [String] {
        Self.iconCategories.first { $0.id == selectedIconCategoryID }?.symbolNames ?? Self.allSymbolOptions
    }

    fileprivate static func initialIconCategoryID(for symbolName: String) -> String {
        curatedIconCategories.first { $0.symbolNames.contains(symbolName) }?.id ?? "all"
    }

    fileprivate static let curatedIconCategories = [
        SpaceIconCategory(
            id: "popular",
            name: "Popular",
            symbolNames: [
                BrowserSpace.defaultSymbolName,
                "sparkles",
                "star.fill",
                "heart.fill",
                "bolt.fill",
                "flame.fill",
                "moon.stars.fill",
                "sun.max.fill",
                "globe.americas.fill",
                "house.fill",
                "briefcase.fill",
                "book.closed.fill",
                "terminal.fill",
                "paintpalette.fill",
                "camera.fill",
                "gamecontroller.fill",
                "folder.fill",
                "shield.fill",
                "lock.fill",
                "flag.fill"
            ]
        ),
        SpaceIconCategory(
            id: "work",
            name: "Work",
            symbolNames: [
                "briefcase.fill",
                "building.2.fill",
                "chart.bar.xaxis",
                "chart.line.uptrend.xyaxis",
                "tray.full.fill",
                "folder.fill",
                "doc.text.fill",
                "doc.richtext.fill",
                "clipboard.fill",
                "calendar",
                "mail.stack.fill",
                "person.2.fill",
                "signature",
                "creditcard.fill",
                "cart.fill",
                "shippingbox.fill",
                "banknote.fill",
                "case.fill"
            ]
        ),
        SpaceIconCategory(
            id: "development",
            name: "Dev",
            symbolNames: [
                "terminal.fill",
                "curlybraces",
                "chevron.left.forwardslash.chevron.right",
                "network",
                "server.rack",
                "externaldrive.fill",
                "internaldrive.fill",
                "cpu.fill",
                "memorychip.fill",
                "hammer.fill",
                "wrench.and.screwdriver.fill",
                "gearshape.fill",
                "slider.horizontal.3",
                "lock.shield.fill",
                "key.fill",
                "antenna.radiowaves.left.and.right"
            ]
        ),
        SpaceIconCategory(
            id: "creative",
            name: "Creative",
            symbolNames: [
                "paintbrush.pointed.fill",
                "paintpalette.fill",
                "pencil.and.outline",
                "highlighter",
                "scissors",
                "camera.fill",
                "photo.fill",
                "photo.stack.fill",
                "video.fill",
                "wand.and.stars",
                "sparkles",
                "theatermasks.fill",
                "music.note",
                "waveform",
                "mic.fill",
                "headphones"
            ]
        ),
        SpaceIconCategory(
            id: "media",
            name: "Media",
            symbolNames: [
                "play.rectangle.fill",
                "tv.fill",
                "display",
                "airplayvideo",
                "speaker.wave.3.fill",
                "headphones",
                "music.note.list",
                "waveform",
                "film.fill",
                "photo.on.rectangle.angled",
                "camera.aperture",
                "book.fill",
                "newspaper.fill",
                "magazine.fill",
                "gamecontroller.fill",
                "dice.fill"
            ]
        ),
        SpaceIconCategory(
            id: "life",
            name: "Life",
            symbolNames: [
                "house.fill",
                "person.crop.circle.fill",
                "person.2.fill",
                "heart.fill",
                "cross.case.fill",
                "figure.walk",
                "dumbbell.fill",
                "fork.knife",
                "cup.and.saucer.fill",
                "takeoutbag.and.cup.and.straw.fill",
                "bed.double.fill",
                "gift.fill",
                "party.popper.fill",
                "leaf.fill",
                "drop.fill",
                "camera.macro"
            ]
        ),
        SpaceIconCategory(
            id: "travel",
            name: "Travel",
            symbolNames: [
                "map.fill",
                "location.fill",
                "mappin.circle.fill",
                "paperplane.fill",
                "airplane",
                "car.fill",
                "tram.fill",
                "bus.fill",
                "bicycle",
                "ferry.fill",
                "sailboat.fill",
                "fuelpump.fill",
                "globe.americas.fill",
                "binoculars.fill",
                "compass.drawing",
                "mountain.2.fill"
            ]
        ),
        SpaceIconCategory(
            id: "focus",
            name: "Focus",
            symbolNames: [
                "target",
                "checkmark.circle.fill",
                "checklist",
                "clock.fill",
                "timer",
                "hourglass",
                "bell.fill",
                "bookmark.fill",
                "pin.fill",
                "flag.fill",
                "eye.fill",
                "brain.head.profile",
                "moon.stars.fill",
                "sun.max.fill",
                "bolt.fill",
                "flame.fill"
            ]
        )
    ]

    fileprivate static let allSymbolOptions: [String] = {
        var seen = Set<String>()
        return curatedIconCategories
            .flatMap(\.symbolNames)
            .filter { seen.insert($0).inserted }
    }()

    fileprivate static let iconCategories = [
        SpaceIconCategory(id: "all", name: "All", symbolNames: allSymbolOptions)
    ] + curatedIconCategories

    fileprivate static let tintPresets = [
        SidebarTintPreset(id: "crystal", name: "Crystal", tintSource: .custom, tintHex: "#F2F7FF"),
        SidebarTintPreset(id: "graphite", name: "Graphite", tintSource: .custom, tintHex: "#8E8E93"),
        SidebarTintPreset(id: "sky", name: "Sky", tintSource: .custom, tintHex: "#64D2FF"),
        SidebarTintPreset(id: "ocean", name: "Ocean", tintSource: .custom, tintHex: "#0A84FF"),
        SidebarTintPreset(id: "violet", name: "Violet", tintSource: .custom, tintHex: "#BF5AF2"),
        SidebarTintPreset(id: "rose", name: "Rose", tintSource: .custom, tintHex: "#FF375F"),
        SidebarTintPreset(id: "amber", name: "Amber", tintSource: .custom, tintHex: "#FFB340"),
        SidebarTintPreset(id: "forest", name: "Forest", tintSource: .custom, tintHex: "#30D158")
    ]

}

struct SpaceCustomizationView: View {
    @ObservedObject private var store: BrowserStore
    let space: BrowserSpace
    let profiles: [BrowserProfile]

    @State private var draftName: String
    @State private var selectedIconCategoryID: String

    init(store: BrowserStore, space: BrowserSpace, profiles: [BrowserProfile]) {
        self.store = store
        self.space = space
        self.profiles = profiles
        _draftName = State(initialValue: space.name)
        _selectedIconCategoryID = State(initialValue: SpaceCustomizationSheet.initialIconCategoryID(for: space.symbolName))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                customizationHeader

                LazyVGrid(columns: pageColumns, alignment: .leading, spacing: 18) {
                    identitySection
                    sidebarMaterialSection
                }

                iconSection
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 1100, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.visible)
        .background(.background)
        .onDisappear {
            store.flushScheduledSessionPersistence()
        }
    }

    private var customizationHeader: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: themeColorHex).opacity(0.16))

                SpaceIconGlyph(
                    symbolName: currentSpace.symbolName,
                    colorHex: currentSpace.colorHex,
                    size: 52,
                    foregroundColor: .secondary
                )
            }
            .frame(width: 72, height: 72)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: themeColorHex).opacity(0.28), lineWidth: 0.8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Customize Space")
                    .font(.title3.weight(.semibold))

                Text(displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private var identitySection: some View {
        SpaceCustomizationPanel(title: "Identity", systemName: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Name", text: Binding(
                        get: { draftName },
                        set: { value in
                            draftName = value
                            _ = updateSpace(name: value)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("Profile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Profile", selection: Binding(
                        get: { currentSpace.profileID },
                        set: { profileID in
                            _ = updateSpace(profileID: profileID)
                        }
                    )) {
                        ForEach(profiles) { profile in
                            Text(profile.name)
                                .tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var sidebarMaterialSection: some View {
        SpaceCustomizationPanel(title: "Sidebar", systemName: "sidebar.leading") {
            VStack(alignment: .leading, spacing: 15) {
                themeColorControl

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("Presets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: tintPresetColumns, alignment: .leading, spacing: 8) {
                        ForEach(SpaceCustomizationSheet.tintPresets) { preset in
                            SidebarTintPresetButton(
                                preset: preset,
                                colorHex: preset.usesSpaceColor ? currentSpace.colorHex : preset.tintHex,
                                isSelected: isTintPresetSelected(preset)
                            ) {
                                applyTintPreset(preset)
                            }
                        }
                    }
                }

                Divider()

                materialControls
            }
        }
    }

    private var materialControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Material")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            SidebarGlassSlider(
                title: "Color",
                value: settingBinding(\.tintOpacity),
                lowLabel: "Neutral",
                highLabel: "Color"
            )
            SidebarGlassSlider(
                title: "Density",
                value: settingBinding(\.glassOpacity),
                lowLabel: "Clear",
                highLabel: "Dense"
            )
            SidebarColorNoiseControl(
                level: settingBinding(\.colorNoiseLevel),
                cellScale: settingBinding(\.colorNoiseScale)
            )
        }
    }

    private var themeColorControl: some View {
        let themeColor = Color(hex: themeColorHex)

        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(themeColor)
                .frame(width: 34, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.42), lineWidth: 0.7)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Theme Color")
                    .font(.caption.weight(.semibold))
                Text(themeColorSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ThemeColorEditorButton(colorHex: themeColorHex) { colorHex in
                var appearance = currentSpace.sidebarAppearance
                appearance.tintSource = .custom
                appearance.tintHex = colorHex
                appearance.pinnedOverride = nil
                _ = updateSpace(sidebarAppearance: appearance)
            }
        }
    }

    private var iconSection: some View {
        SpaceCustomizationPanel(title: "Icon", systemName: "circle.grid.3x3.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Icon Set", selection: $selectedIconCategoryID) {
                    ForEach(SpaceCustomizationSheet.iconCategories) { category in
                        Text(category.name)
                            .tag(category.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180, alignment: .leading)

                LazyVGrid(columns: iconColumns, alignment: .leading, spacing: 8) {
                    ForEach(visibleSymbolOptions, id: \.self) { symbolName in
                        SpaceIconOptionButton(
                            symbolName: symbolName,
                            colorHex: currentSpace.colorHex,
                            isSelected: symbolName == currentSpace.symbolName
                        ) {
                            _ = updateSpace(symbolName: symbolName)
                        }
                    }
                }
            }
        }
    }

    private var displayName: String {
        let trimmedName = currentSpace.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled Space" : trimmedName
    }

    private var currentSpace: BrowserSpace {
        store.spaces.first { $0.id == space.id } ?? space
    }

    private var themeColorHex: String {
        currentSpace.sidebarAppearance.tintHex(forSpaceColorHex: currentSpace.colorHex)
    }

    private var themeColorSubtitle: String {
        switch currentSpace.sidebarAppearance.tintSource {
        case .spaceColor:
            return "Uses saved space color"
        case .custom:
            return currentSpace.sidebarAppearance.tintHex.uppercased()
        }
    }

    private var visibleSymbolOptions: [String] {
        SpaceCustomizationSheet.iconCategories.first { $0.id == selectedIconCategoryID }?.symbolNames
            ?? SpaceCustomizationSheet.allSymbolOptions
    }

    private var iconColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 40), spacing: 8)]
    }

    private var pageColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 430), spacing: 18, alignment: .top)]
    }

    private var tintPresetColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: 8)]
    }

    private func settingBinding(_ keyPath: WritableKeyPath<SidebarGlassSettings, Double>) -> Binding<Double> {
        Binding(
            get: { currentSpace.sidebarAppearance.base[keyPath: keyPath] },
            set: { value in
                var appearance = currentSpace.sidebarAppearance
                appearance.base[keyPath: keyPath] = value
                appearance.pinnedOverride = nil
                _ = updateSpace(sidebarAppearance: appearance)
            }
        )
    }

    private func isTintPresetSelected(_ preset: SidebarTintPreset) -> Bool {
        if preset.usesSpaceColor {
            return currentSpace.sidebarAppearance.tintSource == .spaceColor
        }
        return currentSpace.sidebarAppearance.tintSource == .custom
            && currentSpace.sidebarAppearance.tintHex.caseInsensitiveCompare(preset.tintHex) == .orderedSame
    }

    private func applyTintPreset(_ preset: SidebarTintPreset) {
        var appearance = currentSpace.sidebarAppearance
        appearance.tintSource = preset.tintSource
        appearance.tintHex = preset.tintHex
        appearance.pinnedOverride = nil
        _ = updateSpace(sidebarAppearance: appearance)
    }

    @discardableResult
    private func updateSpace(
        name: String? = nil,
        symbolName: String? = nil,
        profileID: ProfileID? = nil,
        sidebarAppearance: SidebarAppearance? = nil
    ) -> Bool {
        let space = currentSpace
        var appearance = sidebarAppearance
        appearance?.pinnedOverride = nil
        return store.customizeSpace(
            space.id,
            name: name ?? space.name,
            symbolName: symbolName ?? space.symbolName,
            colorHex: space.colorHex,
            profileID: profileID,
            sidebarAppearance: appearance,
            persistImmediately: false
        )
    }
}

private struct SpaceCustomizationPanel<Content: View>: View {
    let title: String
    let systemName: String
    let content: Content

    init(
        title: String,
        systemName: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemName = systemName
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.25), lineWidth: 0.5)
        }
    }
}

private struct SidebarTintPresetButton: View {
    let preset: SidebarTintPreset
    let colorHex: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let color = Color(hex: colorHex)

        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 13, height: 13)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.45), lineWidth: 0.8)
                    }

                Text(preset.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? color.opacity(0.28) : isHovered ? Color.primary.opacity(0.08) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isSelected ? color.opacity(0.65) : Color(nsColor: .separatorColor).opacity(0.22),
                        lineWidth: 0.6
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ThemeColorEditorButton: View {
    let colorHex: String
    let colorChanged: (String) -> Void
    @StateObject private var colorPanel = ThemeColorPanelController()
    @State private var isHovered = false

    var body: some View {
        Button {
            colorPanel.open(initialHex: colorHex, colorChanged: colorChanged)
        } label: {
            Label("Edit", systemImage: "paintpalette")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.34), lineWidth: 0.6)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Edit theme color")
    }
}

@MainActor
private final class ThemeColorPanelController: NSObject, ObservableObject {
    private var colorChanged: ((String) -> Void)?

    func open(initialHex: String, colorChanged: @escaping (String) -> Void) {
        self.colorChanged = colorChanged

        let panel = NSColorPanel.shared
        panel.color = NSColor(Color(hex: initialHex)).usingColorSpace(.sRGB) ?? NSColor(calibratedRed: 0.31, green: 0.49, blue: 0.67, alpha: 1)
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        guard let hexString = Color(nsColor: sender.color).hexString else {
            return
        }
        colorChanged?(hexString)
    }
}

private struct SidebarGlassSlider: View {
    let title: String
    @Binding var value: Double
    var lowLabel: String? = nil
    var highLabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)

                Slider(value: $value, in: 0...1, step: 0.01)

                Text("\(Int((value * 100).rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }

            if lowLabel != nil || highLabel != nil {
                HStack {
                    Text(lowLabel ?? "")
                    Spacer()
                    Text(highLabel ?? "")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.leading, 102)
                .padding(.trailing, 40)
            }
        }
    }
}

private struct SidebarColorNoiseControl: View {
    @Binding var level: Double
    @Binding var cellScale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text("Color Noise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)

                Slider(value: $level, in: 0...1, step: 0.01)

                Text("\(Int((level * 100).rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)

                HStack(spacing: 4) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    Slider(value: $cellScale, in: 0...1, step: 0.01)
                        .controlSize(.mini)
                        .frame(width: 58)
                }
                .help("Noise cell size")
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Noise cell size")
            }

            HStack {
                Text("Clean")
                Spacer()
                Text("Grain")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.leading, 102)
            .padding(.trailing, 112)
        }
    }
}

private struct SpaceIconOptionButton: View {
    let symbolName: String
    let colorHex: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.16) : isHovered ? Color.primary.opacity(0.08) : .clear)

                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.28), lineWidth: 0.8)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 0.7)
                }

                SpaceIconGlyph(
                    symbolName: symbolName,
                    colorHex: colorHex,
                    size: 34,
                    foregroundColor: isSelected ? .primary : .secondary
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

private struct WindowTrafficLightGroup: View {
    let window: NSWindow?

    var body: some View {
        HStack(spacing: WindowTrafficLightMetrics.spacing) {
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

private enum WindowTrafficLightMetrics {
    static let diameter: CGFloat = 14
    static let spacing: CGFloat = 9
    static let hoverSymbolSize: CGFloat = 7.5
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
                .frame(width: WindowTrafficLightMetrics.diameter, height: WindowTrafficLightMetrics.diameter)
                .overlay {
                    if isHovered {
                        Image(systemName: systemName)
                            .font(.system(size: WindowTrafficLightMetrics.hoverSymbolSize, weight: .bold))
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
            .frame(width: 26, height: SidebarHeaderMetrics.inlineControlHeight)
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
                .frame(width: 22, height: SidebarHeaderMetrics.inlineControlHeight)
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

struct SidebarSpacePagerSnapshot: Equatable, Sendable {
    let selectedIndex: Int?
    let spaceCount: Int
    let pages: [SidebarSpacePageSnapshot]
}

struct SidebarSpacePageSnapshot: Identifiable, Equatable, Sendable {
    var id: SpaceID { space.id }

    let index: Int
    let space: BrowserSpace
    let favoriteTabs: [SidebarTabItemSnapshot]
    let pinnedTabs: [SidebarTabItemSnapshot]
    let folders: [SidebarFolderItemSnapshot]
    let regularTabs: [SidebarTabItemSnapshot]
}

struct SidebarFolderItemSnapshot: Identifiable, Equatable, Sendable {
    var id: FolderID { folder.id }

    let folder: BrowserFolder
    let tabs: [SidebarTabItemSnapshot]
    let childFolders: [SidebarFolderItemSnapshot]

    static func == (lhs: SidebarFolderItemSnapshot, rhs: SidebarFolderItemSnapshot) -> Bool {
        lhs.folder == rhs.folder
            && lhs.tabs == rhs.tabs
            && lhs.childFolders == rhs.childFolders
    }
}

struct SidebarTabItemSnapshot: Identifiable, Equatable, Sendable {
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
    let moveTabToFolder: (TabID, FolderID, TabID?) -> Bool
    let createFolder: (String, SpaceID, FolderID?) -> BrowserFolder?
    let customizeSpace: (BrowserSpace) -> Void
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
                        moveTabToPlacement: moveTabToPlacement,
                        moveTabToFolder: moveTabToFolder,
                        createFolder: createFolder,
                        customizeSpace: customizeSpace
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
    nonisolated let page: SidebarSpacePageSnapshot
    let selectTab: (TabID) -> Void
    let closeTab: (BrowserTab) -> Void
    let setTabPlacement: (TabID, BrowserTabPlacement) -> Void
    let moveTab: (TabID, BrowserTabReorderDirection) -> Void
    let moveTabBefore: (TabID, BrowserTabPlacement, TabID) -> Bool
    let moveTabToPlacement: (TabID, BrowserTabPlacement) -> Bool
    let moveTabToFolder: (TabID, FolderID, TabID?) -> Bool
    let createFolder: (String, SpaceID, FolderID?) -> BrowserFolder?
    let customizeSpace: (BrowserSpace) -> Void

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
            .frame(maxWidth: .infinity, minHeight: 1, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .contextMenu {
            Button {
                _ = createFolder("New Folder", page.space.id, nil)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }

            Divider()

            Button {
                customizeSpace(page.space)
            } label: {
                Label("Customize Space", systemImage: "slider.horizontal.3")
            }
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
            SidebarFolderTreeView(
                folders: page.folders,
                spaceID: page.space.id,
                nestingLevel: 0,
                selectTab: selectTab,
                closeTab: closeTab,
                setTabPlacement: setTabPlacement,
                moveTab: moveTab,
                moveTabToFolder: moveTabToFolder,
                createFolder: createFolder
            )
        }
    }

    private func tabRow(
        _ item: SidebarTabItemSnapshot,
        placement: BrowserTabPlacement,
        allowsDropBefore: Bool,
        moveBeforeInContainer: ((TabID) -> Bool)? = nil
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
                if let moveBeforeInContainer {
                    return moveBeforeInContainer(draggedTabID)
                }
                guard allowsDropBefore else {
                    return false
                }
                return moveTabBefore(draggedTabID, placement, item.tab.id)
            }
        )
    }
}

private struct SidebarFolderTreeView: View {
    let folders: [SidebarFolderItemSnapshot]
    let spaceID: SpaceID
    let nestingLevel: Int
    let selectTab: (TabID) -> Void
    let closeTab: (BrowserTab) -> Void
    let setTabPlacement: (TabID, BrowserTabPlacement) -> Void
    let moveTab: (TabID, BrowserTabReorderDirection) -> Void
    let moveTabToFolder: (TabID, FolderID, TabID?) -> Bool
    let createFolder: (String, SpaceID, FolderID?) -> BrowserFolder?

    var body: some View {
        ForEach(folders) { folderItem in
            SidebarFolderNodeView(
                folderItem: folderItem,
                spaceID: spaceID,
                nestingLevel: nestingLevel,
                selectTab: selectTab,
                closeTab: closeTab,
                setTabPlacement: setTabPlacement,
                moveTab: moveTab,
                moveTabToFolder: moveTabToFolder,
                createFolder: createFolder
            )
        }
    }
}

private struct SidebarFolderNodeView: View {
    let folderItem: SidebarFolderItemSnapshot
    let spaceID: SpaceID
    let nestingLevel: Int
    let selectTab: (TabID) -> Void
    let closeTab: (BrowserTab) -> Void
    let setTabPlacement: (TabID, BrowserTabPlacement) -> Void
    let moveTab: (TabID, BrowserTabReorderDirection) -> Void
    let moveTabToFolder: (TabID, FolderID, TabID?) -> Bool
    let createFolder: (String, SpaceID, FolderID?) -> BrowserFolder?

    var body: some View {
        DisclosureGroup(isExpanded: .constant(!folderItem.folder.isCollapsed)) {
            VStack(alignment: .leading, spacing: 2) {
                SidebarFolderTreeView(
                    folders: folderItem.childFolders,
                    spaceID: spaceID,
                    nestingLevel: nestingLevel + 1,
                    selectTab: selectTab,
                    closeTab: closeTab,
                    setTabPlacement: setTabPlacement,
                    moveTab: moveTab,
                    moveTabToFolder: moveTabToFolder,
                    createFolder: createFolder
                )

                ForEach(folderItem.tabs) { item in
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
                            moveTabToFolder(draggedTabID, folderItem.folder.id, item.tab.id)
                        }
                    )
                    .padding(.leading, folderContentIndent)
                }

                folderDropTail
            }
            .padding(.top, 2)
        } label: {
            folderLabel
                .padding(.leading, folderLabelIndent)
                .dropDestination(for: String.self) { values, _ in
                    guard let value = values.first,
                          let draggedTabID = UUID(uuidString: value) else {
                        return false
                    }
                    return moveTabToFolder(draggedTabID, folderItem.folder.id, nil)
                }
                .contextMenu {
                    Button {
                        _ = createFolder("New Subfolder", spaceID, folderItem.folder.id)
                    } label: {
                        Label("New Subfolder", systemImage: "folder.badge.plus")
                    }
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var folderLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(folderItem.folder.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private var folderDropTail: some View {
        Color.clear
            .frame(height: 10)
            .padding(.leading, folderContentIndent)
            .dropDestination(for: String.self) { values, _ in
                guard let value = values.first,
                      let draggedTabID = UUID(uuidString: value) else {
                    return false
                }
                return moveTabToFolder(draggedTabID, folderItem.folder.id, nil)
            }
    }

    private var folderLabelIndent: CGFloat {
        CGFloat(nestingLevel) * 16
    }

    private var folderContentIndent: CGFloat {
        CGFloat(nestingLevel + 1) * 16
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
