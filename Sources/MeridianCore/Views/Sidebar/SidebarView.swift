import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private struct SidebarForegroundColorEnvironmentKey: EnvironmentKey {
    static let defaultValue = Color.primary
}

private struct SidebarUsesDarkForegroundEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sidebarForegroundColor: Color {
        get { self[SidebarForegroundColorEnvironmentKey.self] }
        set { self[SidebarForegroundColorEnvironmentKey.self] = newValue }
    }

    var sidebarUsesDarkForeground: Bool {
        get { self[SidebarUsesDarkForegroundEnvironmentKey.self] }
        set { self[SidebarUsesDarkForegroundEnvironmentKey.self] = newValue }
    }
}

private let sidebarLockControlAnimation = Animation.smooth(duration: 0.24, extraBounce: 0)
#if DEBUG
private let sidebarSpaceSwitcherLogger = Logger(
    subsystem: "app.barebrowser.BareBrowser",
    category: "SidebarSpaceSwitcher"
)
#endif

private enum SidebarHeaderMetrics {
    static let trafficLightEdgeInset: CGFloat = 12
    static let controlRowHeight: CGFloat = 24
    static let controlRowBottomInset: CGFloat = 7
    static let compactAddressControlsHeight: CGFloat = 34
    static let pageContentTopInset: CGFloat = 20
    static let pageContentBottomInset: CGFloat = 12
    static let inlineControlHeight: CGFloat = 14
    static let spaceSwitcherButtonSize: CGFloat = 26
    static let spaceSwitcherGlyphSize: CGFloat = 26
    static let spaceSwitcherIconFrameSize: CGFloat = 20
    static let spaceSwitcherSpacing: CGFloat = 6
    static let spaceSwitcherPlusSymbolSize: CGFloat = 12

    static var spaceSwitcherVerticalInset: CGFloat {
        max(
            0,
            (trafficLightEdgeInset + controlRowHeight + controlRowBottomInset - spaceSwitcherButtonSize) / 2
        )
    }
}

enum SidebarSpaceSwitcherDropTarget: Equatable {
    case before(SpaceID)
    case tail

    var slotID: String {
        switch self {
        case .before(let spaceID):
            return "before-\(spaceID.uuidString)"
        case .tail:
            return "tail"
        }
    }

    var targetSpaceID: SpaceID? {
        switch self {
        case .before(let spaceID):
            return spaceID
        case .tail:
            return nil
        }
    }
}

enum SidebarSpaceSwitcherLayout {
    static func insertionTargets(for spaceIDs: [SpaceID]) -> [SidebarSpaceSwitcherDropTarget] {
        spaceIDs.map(SidebarSpaceSwitcherDropTarget.before) + [.tail]
    }

    static func target(for locationX: CGFloat, spaceIDs: [SpaceID]) -> SidebarSpaceSwitcherDropTarget? {
        guard !spaceIDs.isEmpty else {
            return nil
        }

        for (index, spaceID) in spaceIDs.enumerated() where locationX < spaceCenterX(at: index) {
            return .before(spaceID)
        }

        return .tail
    }

    static func indicatorX(for target: SidebarSpaceSwitcherDropTarget, spaceIDs: [SpaceID]) -> CGFloat? {
        guard !spaceIDs.isEmpty else {
            return nil
        }

        switch target {
        case .before(let spaceID):
            guard let index = spaceIDs.firstIndex(of: spaceID) else {
                return nil
            }
            return spaceLeftX(at: index) - SidebarHeaderMetrics.spaceSwitcherSpacing / 2
        case .tail:
            return spaceLeftX(at: spaceIDs.count) - SidebarHeaderMetrics.spaceSwitcherSpacing / 2
        }
    }

    private static func spaceLeftX(at index: Int) -> CGFloat {
        let buttonSize = SidebarHeaderMetrics.spaceSwitcherButtonSize
        let itemStride = buttonSize + SidebarHeaderMetrics.spaceSwitcherSpacing
        return buttonSize + SidebarHeaderMetrics.spaceSwitcherSpacing + CGFloat(index) * itemStride
    }

    private static func spaceCenterX(at index: Int) -> CGFloat {
        spaceLeftX(at: index) + SidebarHeaderMetrics.spaceSwitcherButtonSize / 2
    }
}

struct SidebarSpaceSwitcherDragState: Equatable {
    static let cancellationDelayNanoseconds: UInt64 = 4_000_000_000

    var activeTarget: SidebarSpaceSwitcherDropTarget?
    var isDragging = false
    var generation = 0

    @discardableResult
    mutating func beginDrag() -> Int {
        generation += 1
        activeTarget = nil
        isDragging = true
        return generation
    }

    @discardableResult
    mutating func target(_ target: SidebarSpaceSwitcherDropTarget) -> Int {
        if !isDragging {
            generation += 1
            isDragging = true
        }

        activeTarget = target
        return generation
    }

    mutating func clear() {
        guard isDragging || activeTarget != nil else {
            return
        }

        generation += 1
        activeTarget = nil
        isDragging = false
    }

    @discardableResult
    mutating func clearIfCurrentGeneration(_ expectedGeneration: Int) -> Bool {
        guard generation == expectedGeneration else {
            return false
        }

        clear()
        return true
    }
}

enum SidebarSpaceSwitcherDiagnostics {
    static func dragStarted(_ spaceID: SpaceID) {
        #if DEBUG
        sidebarSpaceSwitcherLogger.debug("space drag started id=\(spaceID.uuidString, privacy: .public)")
        #endif
    }

    static func validateDrop(_ isValid: Bool, spaceCount: Int) {
        #if DEBUG
        sidebarSpaceSwitcherLogger.debug("space drop validation valid=\(isValid, privacy: .public) spaceCount=\(spaceCount, privacy: .public)")
        #endif
    }

    static func targetUpdated(_ target: SidebarSpaceSwitcherDropTarget) {
        #if DEBUG
        sidebarSpaceSwitcherLogger.debug("space drop target updated target=\(target.slotID, privacy: .public)")
        #endif
    }

    static func dropCompleted(draggedSpaceID: SpaceID?, target: SidebarSpaceSwitcherDropTarget?, didMove: Bool) {
        #if DEBUG
        let draggedID = draggedSpaceID?.uuidString ?? "nil"
        let targetID = target?.slotID ?? "nil"
        sidebarSpaceSwitcherLogger.debug("space drop completed dragged=\(draggedID, privacy: .public) target=\(targetID, privacy: .public) didMove=\(didMove, privacy: .public)")
        #endif
    }

    static func dragCleared(reason: String) {
        #if DEBUG
        sidebarSpaceSwitcherLogger.debug("space drag cleared reason=\(reason, privacy: .public)")
        #endif
    }
}

public struct SidebarView: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var webViewState: WebViewState
    @ObservedObject private var presentationState: BrowserContentPresentationState
    @Binding private var activityPageIsSelected: Bool
    @State private var window: NSWindow?
    @State private var previewedSpaceID: SpaceID?
    @State private var pagerNavigationRequest: SidebarSpacePagerNavigationRequest?
    @State private var spaceSwitcherDragState = SidebarSpaceSwitcherDragState()
    private let tabHasLiveSession: @MainActor (TabID) -> Bool
    private let updateSidebarChromeTheme: (SidebarChromeTheme?) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sidebarUsesDarkForeground) private var sidebarUsesDarkForeground

    public init(
        store: BrowserStore,
        webViewState: WebViewState,
        presentationState: BrowserContentPresentationState,
        activityPageIsSelected: Binding<Bool> = .constant(false),
        tabHasLiveSession: @escaping @MainActor (TabID) -> Bool = { _ in false },
        updateSidebarChromeTheme: @escaping (SidebarChromeTheme?) -> Void = { _ in }
    ) {
        self.store = store
        self.webViewState = webViewState
        self.presentationState = presentationState
        self._activityPageIsSelected = activityPageIsSelected
        self.tabHasLiveSession = tabHasLiveSession
        self.updateSidebarChromeTheme = updateSidebarChromeTheme
    }

    public var body: some View {
        VStack(spacing: 0) {
            browserControlsHeader
            compactAddressButton
            sidebarSeparator
            spacePager
                .frame(maxHeight: .infinity)
            sidebarSeparator
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
                isDisabled: commandTargetTab?.url == nil
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
        .padding(.bottom, SidebarHeaderMetrics.controlRowBottomInset)
        .background(WindowTitlebarInteractionZone().accessibilityHidden(true))
    }

    private func dispatchWebViewCommand(_ command: WebViewState.Command) {
        webViewState.dispatch(command, targetTabID: commandTargetTabID)
    }

    private var compactAddressButton: some View {
        SidebarAddressControls(
            store: store,
            presentationState: presentationState,
            isActivitySelected: activityPageIsSelected
        )
    }

    private var sidebarSeparator: some View {
        Divider()
            .opacity(sidebarSeparatorOpacity)
            .accessibilityHidden(true)
    }

    private var sidebarSeparatorOpacity: Double {
        guard !sidebarUsesDarkForeground else {
            return 0
        }

        return colorScheme == .dark ? 0.12 : 1
    }

    private var commandTargetTabID: TabID? {
        guard !activityPageIsSelected else {
            return nil
        }

        return presentationState.activeContentTabID ?? store.selectedTabID
    }

    private var commandTargetTab: BrowserTab? {
        guard let commandTargetTabID else {
            return nil
        }

        return store.tabs.first { $0.id == commandTargetTabID }
    }

    private var spaceSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            let sidebarSpaces = store.sidebarSpaces
            let sidebarSpaceIDs = sidebarSpaces.map(\.id)

            HStack(spacing: SidebarHeaderMetrics.spaceSwitcherSpacing) {
                Button {
                    showActivity()
                } label: {
                    ActivitySwitcherButtonLabel(isSelected: isActivitySelected)
                }
                .buttonStyle(.plain)
                .help("History and Downloads")
                .accessibilityLabel("History and Downloads")

                ForEach(sidebarSpaces) { space in
                    spaceSwitcherButton(space)
                }

                Button {
                    _ = store.createSpace(name: "New Space")
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: SidebarHeaderMetrics.spaceSwitcherPlusSymbolSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(
                            width: SidebarHeaderMetrics.spaceSwitcherButtonSize,
                            height: SidebarHeaderMetrics.spaceSwitcherButtonSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New space")
            }
            .overlay(alignment: .leading) {
                ForEach(
                    SidebarSpaceSwitcherLayout.insertionTargets(for: sidebarSpaceIDs),
                    id: \.slotID
                ) { target in
                    if spaceSwitcherDragState.isDragging,
                       let indicatorX = SidebarSpaceSwitcherLayout.indicatorX(
                        for: target,
                        spaceIDs: sidebarSpaceIDs
                       ) {
                        let isActive = spaceSwitcherDragState.activeTarget == target
                        spaceSwitcherDropIndicator(isActive: isActive)
                            .offset(x: indicatorX - (isActive ? 1.5 : 1))
                    }
                }
            }
            .contentShape(Rectangle())
            .onDrop(
                of: SidebarSpaceDragPayload.acceptedTypes,
                delegate: SidebarSpaceSwitcherRowDropDelegate(
                    spaceIDs: sidebarSpaceIDs,
                    dragState: $spaceSwitcherDragState,
                    scheduleDragCancellation: scheduleSpaceSwitcherDragCancellation
                ) { draggedSpaceID, targetSpaceID in
                    withAnimation(SidebarSpacePagerMetrics.selectionAnimation) {
                        store.moveSpace(draggedSpaceID, before: targetSpaceID)
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, SidebarHeaderMetrics.spaceSwitcherVerticalInset)
        }
    }

    private func spaceSwitcherButton(_ space: BrowserSpace) -> some View {
        Button {
            showSpace(space.id)
        } label: {
            SpaceSwitcherButtonLabel(
                space: space,
                isSelected: visualSelectedSpaceID == space.id
            )
        }
        .buttonStyle(.plain)
        .help(space.name)
        .accessibilityLabel(space.name)
        .onDrag {
            beginSpaceSwitcherDrag(space.id)
            return SidebarSpaceDragPayload.itemProvider(for: space.id)
        } preview: {
            SpaceSwitcherButtonLabel(
                space: space,
                isSelected: visualSelectedSpaceID == space.id
            )
        }
        .contextMenu {
            Button {
                beginCustomizing(space)
            } label: {
                Label("Customize Space", systemImage: "slider.horizontal.3")
            }

            Divider()

            Button {
                showSpace(space.id)
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

    private func spaceSwitcherDropIndicator(isActive: Bool) -> some View {
        Capsule()
            .fill(Color.accentColor.opacity(isActive ? 0.95 : 0.32))
            .frame(
                width: isActive ? 3 : 2,
                height: isActive
                    ? SidebarHeaderMetrics.spaceSwitcherButtonSize + 2
                    : SidebarHeaderMetrics.spaceSwitcherButtonSize - 8
            )
            .overlay {
                Capsule()
                    .stroke(.white.opacity(isActive ? 0.55 : 0.25), lineWidth: 0.5)
            }
            .shadow(color: .accentColor.opacity(isActive ? 0.45 : 0), radius: 3)
            .allowsHitTesting(false)
            .animation(SidebarTabReorderInteractionMetrics.indicatorAnimation, value: isActive)
    }

    private func beginSpaceSwitcherDrag(_ spaceID: SpaceID) {
        let generation: Int = withAnimation(SidebarTabReorderInteractionMetrics.indicatorAnimation) {
            spaceSwitcherDragState.beginDrag()
        }
        SidebarSpaceSwitcherDiagnostics.dragStarted(spaceID)
        scheduleSpaceSwitcherDragCancellation(generation)
    }

    private func scheduleSpaceSwitcherDragCancellation(_ generation: Int) {
        Task {
            try? await Task.sleep(nanoseconds: SidebarSpaceSwitcherDragState.cancellationDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                let didClear = withAnimation(SidebarTabReorderInteractionMetrics.indicatorAnimation) {
                    spaceSwitcherDragState.clearIfCurrentGeneration(generation)
                }
                if didClear {
                    SidebarSpaceSwitcherDiagnostics.dragCleared(reason: "timeout")
                }
            }
        }
    }

    @ViewBuilder
    private var spacePager: some View {
        SidebarSpacePagerView(
            snapshot: makeSpacePagerSnapshot(),
            navigationRequest: pagerNavigationRequest,
            selectTab: { store.selectTab($0) },
            closeTab: { store.closeTab($0.id) },
            setTabPlacement: { tabID, placement in store.setTabPlacement(placement, for: tabID) },
            moveTab: { tabID, direction in
                withAnimation(SidebarTabReorderInteractionMetrics.animation) {
                    _ = store.moveTab(tabID, direction)
                }
            },
            moveTabBefore: { draggedTabID, placement, tabID in
                withAnimation(SidebarTabReorderInteractionMetrics.animation) {
                    store.moveTab(draggedTabID, to: placement, before: tabID)
                }
            },
            moveTabToPlacement: { draggedTabID, placement in
                withAnimation(SidebarTabReorderInteractionMetrics.animation) {
                    store.moveTab(draggedTabID, to: placement)
                }
            },
            moveTabToFolder: { draggedTabID, folderID, targetTabID in
                withAnimation(SidebarTabReorderInteractionMetrics.animation) {
                    store.moveTab(draggedTabID, toFolder: folderID, before: targetTabID)
                }
            },
            createFolder: { name, spaceID, parentFolderID in
                store.createFolder(name: name, in: spaceID, parentFolderID: parentFolderID)
            },
            customizeSpace: { beginCustomizing($0) },
            openHistoryEntry: { openHistoryEntry($0) },
            revealDownload: { revealDownload($0) },
            selectSpace: { selectSpace($0) },
            selectAuxiliaryPage: { selectAuxiliaryPage($0) },
            previewSpace: { setPreviewSpace($0) },
            updateSidebarChromeTheme: updateSidebarChromeTheme
        )
    }

    private var visualSelectedSpaceID: SpaceID? {
        previewedSpaceID ?? (selectedAuxiliaryPageID == nil ? store.selectedSpaceID : nil)
    }

    private var isActivitySelected: Bool {
        previewedSpaceID == nil && selectedAuxiliaryPageID == .activity
    }

    private var selectedAuxiliaryPageID: SidebarSpacePagerPageID? {
        get {
            activityPageIsSelected ? .activity : nil
        }
        nonmutating set {
            activityPageIsSelected = newValue == .activity
        }
    }

    private func selectSpace(_ id: SpaceID) {
        guard store.selectedSpaceID != id else {
            return
        }

        presentationState.beginSnapshotHandoff(to: addressPreviewTabID(for: id))
        withTransaction(Transaction(animation: nil)) {
            store.selectSpace(id)
        }
    }

    private func showSpace(_ id: SpaceID) {
        selectedAuxiliaryPageID = nil
        pagerNavigationRequest = SidebarSpacePagerNavigationRequest(pageID: .space(id))
        selectSpace(id)
    }

    private func showActivity() {
        selectedAuxiliaryPageID = .activity
        pagerNavigationRequest = SidebarSpacePagerNavigationRequest(pageID: .activity)
        setPreviewSpace(nil)
    }

    private func selectAuxiliaryPage(_ pageID: SidebarSpacePagerPageID?) {
        selectedAuxiliaryPageID = pageID
    }

    private func makeSpacePagerSnapshot() -> SidebarSpacePagerSnapshot {
        let activeSpaces = store.sidebarSpaces
        let liveSessionTabIDs = Set(store.tabs.lazy.filter { tabHasLiveSession($0.id) }.map(\.id))
        let spacePages = SidebarSpacePageSnapshotBuilder.spacePages(
            activeSpaces: activeSpaces,
            folders: store.folders,
            tabs: store.tabs,
            liveSessionTabIDs: liveSessionTabIDs
        )
        let activityPage = SidebarActivityPageSnapshot(
            profiles: store.profiles,
            downloads: store.downloads,
            historyEntries: store.historyEntries
        )

        return SidebarSpacePagerSnapshot(
            selectedSpacePageID: store.selectedSpaceID.map(SidebarSpacePagerPageID.space),
            selectedAuxiliaryPageID: selectedAuxiliaryPageID,
            spaceCount: activeSpaces.count,
            pages: [.activity(activityPage)] + spacePages.map(SidebarSpacePagerPageSnapshot.space)
        )
    }

    private func close(_ tab: BrowserTab) {
        store.closeTab(tab.id)
    }

    private func beginCustomizing(_ space: BrowserSpace) {
        _ = store.openSpaceCustomizer(for: space.id)
    }

    private func openHistoryEntry(_ entry: BrowserHistoryEntry) {
        let matchingSpaceID: SpaceID?
        if store.selectedSpace?.profileID == entry.profileID {
            matchingSpaceID = store.selectedSpaceID
        } else {
            matchingSpaceID = store.sidebarSpaces.first { $0.profileID == entry.profileID }?.id
        }

        if let matchingSpaceID {
            showSpace(matchingSpaceID)
        }

        store.open(entry.url)
    }

    private func revealDownload(_ download: BrowserDownload) {
        guard let destinationURL = download.destinationURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    private func setPreviewSpace(_ spaceID: SpaceID?) {
        previewedSpaceID = spaceID
        let previewTabID = addressPreviewTabID(for: spaceID)

        withTransaction(Transaction(animation: nil)) {
            presentationState.setPreviewTabID(previewTabID)
            presentationState.setPreviewStartPageSpaceID(previewTabID == nil ? spaceID : nil)
        }
    }

    private func addressPreviewTabID(for spaceID: SpaceID?) -> TabID? {
        guard let spaceID,
              let space = store.sidebarSpaces.first(where: { $0.id == spaceID }) else {
            return nil
        }

        let folders = store.folders.filter { $0.parentSpaceID == space.id }
        let tabsByID = Dictionary(uniqueKeysWithValues: store.tabs.map { ($0.id, $0) })
        return BrowserSpaceFocusedTabResolver.focusedTabID(for: space, folders: folders, tabsByID: tabsByID)
    }

}

private struct ActiveSitePermissionContext {
    var origin: SitePermissionOrigin
    var profileID: ProfileID
}

private struct SidebarAddressControls: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var presentationState: BrowserContentPresentationState
    let isActivitySelected: Bool
    @Environment(\.sidebarForegroundColor) private var sidebarForegroundColor
    @Environment(\.sidebarUsesDarkForeground) private var sidebarUsesDarkForeground
    @State private var didCopyCurrentURL = false

    init(
        store: BrowserStore,
        presentationState: BrowserContentPresentationState,
        isActivitySelected: Bool
    ) {
        self.store = store
        self.presentationState = presentationState
        self.isActivitySelected = isActivitySelected
    }

    var body: some View {
        HStack(spacing: 6) {
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
                            .foregroundStyle(sidebarForegroundColor)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .help("Open command bar")
                .accessibilityLabel("Search or enter address")
                .accessibilityValue(addressText)

                Button {
                    copyCurrentURLToPasteboard()
                } label: {
                    Image(systemName: didCopyCurrentURL ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(currentURLForCopy == nil ? .tertiary : .secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(currentURLForCopy == nil)
                .help("Copy current URL")
                .accessibilityLabel("Copy current URL")
            }
            .padding(.leading, 8)
            .padding(.trailing, 3)
            .frame(height: 26)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                if !sidebarUsesDarkForeground {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.separator.opacity(0.35), lineWidth: 0.5)
                }
            }

            sitePermissionsMenu
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(height: SidebarHeaderMetrics.compactAddressControlsHeight, alignment: .top)
    }

    private var presentedTab: BrowserTab? {
        guard !isActivitySelected else {
            return nil
        }

        if let previewTabID = presentationState.previewTabID,
           let previewTab = store.tabs.first(where: { $0.id == previewTabID }) {
            return previewTab
        }

        return store.activeTab
    }

    private var currentURLForCopy: URL? {
        guard presentedTab?.content.isWeb == true else {
            return nil
        }

        return presentedTab?.url
    }

    private func copyCurrentURLToPasteboard() {
        guard let url = currentURLForCopy else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        didCopyCurrentURL = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopyCurrentURL = false
        }
    }

    private var addressText: String {
        if isActivitySelected {
            return "Activity"
        }

        if let tab = presentedTab,
           !tab.content.isWeb {
            return tab.title
        }
        if let url = presentedTab?.url {
            return url.absoluteString
        }
        return "Search or enter address"
    }

    private var siteSymbolName: String {
        if isActivitySelected {
            return "clock.arrow.circlepath"
        }

        switch presentedTab?.content {
        case .spaceCustomization:
            return "slider.horizontal.3"
        case .passwordManager:
            return "key"
        case .web, nil:
            break
        }
        guard let url = presentedTab?.url else {
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
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(sidebarForegroundColor)
                .foregroundColor(sidebarForegroundColor)
                .frame(width: 26, height: 26)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    if !sidebarUsesDarkForeground {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(.separator.opacity(0.35), lineWidth: 0.5)
                    }
                }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .tint(sidebarForegroundColor)
        .foregroundStyle(sidebarForegroundColor)
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
        guard let tab = presentedTab,
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

enum SidebarSpaceDragPayload {
    static let type = UTType(exportedAs: "com.meridianbrowser.sidebar-space-id")
    static let acceptedTypes: [UTType] = [type]

    static func itemProvider(for spaceID: SpaceID) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = data(for: spaceID)
        provider.registerDataRepresentation(
            forTypeIdentifier: type.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func data(for spaceID: SpaceID) -> Data {
        Data(spaceID.uuidString.utf8)
    }

    static func spaceID(from data: Data) -> SpaceID? {
        String(data: data, encoding: .utf8)
            .flatMap(UUID.init(uuidString:))
    }

    static func loadSpaceID(from info: DropInfo, completion: @escaping @MainActor (SpaceID?) -> Void) {
        loadSpaceID(from: info.itemProviders(for: acceptedTypes), completion: completion)
    }

    static func loadSpaceID(from providers: [NSItemProvider], completion: @escaping @MainActor (SpaceID?) -> Void) {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(type.identifier)
        }) else {
            Task { @MainActor in
                completion(nil)
            }
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            Task { @MainActor in
                completion(data.flatMap(spaceID(from:)))
            }
        }
    }
}

private struct SidebarSpaceSwitcherRowDropDelegate: DropDelegate {
    let spaceIDs: [SpaceID]
    @Binding var dragState: SidebarSpaceSwitcherDragState
    let scheduleDragCancellation: (Int) -> Void
    let moveSpace: (SpaceID, SpaceID?) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        let isValid = !spaceIDs.isEmpty && info.hasItemsConforming(to: SidebarSpaceDragPayload.acceptedTypes)
        SidebarSpaceSwitcherDiagnostics.validateDrop(isValid, spaceCount: spaceIDs.count)
        return isValid
    }

    func dropEntered(info: DropInfo) {
        updateTarget(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(for: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearDragState(reason: "drop exited")
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let target = target(for: info) else {
            clearDragState(reason: "missing target")
            SidebarSpaceSwitcherDiagnostics.dropCompleted(draggedSpaceID: nil, target: nil, didMove: false)
            return false
        }

        clearDragState(reason: "perform drop")

        SidebarSpaceDragPayload.loadSpaceID(from: info) { draggedSpaceID in
            guard let draggedSpaceID else {
                SidebarSpaceSwitcherDiagnostics.dropCompleted(draggedSpaceID: nil, target: target, didMove: false)
                return
            }

            let didMove = moveSpace(draggedSpaceID, target.targetSpaceID)
            SidebarSpaceSwitcherDiagnostics.dropCompleted(
                draggedSpaceID: draggedSpaceID,
                target: target,
                didMove: didMove
            )
        }

        return true
    }

    private func target(for info: DropInfo) -> SidebarSpaceSwitcherDropTarget? {
        SidebarSpaceSwitcherLayout.target(for: info.location.x, spaceIDs: spaceIDs)
    }

    private func updateTarget(for info: DropInfo) {
        guard let target = target(for: info) else {
            clearDragState(reason: "missing target")
            return
        }

        guard dragState.activeTarget != target else {
            scheduleDragCancellation(dragState.generation)
            return
        }

        var generation = dragState.generation
        withAnimation(SidebarTabReorderInteractionMetrics.indicatorAnimation) {
            generation = dragState.target(target)
        }
        SidebarSpaceSwitcherDiagnostics.targetUpdated(target)
        scheduleDragCancellation(generation)
    }

    private func clearDragState(reason: String) {
        guard dragState.isDragging || dragState.activeTarget != nil else {
            return
        }

        withAnimation(SidebarTabReorderInteractionMetrics.indicatorAnimation) {
            dragState.clear()
        }
        SidebarSpaceSwitcherDiagnostics.dragCleared(reason: reason)
    }
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
    let isSelected: Bool
    @Environment(\.sidebarForegroundColor) private var sidebarForegroundColor

    var body: some View {
        SpaceIconGlyph(
            symbolName: space.symbolName,
            colorHex: space.colorHex,
            size: SidebarHeaderMetrics.spaceSwitcherGlyphSize,
            foregroundColor: sidebarForegroundColor
        )
        .opacity(isSelected ? 1 : 0.74)
        .scaleEffect(isSelected ? 1.06 : 1)
        .frame(
            width: SidebarHeaderMetrics.spaceSwitcherIconFrameSize,
            height: SidebarHeaderMetrics.spaceSwitcherIconFrameSize
        )
        .frame(
            width: SidebarHeaderMetrics.spaceSwitcherButtonSize,
            height: SidebarHeaderMetrics.spaceSwitcherButtonSize
        )
        .contentShape(Rectangle())
        .animation(SidebarSpacePagerMetrics.selectionAnimation, value: isSelected)
    }
}

private struct ActivitySwitcherButtonLabel: View {
    let isSelected: Bool
    @Environment(\.sidebarForegroundColor) private var sidebarForegroundColor

    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(sidebarForegroundColor)
            .frame(
                width: SidebarHeaderMetrics.spaceSwitcherIconFrameSize,
                height: SidebarHeaderMetrics.spaceSwitcherIconFrameSize
            )
            .opacity(isSelected ? 1 : 0.74)
            .scaleEffect(isSelected ? 1.06 : 1)
            .frame(
                width: SidebarHeaderMetrics.spaceSwitcherButtonSize,
                height: SidebarHeaderMetrics.spaceSwitcherButtonSize
            )
            .contentShape(Rectangle())
            .animation(SidebarSpacePagerMetrics.selectionAnimation, value: isSelected)
    }
}

struct SpaceIconGlyph: View {
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

@MainActor
private enum SpaceIconOpticalCentering {
    private static var cachedOffsets: [String: CGFloat] = [:]

    static func yOffset(for symbolName: String, pointSize: CGFloat) -> CGFloat {
        let cacheKey = "\(symbolName)#\(Int((pointSize * 100).rounded()))"
        if let cachedOffset = cachedOffsets[cacheKey] {
            return cachedOffset
        }

        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)) else {
            return 0
        }

        let offset = image.alignmentRect.midY - image.size.height / 2
        let normalizedOffset = abs(offset) < 0.25 ? 0 : offset
        cachedOffsets[cacheKey] = normalizedOffset
        return normalizedOffset
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

            SidebarThemeColorEditorButton(
                colorHex: themeColorHex,
                settings: sidebarSettingsBinding
            ) { colorHex in
                sidebarAppearance.tintSource = .custom
                sidebarAppearance.tintHex = colorHex
                sidebarAppearance.pinnedOverride = nil
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

    private var iconColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(40), spacing: 8), count: 8)
    }

    private var tintPresetColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 88), spacing: 8)]
    }

    private var sidebarSettingsBinding: Binding<SidebarGlassSettings> {
        Binding(
            get: { sidebarAppearance.base },
            set: { settings in
                sidebarAppearance.base = settings
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
    let deferredIconGridDelayNanoseconds: UInt64?
    let openThemeColorPicker: (SpaceID) -> Void

    @AppStorage(SpaceCustomizationGlassPreviewBackdropSettings.storageKey)
    private var showsGlassPreviewBackdrop = false
    @State private var draftName: String
    @State private var selectedIconCategoryID: String
    @State private var showsIconSection: Bool

    init(
        store: BrowserStore,
        space: BrowserSpace,
        profiles: [BrowserProfile],
        deferredIconGridDelayNanoseconds: UInt64? = 420_000_000,
        openThemeColorPicker: @escaping (SpaceID) -> Void = { _ in }
    ) {
        self.store = store
        self.space = space
        self.profiles = profiles
        self.deferredIconGridDelayNanoseconds = deferredIconGridDelayNanoseconds
        self.openThemeColorPicker = openThemeColorPicker
        _draftName = State(initialValue: space.name)
        _selectedIconCategoryID = State(initialValue: SpaceCustomizationSheet.initialIconCategoryID(for: space.symbolName))
        _showsIconSection = State(initialValue: deferredIconGridDelayNanoseconds == nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                customizationHeader

                LazyVGrid(columns: pageColumns, alignment: .leading, spacing: 18) {
                    identitySection
                    sidebarMaterialSection
                }

                if showsIconSection {
                    iconSection
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 1100, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.visible)
        .background {
            pageBackground
        }
        .animation(.smooth(duration: 0.18), value: showsGlassPreviewBackdrop)
        .task(id: deferredIconSectionTaskID) {
            await revealDeferredIconSectionIfNeeded()
        }
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

            glassPreviewBackdropToggle
        }
    }

    private var glassPreviewBackdropToggle: some View {
        Toggle(isOn: $showsGlassPreviewBackdrop) {
            Label("Backdrop", systemImage: "photo")
                .font(.caption.weight(.semibold))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .help("Show preview backdrop")
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
            }
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

            SidebarThemeColorEditorButton(
                colorHex: themeColorHex,
                settings: sidebarSettingsBinding,
                openPersistentPicker: { openThemeColorPicker(currentSpace.id) }
            ) { colorHex in
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

    private var deferredIconSectionTaskID: String {
        "\(space.id.uuidString)-\(deferredIconGridDelayNanoseconds ?? 0)"
    }

    private var tintPresetColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: 8)]
    }

    @ViewBuilder
    private var pageBackground: some View {
        if showsGlassPreviewBackdrop {
            SpaceCustomizationGlassPreviewBackdrop()
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    @MainActor
    private func revealDeferredIconSectionIfNeeded() async {
        guard let deferredIconGridDelayNanoseconds,
              !showsIconSection else {
            return
        }

        try? await Task.sleep(nanoseconds: deferredIconGridDelayNanoseconds)

        guard !Task.isCancelled else {
            return
        }

        withTransaction(Transaction(animation: nil)) {
            showsIconSection = true
        }
    }

    private var sidebarSettingsBinding: Binding<SidebarGlassSettings> {
        Binding(
            get: { currentSpace.sidebarAppearance.base },
            set: { settings in
                var appearance = currentSpace.sidebarAppearance
                appearance.base = settings
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

struct SpaceCustomizationPreviewShell: View {
    let space: BrowserSpace
    var profileName: String?

    @AppStorage(SpaceCustomizationGlassPreviewBackdropSettings.storageKey)
    private var showsGlassPreviewBackdrop = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                customizationHeader

                LazyVGrid(columns: pageColumns, alignment: .leading, spacing: 18) {
                    identityPreview
                    sidebarPreview
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 1100, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.visible)
        .background {
            pageBackground
        }
    }

    private var customizationHeader: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: themeColorHex).opacity(0.16))

                SpaceIconGlyph(
                    symbolName: space.symbolName,
                    colorHex: space.colorHex,
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

    private var identityPreview: some View {
        SpaceCustomizationPanel(title: "Identity", systemName: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 16) {
                previewValue(title: "Name", value: displayName)

                Divider()

                previewValue(title: "Profile", value: profileName ?? "Current Profile")
            }
        }
    }

    private var sidebarPreview: some View {
        SpaceCustomizationPanel(title: "Sidebar", systemName: "sidebar.leading") {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: themeColorHex))
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
                }

                Divider()

                previewSlider(title: "Color", value: space.sidebarAppearance.base.tintOpacity)
                previewSlider(title: "Density", value: space.sidebarAppearance.base.glassOpacity)
                previewSlider(title: "Color Noise", value: space.sidebarAppearance.base.colorNoiseLevel)
            }
        }
    }

    private func previewValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func previewSlider(title: String, value: Double) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: max(0, min(1, value)) * proxy.size.width)
                }
            }
            .frame(height: 4)

            Text("\(Int((value * 100).rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var displayName: String {
        let trimmedName = space.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled Space" : trimmedName
    }

    private var themeColorHex: String {
        space.sidebarAppearance.tintHex(forSpaceColorHex: space.colorHex)
    }

    private var themeColorSubtitle: String {
        switch space.sidebarAppearance.tintSource {
        case .spaceColor:
            return "Uses saved space color"
        case .custom:
            return space.sidebarAppearance.tintHex.uppercased()
        }
    }

    private var pageColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 430), spacing: 18, alignment: .top)]
    }

    @ViewBuilder
    private var pageBackground: some View {
        if showsGlassPreviewBackdrop {
            SpaceCustomizationGlassPreviewBackdrop()
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
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
			Image(systemName: "sidebar.leading")
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

enum SidebarSpacePagerPageID: Hashable, Sendable {
    case activity
    case space(SpaceID)

    var spaceID: SpaceID? {
        if case .space(let id) = self {
            return id
        }
        return nil
    }
}

struct SidebarSpacePagerNavigationRequest: Equatable, Sendable {
    let id = UUID()
    let pageID: SidebarSpacePagerPageID
}

struct SidebarSpacePagerSnapshot: Equatable, Sendable {
    let selectedSpacePageID: SidebarSpacePagerPageID?
    let selectedAuxiliaryPageID: SidebarSpacePagerPageID?
    let spaceCount: Int
    let pages: [SidebarSpacePagerPageSnapshot]

    var pageCount: Int {
        pages.count
    }
}

enum SidebarSpacePagerPageSnapshot: Identifiable, Equatable, Sendable {
    case activity(SidebarActivityPageSnapshot)
    case space(SidebarSpacePageSnapshot)

    var id: SidebarSpacePagerPageID {
        switch self {
        case .activity:
            return .activity
        case .space(let page):
            return .space(page.id)
        }
    }

    var space: BrowserSpace? {
        if case .space(let page) = self {
            return page.space
        }
        return nil
    }

    var chromeTheme: SidebarChromeTheme {
        switch self {
        case .activity:
            return .standard
        case .space(let page):
            return SidebarChromeTheme.theme(for: page.space)
        }
    }
}

struct SidebarActivityPageSnapshot: Equatable, Sendable {
    let profiles: [BrowserProfile]
    let downloads: [BrowserDownload]
    let historyEntries: [BrowserHistoryEntry]
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
    let hasLiveSession: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool

    init(
        tab: BrowserTab,
        isSelected: Bool,
        hasLiveSession: Bool = false,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) {
        self.tab = tab
        self.isSelected = isSelected
        self.hasLiveSession = hasLiveSession
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
    }
}

struct SidebarSpacePageSectionVisibility {
    static func showsEmptyFavoriteTabDropSection(
        for page: SidebarSpacePageSnapshot,
        isDragging: Bool
    ) -> Bool {
        isDragging && page.favoriteTabs.isEmpty && hasTabsOutsideFavorites(in: page)
    }

    static func showsEmptyPinnedTabDropSection(
        for page: SidebarSpacePageSnapshot,
        isDragging: Bool
    ) -> Bool {
        isDragging && page.pinnedTabs.isEmpty && hasTabsOutsidePinnedList(in: page)
    }

    static func showsEmptyRegularTabDropSection(
        for page: SidebarSpacePageSnapshot,
        isDragging: Bool
    ) -> Bool {
        isDragging && page.regularTabs.isEmpty && hasTabsOutsideRegular(in: page)
    }

    private static func hasTabsOutsideFavorites(in page: SidebarSpacePageSnapshot) -> Bool {
        !page.pinnedTabs.isEmpty
            || !page.regularTabs.isEmpty
            || page.folders.contains(where: folderContainsTabs)
    }

    private static func hasTabsOutsidePinnedList(in page: SidebarSpacePageSnapshot) -> Bool {
        !page.favoriteTabs.isEmpty
            || !page.regularTabs.isEmpty
            || page.folders.contains(where: folderContainsTabs)
    }

    private static func hasTabsOutsideRegular(in page: SidebarSpacePageSnapshot) -> Bool {
        !page.favoriteTabs.isEmpty
            || !page.pinnedTabs.isEmpty
            || page.folders.contains(where: folderContainsTabs)
    }

    private static func folderContainsTabs(_ folder: SidebarFolderItemSnapshot) -> Bool {
        !folder.tabs.isEmpty || folder.childFolders.contains(where: folderContainsTabs)
    }
}

private struct SidebarSpacePagerView: View {
    let snapshot: SidebarSpacePagerSnapshot
    let navigationRequest: SidebarSpacePagerNavigationRequest?
    let selectTab: (TabID) -> Void
    let closeTab: (BrowserTab) -> Void
    let setTabPlacement: (TabID, BrowserTabPlacement) -> Void
    let moveTab: (TabID, BrowserTabReorderDirection) -> Void
    let moveTabBefore: (TabID, BrowserTabPlacement, TabID) -> Bool
    let moveTabToPlacement: (TabID, BrowserTabPlacement) -> Bool
    let moveTabToFolder: (TabID, FolderID, TabID?) -> Bool
    let createFolder: (String, SpaceID, FolderID?) -> BrowserFolder?
    let customizeSpace: (BrowserSpace) -> Void
    let openHistoryEntry: (BrowserHistoryEntry) -> Void
    let revealDownload: (BrowserDownload) -> Void
    let selectSpace: (SpaceID) -> Void
    let selectAuxiliaryPage: (SidebarSpacePagerPageID?) -> Void
    let previewSpace: (SpaceID?) -> Void
    let updateSidebarChromeTheme: (SidebarChromeTheme?) -> Void

    @State private var scrollPositionPageID: SidebarSpacePagerPageID?
    @State private var scrollIsActive = false
    @State private var visibleFractionalPageIndex: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let pageWidth = max(proxy.size.width, 1)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(snapshot.pages) { page in
                        pageView(page)
                        .id(page.id)
                        .frame(width: pageWidth, height: proxy.size.height, alignment: .top)
                    }
                }
                .scrollTargetLayout()
                .background(EnclosingScrollIndicatorHider())
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .scrollIndicators(.hidden)
            .overlay {
                ScrollIndicatorHiderOverlay(axes: .horizontal)
            }
            .scrollTargetBehavior(SidebarMagneticPageScrollTargetBehavior(
                pageCount: snapshot.pageCount,
                visibleFractionalPageIndex: visibleFractionalPageIndex
            ))
            .scrollPosition(id: $scrollPositionPageID)
            .scrollDisabled(snapshot.pageCount <= 1)
            .onAppear {
                syncScrollPositionToSelection(animated: false)
                previewSpace(nil)
                updateSidebarChromeTheme(selectedChromeTheme)
            }
            .onChange(of: selectedPageID) { _, _ in
                guard !scrollIsActive else {
                    return
                }

                syncScrollPositionToSelection(animated: true)
                previewSpace(nil)
                updateSidebarChromeTheme(selectedChromeTheme)
            }
            .onChange(of: snapshot.selectedSpacePageID) { _, _ in
                selectAuxiliaryPage(nil)
                syncScrollPositionToSelection(animated: true)
                if !scrollIsActive {
                    previewSpace(nil)
                    updateSidebarChromeTheme(selectedChromeTheme)
                }
            }
            .onChange(of: navigationRequest) { _, request in
                guard let request else {
                    return
                }

                if case .space = request.pageID {
                    selectAuxiliaryPage(nil)
                } else {
                    selectAuxiliaryPage(request.pageID)
                }

                withAnimation(SidebarSpacePagerMetrics.selectionAnimation) {
                    scrollPositionPageID = request.pageID
                }
            }
            .onChange(of: scrollPositionPageID) { _, newValue in
                previewPage(newValue)
            }
            .onChange(of: snapshot) { _, _ in
                if !scrollIsActive {
                    previewSpace(nil)
                    updateSidebarChromeTheme(selectedChromeTheme)
                }
            }
            .onScrollPhaseChange { _, newPhase in
                scrollIsActive = newPhase != .idle

                if newPhase == .idle {
                    commitPageIfNeeded(scrollPositionPageID)
                    previewSpace(nil)
                }
            }
            .onScrollGeometryChange(for: SidebarSpacePagerGeometryState.self) { geometry in
                let fractionalPageIndex = geometry.contentOffset.x / pageWidth
                return SidebarSpacePagerGeometryState(
                    fractionalPageIndex: fractionalPageIndex,
                    chromeTheme: SidebarSpacePagerChrome.theme(
                        for: snapshot.pages,
                        fractionalPageIndex: Double(fractionalPageIndex)
                    )
                )
            } action: { _, newState in
                visibleFractionalPageIndex = newState.fractionalPageIndex
                updateSidebarChromeTheme(newState.chromeTheme)
            }
            .onDisappear {
                updateSidebarChromeTheme(nil)
                previewSpace(nil)
            }
        }
    }

    @ViewBuilder
    private func pageView(_ page: SidebarSpacePagerPageSnapshot) -> some View {
        switch page {
        case .activity(let snapshot):
            SidebarActivityPageView(
                snapshot: snapshot,
                openHistoryEntry: openHistoryEntry,
                revealDownload: revealDownload
            )
            .equatable()
        case .space(let snapshot):
            SidebarSpacePageView(
                page: snapshot,
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
        }
    }

    private var selectedChromeTheme: SidebarChromeTheme? {
        guard let selectedPageID,
              let selectedPage = snapshot.pages.first(where: { $0.id == selectedPageID }) else {
            return nil
        }

        return selectedPage.chromeTheme
    }

    private var selectedPageID: SidebarSpacePagerPageID? {
        snapshot.selectedAuxiliaryPageID ?? snapshot.selectedSpacePageID
    }

    private func syncScrollPositionToSelection(animated: Bool) {
        guard let selectedPageID,
              scrollPositionPageID != selectedPageID else {
            return
        }

        if let selectedPageIndex = snapshot.pages.firstIndex(where: { $0.id == selectedPageID }) {
            visibleFractionalPageIndex = CGFloat(selectedPageIndex)
        }

        if animated {
            withAnimation(SidebarSpacePagerMetrics.selectionAnimation) {
                scrollPositionPageID = selectedPageID
            }
        } else {
            scrollPositionPageID = selectedPageID
        }
    }

    private func previewPage(_ pageID: SidebarSpacePagerPageID?) {
        withTransaction(Transaction(animation: nil)) {
            switch pageID {
            case .activity:
                selectAuxiliaryPage(.activity)
                previewSpace(nil)
            case .space(let spaceID):
                selectAuxiliaryPage(nil)
                previewSpace(spaceID)
            case nil:
                previewSpace(nil)
            }
        }
    }

    private func commitPageIfNeeded(_ pageID: SidebarSpacePagerPageID?) {
        guard let committedPageID = SidebarSpacePagerSelection.committedPageID(
            scrollPositionPageID: pageID,
            selectedPageID: selectedPageID,
            pageIDs: snapshot.pages.map(\.id)
        ) else {
            return
        }

        switch committedPageID {
        case .activity:
            selectAuxiliaryPage(.activity)
        case .space(let spaceID):
            selectAuxiliaryPage(nil)
            selectSpace(spaceID)
        }
    }
}

private struct SidebarSpacePagerGeometryState: Equatable {
    let fractionalPageIndex: CGFloat
    let chromeTheme: SidebarChromeTheme?
}

struct SidebarSpacePagerChrome {
    static func theme(
        for pages: [SidebarSpacePagerPageSnapshot],
        fractionalPageIndex: Double
    ) -> SidebarChromeTheme? {
        SidebarChromeTheme.interpolated(
            themes: pages.map(\.chromeTheme),
            fractionalIndex: fractionalPageIndex
        )
    }
}

struct SidebarSpacePagerSelection {
    static func committedPageID(
        scrollPositionPageID: SidebarSpacePagerPageID?,
        selectedPageID: SidebarSpacePagerPageID?,
        pageIDs: [SidebarSpacePagerPageID]
    ) -> SidebarSpacePagerPageID? {
        guard let scrollPositionPageID,
              scrollPositionPageID != selectedPageID,
              pageIDs.contains(scrollPositionPageID) else {
            return nil
        }

        return scrollPositionPageID
    }
}

private struct SidebarMagneticPageScrollTargetBehavior: ScrollTargetBehavior {
    let pageCount: Int
    let visibleFractionalPageIndex: CGFloat?

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard context.axes.contains(.horizontal),
              pageCount > 0 else {
            return
        }

        let pageWidth = context.containerSize.width
        let targetPageIndex = SidebarSpacePagerMagnetism.targetPageIndex(
            originalOffsetX: context.originalTarget.rect.minX,
            proposedOffsetX: target.rect.minX,
            visibleFractionalPageIndex: visibleFractionalPageIndex,
            velocityX: context.velocity.dx,
            pageWidth: pageWidth,
            pageCount: pageCount
        )

        target.rect.origin.x = CGFloat(targetPageIndex) * pageWidth
        target.anchor = .topLeading
    }
}

struct SidebarSpacePagerMagnetism {
    static func targetPageIndex(
        originalOffsetX: CGFloat,
        proposedOffsetX: CGFloat,
        visibleFractionalPageIndex: CGFloat?,
        velocityX: CGFloat,
        pageWidth: CGFloat,
        pageCount: Int
    ) -> Int {
        guard pageCount > 0,
              pageWidth.isFinite,
              pageWidth > 0 else {
            return 0
        }

        let currentPageIndex = clampedPageIndex(
            Int((finiteOffset(originalOffsetX) / pageWidth).rounded()),
            pageCount: pageCount
        )
        let currentPagePosition = CGFloat(currentPageIndex)
        let proposedPagePosition = finiteOffset(proposedOffsetX) / pageWidth
        let proposedDeltaInPages = proposedPagePosition - currentPagePosition
        let proposedDistance = abs(proposedDeltaInPages)

        guard proposedDistance > 0 else {
            return currentPageIndex
        }

        let direction = proposedDeltaInPages > 0 ? 1 : -1
        let actualScrolledDistance = actualScrolledDistance(
            from: currentPagePosition,
            toward: direction,
            visibleFractionalPageIndex: visibleFractionalPageIndex,
            proposedDistance: proposedDistance
        )
        let velocityBonusPages = velocityBonusPages(
            velocityX: velocityX,
            actualScrolledDistance: actualScrolledDistance
        )
        let effectiveDistance = min(proposedDistance, actualScrolledDistance + velocityBonusPages)
        let pageStepCount = magneticPageStepCount(effectiveDistance: effectiveDistance)
        return clampedPageIndex(currentPageIndex + direction * pageStepCount, pageCount: pageCount)
    }

    private static func finiteOffset(_ offset: CGFloat) -> CGFloat {
        offset.isFinite ? offset : 0
    }

    private static func actualScrolledDistance(
        from currentPagePosition: CGFloat,
        toward direction: Int,
        visibleFractionalPageIndex: CGFloat?,
        proposedDistance: CGFloat
    ) -> CGFloat {
        guard let visibleFractionalPageIndex,
              visibleFractionalPageIndex.isFinite else {
            return proposedDistance
        }

        let actualDelta = direction > 0
            ? visibleFractionalPageIndex - currentPagePosition
            : currentPagePosition - visibleFractionalPageIndex
        return min(max(actualDelta, 0), proposedDistance)
    }

    private static func velocityBonusPages(
        velocityX: CGFloat,
        actualScrolledDistance: CGFloat
    ) -> CGFloat {
        guard actualScrolledDistance >= SidebarSpacePagerMetrics.magneticFastFlickDistanceThreshold else {
            return 0
        }

        let speed = abs(velocityX)
        guard speed >= SidebarSpacePagerMetrics.magneticFlickVelocityThreshold else {
            return 0
        }

        let velocityRange = max(
            SidebarSpacePagerMetrics.magneticMaxVelocityBonusVelocity
                - SidebarSpacePagerMetrics.magneticFlickVelocityThreshold,
            1
        )
        let normalizedVelocity = min(
            max((speed - SidebarSpacePagerMetrics.magneticFlickVelocityThreshold) / velocityRange, 0),
            1
        )
        return normalizedVelocity * SidebarSpacePagerMetrics.magneticMaxVelocityBonusPages
    }

    private static func magneticPageStepCount(effectiveDistance: CGFloat) -> Int {
        guard effectiveDistance >= SidebarSpacePagerMetrics.magneticPageDistanceThreshold else {
            return 0
        }

        return Int((effectiveDistance - SidebarSpacePagerMetrics.magneticPageDistanceThreshold).rounded(.down)) + 1
    }

    private static func clampedPageIndex(_ pageIndex: Int, pageCount: Int) -> Int {
        min(max(pageIndex, 0), pageCount - 1)
    }
}

struct SidebarSpacePagerFocus {
    static func focusedTabID(
        for space: BrowserSpace,
        folders: [BrowserFolder],
        tabsByID: [TabID: BrowserTab]
    ) -> TabID? {
        BrowserSpaceFocusedTabResolver.focusedTabID(for: space, folders: folders, tabsByID: tabsByID)
    }

    static func isFocused(tabID: TabID, focusedTabID: TabID?) -> Bool {
        tabID == focusedTabID
    }
}

struct SidebarSpacePageSnapshotBuilder {
    static func spacePages(
        activeSpaces: [BrowserSpace],
        folders: [BrowserFolder],
        tabs: [BrowserTab],
        liveSessionTabIDs: Set<TabID> = []
    ) -> [SidebarSpacePageSnapshot] {
        let pageSpaceIDs = Set(activeSpaces.map(\.id))
        let foldersByID = Dictionary(
            uniqueKeysWithValues: folders
                .lazy
                .filter { pageSpaceIDs.contains($0.parentSpaceID) }
                .map { ($0.id, $0) }
        )
        let foldersBySpaceID = Dictionary(grouping: foldersByID.values, by: \.parentSpaceID)
        let directTabIDs = activeSpaces.flatMap { space in
            space.favoriteTabIDs + space.pinnedTabIDs + space.regularTabIDs
        }
        let folderTabIDs = foldersByID.values.flatMap(\.tabIDs)
        let visibleTabIDs = Set(directTabIDs + folderTabIDs)
        let tabsByID = Dictionary(
            uniqueKeysWithValues: tabs
                .lazy
                .filter { visibleTabIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )

        return activeSpaces.indices.map { index in
            let space = activeSpaces[index]
            let focusedTabID = SidebarSpacePagerFocus.focusedTabID(
                for: space,
                folders: foldersBySpaceID[space.id, default: []],
                tabsByID: tabsByID
            )

            return SidebarSpacePageSnapshot(
                index: index,
                space: space,
                favoriteTabs: tabItems(
                    for: space.favoriteTabIDs,
                    focusedTabID: focusedTabID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                ),
                pinnedTabs: tabItems(
                    for: space.pinnedTabIDs,
                    focusedTabID: focusedTabID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                ),
                folders: folderItems(
                    for: space.folderIDs,
                    focusedTabID: focusedTabID,
                    foldersByID: foldersByID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                ),
                regularTabs: tabItems(
                    for: space.regularTabIDs,
                    focusedTabID: focusedTabID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                )
            )
        }
    }

    private static func tabItems(
        for ids: [TabID],
        focusedTabID: TabID?,
        tabsByID: [TabID: BrowserTab],
        liveSessionTabIDs: Set<TabID>
    ) -> [SidebarTabItemSnapshot] {
        let orderedTabs = ids.compactMap { tabsByID[$0] }
        return orderedTabs.enumerated().map { index, tab in
            SidebarTabItemSnapshot(
                tab: tab,
                isSelected: SidebarSpacePagerFocus.isFocused(tabID: tab.id, focusedTabID: focusedTabID),
                hasLiveSession: liveSessionTabIDs.contains(tab.id),
                canMoveUp: index > 0,
                canMoveDown: index < orderedTabs.count - 1
            )
        }
    }

    private static func folderItems(
        for ids: [FolderID],
        focusedTabID: TabID?,
        foldersByID: [FolderID: BrowserFolder],
        tabsByID: [TabID: BrowserTab],
        liveSessionTabIDs: Set<TabID>
    ) -> [SidebarFolderItemSnapshot] {
        ids.compactMap { id in
            guard let folder = foldersByID[id] else {
                return nil
            }

            return SidebarFolderItemSnapshot(
                folder: folder,
                tabs: tabItems(
                    for: folder.tabIDs,
                    focusedTabID: focusedTabID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                ),
                childFolders: folderItems(
                    for: folder.childFolderIDs,
                    focusedTabID: focusedTabID,
                    foldersByID: foldersByID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                )
            )
        }
    }
}

private enum SidebarActivityMode: CaseIterable, Identifiable {
    case history
    case downloads

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .history:
            return "History"
        case .downloads:
            return "Downloads"
        }
    }

    var symbolName: String {
        switch self {
        case .history:
            return "clock"
        case .downloads:
            return "arrow.down.circle"
        }
    }
}

private struct SidebarActivityPageView: View, Equatable {
    nonisolated let snapshot: SidebarActivityPageSnapshot
    let openHistoryEntry: (BrowserHistoryEntry) -> Void
    let revealDownload: (BrowserDownload) -> Void

    @Environment(\.sidebarUsesDarkForeground) private var sidebarUsesDarkForeground
    @State private var selectedProfileID: ProfileID?
    @State private var selectedMode: SidebarActivityMode = .history
    @State private var profileFilterIsPresented = false

    nonisolated static func == (lhs: SidebarActivityPageView, rhs: SidebarActivityPageView) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    modeButtons
                    selectedSection
                }
                .padding(.horizontal, 10)
                .padding(.top, SidebarHeaderMetrics.pageContentTopInset)
                .padding(.bottom, SidebarHeaderMetrics.pageContentBottomInset)
                .frame(width: max(geometry.size.width, 1), alignment: .topLeading)
                .frame(minHeight: 1, alignment: .topLeading)
                .background(EnclosingScrollIndicatorHider())
            }
            .scrollIndicators(.hidden)
            .background(EnclosingScrollIndicatorHider())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: snapshot.profiles.map(\.id)) { _, profileIDs in
            guard let selectedProfileID,
                  !profileIDs.contains(selectedProfileID) else {
                return
            }

            self.selectedProfileID = nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Activity")
                .font(.headline.weight(.semibold))

            Spacer(minLength: 0)

            profileFilterMenu
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var modeButtons: some View {
        HStack(spacing: 6) {
            ForEach(SidebarActivityMode.allCases) { mode in
                modeButton(mode)
            }
        }
        .padding(.horizontal, 2)
    }

    private func modeButton(_ mode: SidebarActivityMode) -> some View {
        let isSelected = selectedMode == mode
        let count = activityCount(for: mode)

        return Button {
            selectedMode = mode
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 22, alignment: .center)

                Text(mode.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.10) : Color.clear)
            }
            .overlay {
                if !sidebarUsesDarkForeground {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(isSelected ? 0.16 : 0.08), lineWidth: 1)
                }
            }
            .overlay(alignment: .topTrailing) {
                activityCountBadge(count, isSelected: isSelected)
                    .padding(.top, 4)
                    .padding(.trailing, 4)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .accessibilityLabel("\(mode.title), \(count)")
        .help(mode.title)
    }

    private func activityCountBadge(_ count: Int, isSelected: Bool) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 5)
            .frame(minWidth: 18)
            .frame(height: 16)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(isSelected ? 0.14 : 0.08))
            }
            .accessibilityHidden(true)
    }

    private var profileFilterMenu: some View {
        Button {
            profileFilterIsPresented.toggle()
        } label: {
            Image(systemName: selectedProfileID == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selectedProfileID == nil ? Color.secondary : Color.primary)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(selectedProfileID == nil ? 0.06 : 0.12))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .popover(isPresented: $profileFilterIsPresented, arrowEdge: .trailing) {
            profileFilterPopover
        }
        .help("Filter by profile")
        .accessibilityLabel("Filter by profile")
        .accessibilityValue(profileFilterTitle)
    }

    private var profileFilterPopover: some View {
        VStack(alignment: .leading, spacing: 3) {
            profileFilterButton(title: "All Profiles", profileID: nil)

            if !snapshot.profiles.isEmpty {
                Divider()
            }

            ForEach(snapshot.profiles) { profile in
                profileFilterButton(title: profile.name, profileID: profile.id)
            }
        }
        .padding(8)
        .frame(width: 220, alignment: .topLeading)
    }

    private func profileFilterButton(title: String, profileID: ProfileID?) -> some View {
        Button {
            selectedProfileID = profileID
            profileFilterIsPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedProfileID == profileID ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedProfileID == profileID ? Color.accentColor : Color.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.callout)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch selectedMode {
        case .history:
            historySection
        case .downloads:
            downloadsSection
        }
    }

    @ViewBuilder
    private var downloadsSection: some View {
        SidebarSectionHeader(title: "Downloads", symbolName: "arrow.down.circle")
        if filteredDownloads.isEmpty {
            activityEmptyRow("No downloads", symbolName: "tray")
        } else {
            ForEach(filteredDownloads.prefix(10)) { download in
                downloadRow(download)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        SidebarSectionHeader(title: "History", symbolName: "clock")
        if filteredHistoryEntries.isEmpty {
            activityEmptyRow("No history", symbolName: "clock.badge.questionmark")
        } else {
            ForEach(filteredHistoryEntries.prefix(18)) { entry in
                historyRow(entry)
            }
        }
    }

    private func downloadRow(_ download: BrowserDownload) -> some View {
        Button {
            revealDownload(download)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: downloadSymbolName(for: download))
                        .foregroundStyle(downloadSymbolStyle(for: download))
                        .frame(width: 16)

                    Text(download.filename)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    Text(downloadStatusText(for: download))
                    Text("-")
                    Text(profileName(for: download.profileID))
                    Spacer(minLength: 0)
                    Text(download.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if download.state.isActive {
                    ProgressView(value: download.progress)
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(download.destinationURL == nil)
        .help(download.destinationURL == nil ? downloadStatusText(for: download) : "Show in Finder")
    }

    private func historyRow(_ entry: BrowserHistoryEntry) -> some View {
        Button {
            openHistoryEntry(entry)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.callout)
                        .lineLimit(1)
                    Text(entry.displayHost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(profileName(for: entry.profileID))
                        Text("-")
                        Text(entry.lastVisitedAt, style: .relative)
                        if entry.visitCount > 1 {
                            Text("-")
                            Text("\(entry.visitCount) visits")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.url.absoluteString)
    }

    private func activityEmptyRow(_ title: String, symbolName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var filteredDownloads: [BrowserDownload] {
        guard let selectedProfileID else {
            return snapshot.downloads
        }

        return snapshot.downloads.filter { $0.profileID == selectedProfileID }
    }

    private var filteredHistoryEntries: [BrowserHistoryEntry] {
        guard let selectedProfileID else {
            return snapshot.historyEntries
        }

        return snapshot.historyEntries.filter { $0.profileID == selectedProfileID }
    }

    private var profileFilterTitle: String {
        guard let selectedProfileID else {
            return "All Profiles"
        }

        return profileName(for: selectedProfileID)
    }

    private func activityCount(for mode: SidebarActivityMode) -> Int {
        switch mode {
        case .history:
            return filteredHistoryEntries.count
        case .downloads:
            return filteredDownloads.count
        }
    }

    private func profileName(for profileID: ProfileID?) -> String {
        guard let profileID,
              let profile = snapshot.profiles.first(where: { $0.id == profileID }) else {
            return "Unknown Profile"
        }

        return profile.name
    }

    private func downloadStatusText(for download: BrowserDownload) -> String {
        switch download.state {
        case .waitingForDestination:
            return "Waiting"
        case .downloading:
            if let percent = download.progressPercent {
                return "Downloading \(percent)%"
            }
            return "Downloading"
        case .finished:
            return "Finished"
        case .failed:
            return download.failureMessage ?? "Failed"
        case .canceled:
            return "Canceled"
        }
    }

    private func downloadSymbolName(for download: BrowserDownload) -> String {
        switch download.state {
        case .waitingForDestination:
            return "questionmark.folder"
        case .downloading:
            return "arrow.down.circle"
        case .finished:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .canceled:
            return "xmark.circle"
        }
    }

    private func downloadSymbolStyle(for download: BrowserDownload) -> AnyShapeStyle {
        switch download.state {
        case .finished:
            return AnyShapeStyle(.green)
        case .failed:
            return AnyShapeStyle(.yellow)
        case .canceled:
            return AnyShapeStyle(.secondary)
        case .waitingForDestination, .downloading:
            return AnyShapeStyle(.tint)
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

    @State private var tabDropState = SidebarTabDropState()

    nonisolated static func == (lhs: SidebarSpacePageView, rhs: SidebarSpacePageView) -> Bool {
        lhs.page == rhs.page
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                favoriteTabGrid
                emptyFavoriteTabDropTarget
                tabSection(
                    "List Essentials",
                    tabs: page.pinnedTabs,
                    symbolName: "pin.fill",
                    placement: .pinned
                )
                emptyPinnedTabDropTarget
                folderSection
                tabSection(
                    page.space.name,
                    tabs: page.regularTabs,
                    symbolName: "rectangle.stack",
                    placement: .regular,
                    showsWhenEmpty: SidebarSpacePageSectionVisibility.showsEmptyRegularTabDropSection(
                        for: page,
                        isDragging: tabDropState.isDragging
                    )
                )
            }
            .padding(.horizontal, 10)
            .padding(.top, SidebarHeaderMetrics.pageContentTopInset)
            .padding(.bottom, SidebarHeaderMetrics.pageContentBottomInset)
            .frame(maxWidth: .infinity, minHeight: 1, alignment: .topLeading)
            .contentShape(Rectangle())
            .background(EnclosingScrollIndicatorHider())
            .animation(SidebarTabReorderInteractionMetrics.indicatorAnimation, value: tabDropState.isDragging)
        }
        .scrollIndicators(.hidden)
        .background(EnclosingScrollIndicatorHider())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    private var favoriteTabGrid: some View {
        if !page.favoriteTabs.isEmpty {
            SidebarFavoriteTabGrid(
                tabs: page.favoriteTabs,
                selectTab: selectTab,
                closeTab: closeTab,
                setTabPlacement: setTabPlacement,
                moveTab: moveTab,
                moveTabBefore: moveTabBefore,
                moveTabToPlacement: moveTabToPlacement,
                tabDropState: $tabDropState
            )
        }
    }

    @ViewBuilder
    private var emptyFavoriteTabDropTarget: some View {
        if SidebarSpacePageSectionVisibility.showsEmptyFavoriteTabDropSection(
            for: page,
            isDragging: tabDropState.isDragging
        ) {
            SidebarTabDropSlot(
                slotID: tabDropSlotID(placement: .favorite, targetTabID: nil),
                resetToken: tabDropResetToken(for: page.favoriteTabs),
                dropState: $tabDropState,
                hitHeight: SidebarTabReorderInteractionMetrics.emptySectionDropSlotHitHeight
            ) { draggedTabID in
                moveTabToPlacement(draggedTabID, .favorite)
            }
        }
    }

    @ViewBuilder
    private var emptyPinnedTabDropTarget: some View {
        if SidebarSpacePageSectionVisibility.showsEmptyPinnedTabDropSection(
            for: page,
            isDragging: tabDropState.isDragging
        ) {
            SidebarTabDropSlot(
                slotID: tabDropSlotID(placement: .pinned, targetTabID: nil),
                resetToken: tabDropResetToken(for: page.pinnedTabs),
                dropState: $tabDropState,
                hitHeight: SidebarTabReorderInteractionMetrics.emptySectionDropSlotHitHeight
            ) { draggedTabID in
                moveTabToPlacement(draggedTabID, .pinned)
            }
        }
    }

    @ViewBuilder
    private func tabSection(
        _ title: String,
        tabs: [SidebarTabItemSnapshot],
        symbolName: String,
        placement: BrowserTabPlacement,
        showsWhenEmpty: Bool = false
    ) -> some View {
        if !tabs.isEmpty || showsWhenEmpty {
            let resetToken = tabDropResetToken(for: tabs)
            let indexedTabs = Array(tabs.enumerated())

            VStack(alignment: .leading, spacing: 0) {
                SidebarSectionHeader(title: title, symbolName: symbolName)

                ForEach(indexedTabs, id: \.element.id) { offset, item in
                    let upperTarget = tabDropTargetBefore(item, placement: placement)
                    let lowerTarget = tabDropTargetAfter(offset: offset, tabs: tabs, placement: placement)

                    SidebarTabDropSlot(
                        slotID: upperTarget.slotID,
                        resetToken: resetToken,
                        dropState: $tabDropState
                    ) { draggedTabID in
                        upperTarget.moveTab(draggedTabID)
                    }

                    tabRow(
                        item,
                        upperDropTarget: upperTarget,
                        lowerDropTarget: lowerTarget
                    )
                }

                SidebarTabDropSlot(
                    slotID: tabDropSlotID(placement: placement, targetTabID: nil),
                    resetToken: resetToken,
                    dropState: $tabDropState,
                    hitHeight: tabs.isEmpty
                        ? SidebarTabReorderInteractionMetrics.emptySectionDropSlotHitHeight
                        : SidebarTabReorderInteractionMetrics.dropSlotHitHeight
                ) { draggedTabID in
                    moveTabToPlacement(draggedTabID, placement)
                }
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
                createFolder: createFolder,
                tabDropState: $tabDropState
            )
        }
    }

    private func tabRow(
        _ item: SidebarTabItemSnapshot,
        upperDropTarget: SidebarTabDropTarget,
        lowerDropTarget: SidebarTabDropTarget
    ) -> some View {
        SidebarTabDropRegion(
            upperTarget: upperDropTarget,
            lowerTarget: lowerDropTarget,
            dropState: $tabDropState
        ) {
            SidebarTabRow(
                tab: item.tab,
                isSelected: item.isSelected,
                select: { selectTab(item.tab.id) },
                close: { closeTab(item.tab) },
                setPlacement: { placement in setTabPlacement(item.tab.id, placement) },
                move: { direction in moveTab(item.tab.id, direction) },
                canClose: item.hasLiveSession,
                canMoveUp: item.canMoveUp,
                canMoveDown: item.canMoveDown,
                dragStarted: { tabDropState.beginDrag() }
            )
        }
    }

    private func tabDropResetToken(for tabs: [SidebarTabItemSnapshot]) -> String {
        tabs.map { $0.tab.id.uuidString }.joined(separator: "|")
    }

    private func tabDropSlotID(placement: BrowserTabPlacement, targetTabID: TabID?) -> String {
        let target = targetTabID?.uuidString ?? "tail"
        return "\(page.space.id.uuidString)-\(placement)-\(target)"
    }

    private func tabDropTargetBefore(
        _ item: SidebarTabItemSnapshot,
        placement: BrowserTabPlacement
    ) -> SidebarTabDropTarget {
        SidebarTabDropTarget(
            slotID: tabDropSlotID(placement: placement, targetTabID: item.tab.id)
        ) { draggedTabID in
            moveTabBefore(draggedTabID, placement, item.tab.id)
        }
    }

    private func tabDropTargetAfter(
        offset: Int,
        tabs: [SidebarTabItemSnapshot],
        placement: BrowserTabPlacement
    ) -> SidebarTabDropTarget {
        if tabs.indices.contains(offset + 1) {
            let nextTabID = tabs[offset + 1].tab.id
            return SidebarTabDropTarget(
                slotID: tabDropSlotID(placement: placement, targetTabID: nextTabID)
            ) { draggedTabID in
                moveTabBefore(draggedTabID, placement, nextTabID)
            }
        }

        return SidebarTabDropTarget(
            slotID: tabDropSlotID(placement: placement, targetTabID: nil)
        ) { draggedTabID in
            moveTabToPlacement(draggedTabID, placement)
        }
    }
}

private struct ScrollIndicatorHiderOverlay: View {
    var axes: ScrollIndicatorHiderAxes = .all

    var body: some View {
        GeometryReader { proxy in
            EnclosingScrollIndicatorHider(axes: axes)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}

private enum ScrollIndicatorHiderAxes {
    case horizontal
    case vertical
    case all

    var hidesHorizontal: Bool {
        self == .horizontal || self == .all
    }

    var hidesVertical: Bool {
        self == .vertical || self == .all
    }
}

private struct EnclosingScrollIndicatorHider: NSViewRepresentable {
    var axes: ScrollIndicatorHiderAxes = .all

    func makeNSView(context: Context) -> EnclosingScrollIndicatorHidingView {
        let view = EnclosingScrollIndicatorHidingView()
        view.axes = axes
        return view
    }

    func updateNSView(_ nsView: EnclosingScrollIndicatorHidingView, context: Context) {
        nsView.axes = axes
        nsView.hideEnclosingIndicators()
    }
}

private final class EnclosingScrollIndicatorHidingView: NSView {
    var axes: ScrollIndicatorHiderAxes = .all {
        didSet {
            hideEnclosingIndicators()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideEnclosingIndicators()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        hideEnclosingIndicators()
    }

    override func layout() {
        super.layout()
        hideEnclosingIndicators()
    }

    func hideEnclosingIndicators() {
        configureMatchingScrollViews()

        DispatchQueue.main.async { [weak self] in
            self?.configureMatchingScrollViews()
        }
    }

    private func configureMatchingScrollViews() {
        guard let nearestScrollView else {
            return
        }

        configure(nearestScrollView)
    }

    private var nearestScrollView: NSScrollView? {
        var candidate: NSView? = self
        while let current = candidate {
            if let scrollView = current as? NSScrollView {
                return scrollView
            }
            candidate = current.superview
        }

        return enclosingScrollView
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.autohidesScrollers = true
        scrollView.usesPredominantAxisScrolling = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.scrollerInsets = NSEdgeInsets()

        if axes.hidesHorizontal {
            scrollView.hasHorizontalScroller = false
            scrollView.horizontalScroller?.isHidden = true
            scrollView.horizontalScrollElasticity = .none
        }

        if axes.hidesVertical {
            scrollView.hasVerticalScroller = false
            scrollView.verticalScroller?.isHidden = true
            scrollView.verticalScrollElasticity = .none
        }
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
    @Binding var tabDropState: SidebarTabDropState

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
                createFolder: createFolder,
                tabDropState: $tabDropState
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
    @Binding var tabDropState: SidebarTabDropState

    var body: some View {
        DisclosureGroup(isExpanded: .constant(!folderItem.folder.isCollapsed)) {
            let resetToken = tabDropResetToken(for: folderItem.tabs)
            let indexedTabs = Array(folderItem.tabs.enumerated())

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
                    createFolder: createFolder,
                    tabDropState: $tabDropState
                )

                ForEach(indexedTabs, id: \.element.id) { offset, item in
                    let upperTarget = tabDropTargetBefore(item)
                    let lowerTarget = tabDropTargetAfter(offset: offset, tabs: folderItem.tabs)

                    SidebarTabDropSlot(
                        slotID: upperTarget.slotID,
                        resetToken: resetToken,
                        dropState: $tabDropState
                    ) { draggedTabID in
                        upperTarget.moveTab(draggedTabID)
                    }
                    .padding(.leading, folderContentIndent)

                    tabRow(
                        item,
                        upperDropTarget: upperTarget,
                        lowerDropTarget: lowerTarget
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
                    clearDropTargetAfterDrop()
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
        SidebarTabDropSlot(
            slotID: tabDropSlotID(targetTabID: nil),
            resetToken: tabDropResetToken(for: folderItem.tabs),
            dropState: $tabDropState
        ) { draggedTabID in
            moveTabToFolder(draggedTabID, folderItem.folder.id, nil)
        }
            .padding(.leading, folderContentIndent)
    }

    private func tabRow(
        _ item: SidebarTabItemSnapshot,
        upperDropTarget: SidebarTabDropTarget,
        lowerDropTarget: SidebarTabDropTarget
    ) -> some View {
        SidebarTabDropRegion(
            upperTarget: upperDropTarget,
            lowerTarget: lowerDropTarget,
            dropState: $tabDropState
        ) {
            SidebarTabRow(
                tab: item.tab,
                isSelected: item.isSelected,
                select: { selectTab(item.tab.id) },
                close: { closeTab(item.tab) },
                setPlacement: { placement in setTabPlacement(item.tab.id, placement) },
                move: { direction in moveTab(item.tab.id, direction) },
                canClose: item.hasLiveSession,
                canMoveUp: item.canMoveUp,
                canMoveDown: item.canMoveDown,
                dragStarted: { tabDropState.beginDrag() }
            )
        }
    }

    private func clearDropTargetAfterDrop() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            tabDropState.finishDrop()
        }
    }

    private var folderLabelIndent: CGFloat {
        CGFloat(nestingLevel) * 16
    }

    private var folderContentIndent: CGFloat {
        CGFloat(nestingLevel + 1) * 16
    }

    private func tabDropResetToken(for tabs: [SidebarTabItemSnapshot]) -> String {
        tabs.map { $0.tab.id.uuidString }.joined(separator: "|")
    }

    private func tabDropSlotID(targetTabID: TabID?) -> String {
        let target = targetTabID?.uuidString ?? "tail"
        return "\(folderItem.folder.id.uuidString)-\(target)"
    }

    private func tabDropTargetBefore(_ item: SidebarTabItemSnapshot) -> SidebarTabDropTarget {
        SidebarTabDropTarget(
            slotID: tabDropSlotID(targetTabID: item.tab.id)
        ) { draggedTabID in
            moveTabToFolder(draggedTabID, folderItem.folder.id, item.tab.id)
        }
    }

    private func tabDropTargetAfter(
        offset: Int,
        tabs: [SidebarTabItemSnapshot]
    ) -> SidebarTabDropTarget {
        if tabs.indices.contains(offset + 1) {
            let nextTabID = tabs[offset + 1].tab.id
            return SidebarTabDropTarget(
                slotID: tabDropSlotID(targetTabID: nextTabID)
            ) { draggedTabID in
                moveTabToFolder(draggedTabID, folderItem.folder.id, nextTabID)
            }
        }

        return SidebarTabDropTarget(
            slotID: tabDropSlotID(targetTabID: nil)
        ) { draggedTabID in
            moveTabToFolder(draggedTabID, folderItem.folder.id, nil)
        }
    }
}

enum SidebarSpacePagerMetrics {
    static let selectionAnimation: Animation = .smooth(duration: 0.18, extraBounce: 0)
    static let magneticPageDistanceThreshold: CGFloat = 0.55
    static let magneticFlickDistanceThreshold: CGFloat = 0.16
    static let magneticFlickVelocityThreshold: CGFloat = 600
    static let magneticFastFlickDistanceThreshold: CGFloat = 0.03
    static let magneticFastFlickVelocityThreshold: CGFloat = 900
    static let magneticMaxVelocityBonusPages: CGFloat = 0.9
    static let magneticMaxVelocityBonusVelocity: CGFloat = 900
}
