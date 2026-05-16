import AppKit
import SwiftUI

private let sidebarRevealHotZoneWidth: CGFloat = 8

private enum BrowserSidebarSizing {
    static let widthStorageKey = "BrowserSidebarWidth"
    static let defaultWidth = 280.0
    static let minimumWidth: CGFloat = 220
    static let maximumWidth: CGFloat = 520
    static let resizeOverlayWidth: CGFloat = 18
    static let resizeHitWidth: CGFloat = 8
    static let accessibilityStep: CGFloat = 16

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }
}

public struct BrowserWindowView: View {
    @ObservedObject private var store: BrowserStore
    @StateObject private var webViewState = WebViewState()
    @StateObject private var webViewRegistry = BrowserWebViewRegistry()
    @AppStorage(BrowserSidebarSizing.widthStorageKey) private var storedSidebarWidth = BrowserSidebarSizing.defaultWidth
    @State private var sidebarResizeStartWidth: CGFloat?
    @State private var sidebarResizeLiveWidth: CGFloat?
    private let dataStoreProvider = ProfileWebsiteDataStoreProvider()
    private let floatingSidebarInset: CGFloat = 8
    private let floatingSidebarCornerRadius: CGFloat = 12
    private var sidebarWidth: CGFloat {
        sidebarResizeLiveWidth ?? BrowserSidebarSizing.clamped(CGFloat(storedSidebarWidth))
    }
    private var sidebarReservedWidth: CGFloat {
        sidebarWidth
    }

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        browserSurface
            .background(.background)
            .ignoresSafeArea(.container, edges: ignoredContentSafeAreaEdges)
            .toolbar(removing: .title)
            .toolbarVisibility(.hidden, for: .windowToolbar)
            .background(WindowChromeController())
            .background(
                BrowserKeyboardShortcutMonitor(
                    beginNewTab: { store.beginNewTab() }
                )
            )
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
            .overlay {
                if store.isCommandBarPresented {
                    CommandBarDismissalBackdrop {
                        store.hideCommandBar()
                    }
                    .zIndex(9)
                }
            }
            .overlay {
                if store.isCommandBarPresented {
                    CommandBarFloatingLayer(store: store, webViewState: webViewState)
                        .zIndex(10)
                }
            }
            .animation(.snappy(duration: 0.16), value: store.isCommandBarPresented)
            .animation(.snappy(duration: 0.16), value: store.sidebarIsVisible)
            .animation(.snappy(duration: 0.16), value: store.sidebarIsLockedOpen)
            .onAppear {
                normalizeStoredSidebarWidth()
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
        .focusedSceneValue(\.browserNavigationCommandContext, browserNavigationCommandContext)
    }

    private var browserDetail: some View {
        BrowserContentView(
            store: store,
            webViewState: webViewState,
            webViewRegistry: webViewRegistry,
            dataStoreProvider: dataStoreProvider
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarOverlay: some View {
        sidebarShell
            .background(
                Group {
                    if !store.sidebarIsLockedOpen {
                        SidebarExitTrackingZone(dismissalIsSuspended: sidebarResizeStartWidth != nil) {
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
            .frame(width: sidebarWidth)
            .padding(.vertical, sidebarOuterInset)
            .padding(sidebarPaddingEdge, sidebarOuterInset)
    }

    @ViewBuilder
    private var sidebar: some View {
        if store.sidebarIsLockedOpen {
            pinnedSidebar
        } else {
            floatingSidebar
        }
    }

    private var pinnedSidebar: some View {
        ZStack {
            pinnedSidebarChrome
            SidebarView(store: store, webViewState: webViewState)
        }
        .frame(maxHeight: .infinity)
        .overlay { pinnedSidebarSeparator }
        .overlay(alignment: sidebarResizeHandleAlignment) { sidebarResizeHandle }
        .accessibilityIdentifier("BrowserSidebar")
    }

    private var floatingSidebar: some View {
        let shape = RoundedRectangle(cornerRadius: floatingSidebarCornerRadius, style: .continuous)

        return ZStack {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .compositingGroup()
                .allowsHitTesting(false)

            SidebarView(store: store, webViewState: webViewState)
        }
        .frame(maxHeight: .infinity)
        .clipShape(shape)
        .overlay {
            shape.stroke(.separator.opacity(0.42), lineWidth: 0.5)
        }
        .overlay(alignment: sidebarResizeHandleAlignment) { sidebarResizeHandle }
        .accessibilityIdentifier("BrowserSidebar")
    }

    private var pinnedSidebarChrome: some View {
        PinnedSidebarGlassBackdrop()
            .allowsHitTesting(false)
    }

    private var pinnedSidebarSeparator: some View {
        HStack(spacing: 0) {
            if store.sidebarRevealEdge == .right {
                Rectangle()
                    .fill(.separator.opacity(0.34))
                    .frame(width: 0.5)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(.separator.opacity(0.34))
                    .frame(width: 0.5)
            }
        }
        .allowsHitTesting(false)
    }

    private var sidebarOuterInset: CGFloat {
        store.sidebarIsLockedOpen ? 0 : floatingSidebarInset
    }

    private var sidebarResizeHandleAlignment: Alignment {
        switch store.sidebarRevealEdge {
        case .left:
            return .trailing
        case .right:
            return .leading
        }
    }

    private var sidebarResizeHandle: some View {
        SidebarResizeHandle(
            edge: store.sidebarRevealEdge,
            currentWidth: sidebarWidth,
            onResizeBegan: { startWidth in
                sidebarResizeStartWidth = BrowserSidebarSizing.clamped(startWidth)
                sidebarResizeLiveWidth = BrowserSidebarSizing.clamped(startWidth)
            },
            onResizeChanged: { width in
                sidebarResizeLiveWidth = BrowserSidebarSizing.clamped(width)
            },
            onResizeEnded: { width in
                storedSidebarWidth = Double(BrowserSidebarSizing.clamped(width))
                sidebarResizeStartWidth = nil
                sidebarResizeLiveWidth = nil
            }
        )
            .frame(width: BrowserSidebarSizing.resizeOverlayWidth)
            .frame(maxHeight: .infinity)
            .help("Resize sidebar")
            .accessibilityElement()
            .accessibilityLabel("Resize sidebar")
            .accessibilityValue("\(Int(sidebarWidth.rounded())) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    adjustSidebarWidth(by: BrowserSidebarSizing.accessibilityStep)
                case .decrement:
                    adjustSidebarWidth(by: -BrowserSidebarSizing.accessibilityStep)
                @unknown default:
                    break
                }
            }
            .zIndex(1)
    }

    private func adjustSidebarWidth(by delta: CGFloat) {
        storedSidebarWidth = Double(BrowserSidebarSizing.clamped(sidebarWidth + delta))
        sidebarResizeStartWidth = nil
        sidebarResizeLiveWidth = nil
    }

    private func normalizeStoredSidebarWidth() {
        storedSidebarWidth = Double(BrowserSidebarSizing.clamped(CGFloat(storedSidebarWidth)))
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

    private var browserNavigationCommandContext: BrowserNavigationCommandContext {
        BrowserNavigationCommandContext(
            canGoBack: webViewState.canGoBack,
            canGoForward: webViewState.canGoForward,
            canReload: store.activeTab?.url != nil,
            canStopLoading: webViewState.isLoading
        ) { command in
            webViewState.dispatch(command)
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

private struct SidebarResizeHandle: NSViewRepresentable {
    let edge: SidebarRevealEdge
    let currentWidth: CGFloat
    let onResizeBegan: (CGFloat) -> Void
    let onResizeChanged: (CGFloat) -> Void
    let onResizeEnded: (CGFloat) -> Void

    func makeNSView(context: Context) -> SidebarResizeNSView {
        SidebarResizeNSView()
    }

    func updateNSView(_ nsView: SidebarResizeNSView, context: Context) {
        nsView.edge = edge
        nsView.currentWidth = currentWidth
        nsView.onResizeBegan = onResizeBegan
        nsView.onResizeChanged = onResizeChanged
        nsView.onResizeEnded = onResizeEnded
    }
}

private struct PinnedSidebarGlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: .zero)
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.isEmphasized = true
    }
}

private final class SidebarResizeNSView: NSView {
    var edge: SidebarRevealEdge = .left {
        didSet {
            if edge != oldValue {
                window?.invalidateCursorRects(for: self)
            }
        }
    }
    var currentWidth: CGFloat = BrowserSidebarSizing.defaultWidth
    var onResizeBegan: ((CGFloat) -> Void)?
    var onResizeChanged: ((CGFloat) -> Void)?
    var onResizeEnded: ((CGFloat) -> Void)?

    private var dragStartX: CGFloat?
    private var dragStartWidth: CGFloat?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }

        if dragStartX != nil || activeRect.contains(point) {
            return self
        }

        return nil
    }

    override func resetCursorRects() {
        addCursorRect(activeRect, cursor: .resizeLeftRight)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            finishResize(at: nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStartX = event.locationInWindow.x
        dragStartWidth = currentWidth
        onResizeBegan?(currentWidth)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let nextWidth = resizedWidth(at: event.locationInWindow.x) else {
            return
        }

        onResizeChanged?(nextWidth)
    }

    override func mouseUp(with event: NSEvent) {
        finishResize(at: event.locationInWindow.x)
    }

    private var activeRect: CGRect {
        let width = min(BrowserSidebarSizing.resizeHitWidth, bounds.width)
        switch edge {
        case .left:
            return CGRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height)
        case .right:
            return CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
        }
    }

    private func resizedWidth(at windowX: CGFloat) -> CGFloat? {
        guard let dragStartX, let dragStartWidth else {
            return nil
        }

        let delta = switch edge {
        case .left:
            windowX - dragStartX
        case .right:
            dragStartX - windowX
        }

        return BrowserSidebarSizing.clamped(dragStartWidth + delta)
    }

    private func finishResize(at windowX: CGFloat?) {
        let finalWidth = windowX.flatMap(resizedWidth(at:)) ?? currentWidth
        if dragStartX != nil {
            onResizeEnded?(finalWidth)
        }
        dragStartX = nil
        dragStartWidth = nil
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
    let dismissalIsSuspended: Bool
    let dismiss: @MainActor () -> Void

    func makeNSView(context: Context) -> SidebarExitTrackingNSView {
        SidebarExitTrackingNSView()
    }

    func updateNSView(_ nsView: SidebarExitTrackingNSView, context: Context) {
        nsView.dismissalIsSuspended = dismissalIsSuspended
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
    var dismissalIsSuspended = false {
        didSet {
            if dismissalIsSuspended {
                outsideStartDate = nil
            }
        }
    }
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
        guard !dismissalIsSuspended else {
            outsideStartDate = nil
            return
        }

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

struct CommandBarPlacement: Equatable {
    static let originXKey = "CommandBarOriginX"
    static let originYKey = "CommandBarOriginY"
    static let unsetCoordinate = -1.0
    static let margin: CGFloat = 12
    static let defaultTopMargin: CGFloat = 24
    static let boundingSize = CGSize(width: CommandBarMetrics.width, height: CommandBarMetrics.maximumHeight)

    static func resolvedOrigin(
        persistedX: Double,
        persistedY: Double,
        containerSize: CGSize
    ) -> CGPoint {
        let candidate: CGPoint
        if persistedX >= 0, persistedY >= 0, persistedX.isFinite, persistedY.isFinite {
            candidate = CGPoint(x: persistedX, y: persistedY)
        } else {
            candidate = defaultOrigin(containerSize: containerSize)
        }

        return clampedOrigin(candidate, itemSize: boundingSize, containerSize: containerSize)
    }

    static func defaultOrigin(containerSize: CGSize) -> CGPoint {
        CGPoint(
            x: max(margin, (containerSize.width - boundingSize.width) / 2),
            y: defaultTopMargin
        )
    }

    static func clampedOrigin(
        _ origin: CGPoint,
        itemSize: CGSize,
        containerSize: CGSize,
        margin: CGFloat = margin
    ) -> CGPoint {
        CGPoint(
            x: clampedCoordinate(origin.x, itemLength: itemSize.width, containerLength: containerSize.width, margin: margin),
            y: clampedCoordinate(origin.y, itemLength: itemSize.height, containerLength: containerSize.height, margin: margin)
        )
    }

    static func containerID(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    private static func clampedCoordinate(
        _ value: CGFloat,
        itemLength: CGFloat,
        containerLength: CGFloat,
        margin: CGFloat
    ) -> CGFloat {
        guard containerLength > itemLength + margin * 2 else {
            return max(0, (containerLength - itemLength) / 2)
        }

        return min(max(value, margin), containerLength - itemLength - margin)
    }
}

private struct CommandBarFloatingLayer: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var webViewState: WebViewState
    @AppStorage(CommandBarPlacement.originXKey) private var persistedOriginX = CommandBarPlacement.unsetCoordinate
    @AppStorage(CommandBarPlacement.originYKey) private var persistedOriginY = CommandBarPlacement.unsetCoordinate
    @State private var dragStartOrigin: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let origin = CommandBarPlacement.resolvedOrigin(
                persistedX: persistedOriginX,
                persistedY: persistedOriginY,
                containerSize: containerSize
            )

            ZStack(alignment: .topLeading) {
                CommandBarView(store: store, webViewState: webViewState)
                    .offset(x: origin.x, y: origin.y)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .simultaneousGesture(dragGesture(currentOrigin: origin, containerSize: containerSize))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: CommandBarPlacement.containerID(containerSize)) {
                persist(origin)
            }
        }
    }

    private func dragGesture(currentOrigin: CGPoint, containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStartOrigin == nil {
                    dragStartOrigin = currentOrigin
                }

                let startOrigin = dragStartOrigin ?? currentOrigin
                let candidate = CGPoint(
                    x: startOrigin.x + value.translation.width,
                    y: startOrigin.y + value.translation.height
                )
                persist(CommandBarPlacement.clampedOrigin(
                    candidate,
                    itemSize: CommandBarPlacement.boundingSize,
                    containerSize: containerSize
                ))
            }
            .onEnded { _ in
                dragStartOrigin = nil
            }
    }

    private func persist(_ origin: CGPoint) {
        persistedOriginX = origin.x
        persistedOriginY = origin.y
    }
}

private struct BrowserKeyboardShortcutMonitor: NSViewRepresentable {
    let beginNewTab: @MainActor () -> Void

    func makeNSView(context: Context) -> BrowserKeyboardShortcutMonitorNSView {
        let nsView = BrowserKeyboardShortcutMonitorNSView()
        nsView.beginNewTab = beginNewTab
        return nsView
    }

    func updateNSView(_ nsView: BrowserKeyboardShortcutMonitorNSView, context: Context) {
        nsView.beginNewTab = beginNewTab
        nsView.installEventMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: BrowserKeyboardShortcutMonitorNSView, coordinator: ()) {
        nsView.removeEventMonitor()
    }
}

private final class BrowserKeyboardShortcutMonitorNSView: NSView {
    var beginNewTab: (@MainActor () -> Void)?
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

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  event.isCommandT else {
                return event
            }

            Task { @MainActor in
                self.beginNewTab?()
            }
            return nil
        }
    }

    func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

private struct CommandBarDismissalBackdrop: View {
    let dismiss: @MainActor () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                dismiss()
            }
            .background(CommandBarEscapeKeyMonitor(dismiss: dismiss))
            .accessibilityHidden(true)
    }
}

private struct CommandBarEscapeKeyMonitor: NSViewRepresentable {
    let dismiss: @MainActor () -> Void

    func makeNSView(context: Context) -> CommandBarEscapeKeyMonitorNSView {
        let nsView = CommandBarEscapeKeyMonitorNSView()
        nsView.dismiss = dismiss
        return nsView
    }

    func updateNSView(_ nsView: CommandBarEscapeKeyMonitorNSView, context: Context) {
        nsView.dismiss = dismiss
        nsView.installEventMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: CommandBarEscapeKeyMonitorNSView, coordinator: ()) {
        nsView.removeEventMonitor()
    }
}

private final class CommandBarEscapeKeyMonitorNSView: NSView {
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

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  event.isEscapeKey else {
                return event
            }

            Task { @MainActor in
                self.dismiss?()
            }
            return nil
        }
    }

    func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

private extension NSEvent {
    var isCommandT: Bool {
        charactersIgnoringModifiers?.lowercased() == "t"
            && modifierFlags.contains(.command)
            && !modifierFlags.contains(.shift)
            && !modifierFlags.contains(.option)
            && !modifierFlags.contains(.control)
    }

    var isEscapeKey: Bool {
        keyCode == 53 || charactersIgnoringModifiers == "\u{1B}"
    }
}

private struct WindowChromeController: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.applyMeridianChrome()
        }
    }
}

private extension NSWindow {
    func applyMeridianChrome() {
        title = "Meridian Browser"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        hasShadow = true
        collectionBehavior.insert(.fullScreenPrimary)

        setStandardWindowButtonsHidden(true)
        removeMeridianContentCornerOverrides()
        invalidateShadow()
    }

    func setStandardWindowButtonsHidden(_ isHidden: Bool) {
        standardWindowButton(.closeButton)?.isHidden = isHidden
        standardWindowButton(.miniaturizeButton)?.isHidden = isHidden
        standardWindowButton(.zoomButton)?.isHidden = isHidden
    }

    func removeMeridianContentCornerOverrides() {
        guard let contentView else {
            return
        }

        [contentView.superview, contentView].compactMap(\.self).forEach { view in
            view.layer?.cornerRadius = 0
            view.layer?.borderWidth = 0
            view.layer?.masksToBounds = false
        }
    }
}
