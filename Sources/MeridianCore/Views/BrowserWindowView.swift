import AppKit
import SwiftUI

private let sidebarRevealHotZoneWidth: CGFloat = 8

public struct BrowserWindowView: View {
    @ObservedObject private var store: BrowserStore
    @StateObject private var webViewState = WebViewState()
    @State private var sidebarFloatingChromeIsMounted = false
    @State private var sidebarFloatingChromeProgress: CGFloat = 0
    private let dataStoreProvider = ProfileWebsiteDataStoreProvider()
    private let sidebarWidth: CGFloat = 280
    private let sidebarOuterPadding: CGFloat = 8
    private let sidebarCornerRadius: CGFloat = 20
    private var sidebarReservedWidth: CGFloat {
        sidebarWidth + sidebarOuterPadding
    }
    private var appCornerRadius: CGFloat {
        sidebarCornerRadius + sidebarOuterPadding
    }
    private var appShape: ConcentricRectangle {
        ConcentricRectangle(corners: .fixed(appCornerRadius), isUniform: true)
    }
    private var appContainerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: appCornerRadius, style: .continuous)
    }

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        browserSurface
            .background(.background, in: appShape)
            .containerShape(appContainerShape)
            .clipShape(appShape)
            .ignoresSafeArea(.container, edges: ignoredContentSafeAreaEdges)
            .toolbar(removing: .title)
            .toolbarVisibility(.hidden, for: .windowToolbar)
            .background(WindowChromeController(contentCornerRadius: appCornerRadius))
            .background(
                SidebarWindowRevealMonitor(
                    edge: store.sidebarRevealEdge,
                    sidebarIsVisible: store.sidebarIsVisible,
                    sidebarIsLockedOpen: store.sidebarIsLockedOpen,
                    reveal: { store.revealSidebar() }
                )
            )
            .overlay(alignment: .top) {
                WindowDragStrip()
            }
            .animation(.snappy(duration: 0.16), value: store.isCommandBarPresented)
            .animation(.snappy(duration: 0.16), value: store.sidebarIsVisible)
            .animation(.snappy(duration: 0.16), value: store.sidebarIsLockedOpen)
            .onAppear {
                sidebarFloatingChromeIsMounted = !store.sidebarIsLockedOpen
                sidebarFloatingChromeProgress = store.sidebarIsLockedOpen ? 0 : 1
            }
            .task(id: store.sidebarIsLockedOpen) {
                await updateSidebarFloatingChrome()
            }
            .alert(
                store.pendingURLConfirmation?.confirmationTitle ?? "Open Link?",
                isPresented: pendingURLConfirmationIsPresented,
                presenting: store.pendingURLConfirmation
            ) { request in
                Button("Cancel", role: .cancel) {
                    store.cancelPendingURLConfirmation()
                }
                Button(request.confirmButtonTitle) {
                    store.approvePendingURLConfirmation { url in
                        NSWorkspace.shared.open(url)
                    }
                }
            } message: { request in
                Text(request.confirmationMessage)
            }
            .alert(
                store.pendingDownloadConfirmation?.confirmationTitle ?? "Download File?",
                isPresented: pendingDownloadConfirmationIsPresented,
                presenting: store.pendingDownloadConfirmation
            ) { request in
                Button("Cancel", role: .cancel) {
                    store.cancelPendingDownloadConfirmation()
                }
                Button(request.confirmButtonTitle) {
                    if store.beginPendingDownloadDestinationSelection() {
                        presentSavePanel(for: request)
                    }
                }
            } message: { request in
                Text(request.confirmationMessage)
            }
    }

    private var browserSurface: some View {
        ZStack(alignment: sidebarRevealAlignment) {
            browserDetail
                .padding(sidebarPaddingEdge, store.sidebarIsLockedOpen ? sidebarReservedWidth : 0)
                .zIndex(0)

            if sidebarShouldBeMounted {
                sidebarOverlay
                    .zIndex(2)
            } else {
                SidebarRevealZone {
                    store.revealSidebar()
                }
                .frame(width: sidebarRevealHotZoneWidth)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
                .zIndex(3)
            }
        }
    }

    private var browserDetail: some View {
        BrowserContentView(
            store: store,
            webViewState: webViewState,
            dataStoreProvider: dataStoreProvider
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if store.isCommandBarPresented {
                CommandBarView(store: store, webViewState: webViewState)
                    .background(CommandBarOutsideClickMonitor(dismiss: { store.hideCommandBar() }))
                    .padding(.top, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var sidebarOverlay: some View {
        sidebarShell
            .background(
                Group {
                    if !store.sidebarIsLockedOpen {
                        SidebarExitTrackingZone {
                            store.hideTransientSidebar()
                        }
                    }
                }
                .accessibilityHidden(true)
            )
            .transition(.move(edge: sidebarTransitionEdge).combined(with: .opacity))
    }

    private var sidebarShell: some View {
        sidebar
            .frame(width: sidebarContentWidth)
            .padding(.vertical, sidebarCurrentOuterPadding)
            .padding(sidebarPaddingEdge, sidebarCurrentOuterPadding)
    }

    private var sidebar: some View {
        let chromeShape = RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous)
        let clipShape = RoundedRectangle(cornerRadius: sidebarCurrentCornerRadius, style: .continuous)

        return ZStack {
            if sidebarFloatingChromeIsMounted {
                chromeShape
                    .fill(.clear)
                    .glassEffect(.regular, in: chromeShape)
                    .compositingGroup()
                    .opacity(Double(sidebarFloatingChromeProgress))
                    .allowsHitTesting(false)
            }

            SidebarView(store: store, webViewState: webViewState)
        }
            .frame(maxHeight: .infinity)
            .clipShape(clipShape)
            .overlay {
                clipShape
                    .stroke(.separator.opacity(0.42), lineWidth: 0.5)
                    .opacity(Double(sidebarFloatingChromeProgress))
            }
            .accessibilityIdentifier("BrowserSidebar")
    }

    private var sidebarCurrentOuterPadding: CGFloat {
        sidebarOuterPadding * sidebarFloatingChromeProgress
    }

    private var sidebarContentWidth: CGFloat {
        sidebarWidth + sidebarOuterPadding * (1 - sidebarFloatingChromeProgress)
    }

    private var sidebarCurrentCornerRadius: CGFloat {
        sidebarCornerRadius * sidebarFloatingChromeProgress
    }

    private var sidebarShouldBeMounted: Bool {
        store.sidebarIsLockedOpen || store.sidebarIsVisible
    }

    private var sidebarPaddingEdge: Edge.Set {
        switch store.sidebarRevealEdge {
        case .left:
            return .leading
        case .right:
            return .trailing
        }
    }

    private var sidebarRevealAlignment: Alignment {
        switch store.sidebarRevealEdge {
        case .left:
            return .leading
        case .right:
            return .trailing
        }
    }

    private var sidebarTransitionEdge: Edge {
        switch store.sidebarRevealEdge {
        case .left:
            return .leading
        case .right:
            return .trailing
        }
    }

    private var ignoredContentSafeAreaEdges: Edge.Set {
        .top
    }

    @MainActor
    private func updateSidebarFloatingChrome() async {
        if store.sidebarIsLockedOpen {
            guard sidebarFloatingChromeIsMounted || sidebarFloatingChromeProgress > 0 else {
                return
            }

            try? await Task.sleep(nanoseconds: 170_000_000)
            guard !Task.isCancelled else {
                return
            }

            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarFloatingChromeProgress = 0
            }

            try? await Task.sleep(nanoseconds: 190_000_000)
            guard !Task.isCancelled, store.sidebarIsLockedOpen else {
                return
            }

            sidebarFloatingChromeIsMounted = false
        } else {
            sidebarFloatingChromeIsMounted = true
            withAnimation(.easeInOut(duration: 0.12)) {
                sidebarFloatingChromeProgress = 1
            }
        }
    }

    private var pendingURLConfirmationIsPresented: Binding<Bool> {
        Binding {
            store.pendingURLConfirmation != nil
        } set: { isPresented in
            if !isPresented {
                store.cancelPendingURLConfirmation()
            }
        }
    }

    private var pendingDownloadConfirmationIsPresented: Binding<Bool> {
        Binding {
            store.pendingDownloadConfirmation != nil && !store.isChoosingDownloadDestination
        } set: { isPresented in
            if !isPresented {
                store.dismissPendingDownloadConfirmationAlert()
            }
        }
    }

    private func presentSavePanel(for request: DownloadConfirmationRequest) {
        let panel = NSSavePanel()
        panel.title = request.confirmationTitle
        panel.nameFieldStringValue = request.sanitizedFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let destinationURL = panel.url else {
                    store.cancelPendingDownloadConfirmation()
                    return
                }

                store.approvePendingDownloadConfirmation(destination: destinationURL)
            }
        }
    }
}

private struct CommandBarOutsideClickMonitor: NSViewRepresentable {
    let dismiss: @MainActor () -> Void

    func makeNSView(context: Context) -> CommandBarOutsideClickNSView {
        CommandBarOutsideClickNSView()
    }

    func updateNSView(_ nsView: CommandBarOutsideClickNSView, context: Context) {
        nsView.dismiss = dismiss
        nsView.installEventMonitorIfNeeded()
    }
}

private final class CommandBarOutsideClickNSView: NSView {
    var dismiss: (@MainActor () -> Void)?
    private var eventMonitor: Any?

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

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.dismissIfEventIsOutside(event)
            return event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func dismissIfEventIsOutside(_ event: NSEvent) {
        guard event.window === window else {
            return
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard !bounds.contains(localPoint) else {
            return
        }

        Task { @MainActor in dismiss?() }
    }
}

private struct SidebarWindowRevealMonitor: NSViewRepresentable {
    let edge: SidebarRevealEdge
    let sidebarIsVisible: Bool
    let sidebarIsLockedOpen: Bool
    let reveal: @MainActor () -> Void

    func makeNSView(context: Context) -> SidebarWindowRevealNSView {
        SidebarWindowRevealNSView()
    }

    func updateNSView(_ nsView: SidebarWindowRevealNSView, context: Context) {
        nsView.edge = edge
        nsView.sidebarIsVisible = sidebarIsVisible
        nsView.sidebarIsLockedOpen = sidebarIsLockedOpen
        nsView.reveal = reveal
        nsView.window?.acceptsMouseMovedEvents = true
        nsView.startPointerTimerIfNeeded()
        nsView.installEventMonitorIfNeeded()
    }
}

private final class SidebarWindowRevealNSView: NSView {
    var edge: SidebarRevealEdge = .left
    var sidebarIsVisible = true
    var sidebarIsLockedOpen = true
    var reveal: (@MainActor () -> Void)?

    private var pointerTimer: Timer?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        startPointerTimerIfNeeded()
        installEventMonitorIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopPointerTimer()
            removeEventMonitor()
        }
    }

    func startPointerTimerIfNeeded() {
        guard pointerTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.revealIfPointerIsAtWindowEdge()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else {
            return
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func stopPointerTimer() {
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.window === window else {
            return
        }

        revealIfPointerIsAtWindowEdge()
    }

    private func revealIfPointerIsAtWindowEdge() {
        guard !sidebarIsLockedOpen,
              !sidebarIsVisible,
              let window else {
            return
        }

        guard let contentView = window.contentView else {
            return
        }

        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        if contentPoint.isAt(edge: edge, width: sidebarRevealHotZoneWidth, in: contentView.bounds) {
            Task { @MainActor in reveal?() }
        }
    }
}

private struct SidebarRevealZone: NSViewRepresentable {
    let reveal: @MainActor () -> Void

    func makeNSView(context: Context) -> SidebarRevealTrackingNSView {
        SidebarRevealTrackingNSView()
    }

    func updateNSView(_ nsView: SidebarRevealTrackingNSView, context: Context) {
        nsView.reveal = reveal
        nsView.startPointerTimerIfNeeded()
    }
}

private struct SidebarExitTrackingZone: NSViewRepresentable {
    let dismiss: @MainActor () -> Void

    func makeNSView(context: Context) -> SidebarExitTrackingNSView {
        SidebarExitTrackingNSView()
    }

    func updateNSView(_ nsView: SidebarExitTrackingNSView, context: Context) {
        nsView.dismiss = dismiss
        nsView.startPointerTimerIfNeeded()
    }
}

private final class SidebarRevealTrackingNSView: NSView {
    var reveal: (@MainActor () -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var pointerTimer: Timer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        startPointerTimerIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopPointerTimer()
        }
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        triggerReveal()
    }

    override func mouseMoved(with event: NSEvent) {
        triggerReveal()
    }

    override func mouseDragged(with event: NSEvent) {
        triggerReveal()
    }

    override func mouseDown(with event: NSEvent) {
        triggerReveal()
    }

    func startPointerTimerIfNeeded() {
        guard pointerTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.triggerRevealIfPointerIsInside()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func stopPointerTimer() {
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    private func triggerRevealIfPointerIsInside() {
        guard let window else {
            return
        }

        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let localPoint = convert(windowPoint, from: nil)
        if bounds.contains(localPoint) {
            triggerReveal()
        }
    }

    private func triggerReveal() {
        Task { @MainActor in reveal?() }
    }
}

private final class SidebarExitTrackingNSView: NSView {
    var dismiss: (@MainActor () -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var pointerTimer: Timer?
    private var outsideStartDate: Date?
    private let dismissalDelay: TimeInterval = 0.22
    private let boundsTolerance: CGFloat = 24

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        startPointerTimerIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopPointerTimer()
        }
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseExited(with event: NSEvent) {
        updateDismissalState()
    }

    override func mouseMoved(with event: NSEvent) {
        updateDismissalState()
    }

    func startPointerTimerIfNeeded() {
        guard pointerTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDismissalState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func stopPointerTimer() {
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    private func updateDismissalState() {
        guard let window else {
            return
        }

        let windowBounds = convert(bounds, to: nil)
        let screenBounds = window.convertToScreen(windowBounds)
        let protectedBounds = screenBounds.insetBy(dx: -boundsTolerance, dy: -boundsTolerance)

        if protectedBounds.contains(NSEvent.mouseLocation) {
            outsideStartDate = nil
            return
        }

        let now = Date()
        if let outsideStartDate {
            if now.timeIntervalSince(outsideStartDate) >= dismissalDelay {
                self.outsideStartDate = nil
                triggerDismiss()
            }
        } else {
            outsideStartDate = now
        }
    }

    private func triggerDismiss() {
        Task { @MainActor in dismiss?() }
    }
}

private extension NSPoint {
    func isAt(edge: SidebarRevealEdge, width: CGFloat, in bounds: CGRect) -> Bool {
        switch edge {
        case .left:
            return x >= bounds.minX && x <= bounds.minX + width
        case .right:
            return x <= bounds.maxX && x >= bounds.maxX - width
        }
    }
}

private struct WindowDragStrip: View {
    var body: some View {
        WindowTitlebarInteractionZone()
            .frame(height: 8)
            .accessibilityHidden(true)
    }
}

private struct WindowChromeController: NSViewRepresentable {
    let contentCornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.applyMeridianChrome(contentCornerRadius: contentCornerRadius)
        }
    }
}

private extension NSWindow {
    func applyMeridianChrome(contentCornerRadius: CGFloat) {
        title = "Meridian Browser"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        styleMask.remove(.titled)
        styleMask.insert([.closable, .miniaturizable, .resizable, .fullSizeContentView])
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior.insert(.fullScreenPrimary)

        setStandardWindowButtonsHidden(true)
        applyMeridianContentCornerRadius(contentCornerRadius)
        invalidateShadow()
    }

    func setStandardWindowButtonsHidden(_ isHidden: Bool) {
        standardWindowButton(.closeButton)?.isHidden = isHidden
        standardWindowButton(.miniaturizeButton)?.isHidden = isHidden
        standardWindowButton(.zoomButton)?.isHidden = isHidden
    }

    func applyMeridianContentCornerRadius(_ cornerRadius: CGFloat) {
        guard let contentView else {
            return
        }

        [contentView.superview, contentView].compactMap(\.self).forEach { view in
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.cornerRadius = cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
    }
}
