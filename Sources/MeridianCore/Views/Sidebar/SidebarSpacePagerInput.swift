import AppKit
#if DEBUG
import OSLog
#endif
import QuartzCore
import SwiftUI

struct SidebarSpacePagerScrollInputScalingInstaller: NSViewRepresentable {
    let sensitivity: CGFloat
    let pageWidth: CGFloat
    let pageCount: Int
    let creationIsAvailable: Bool
    let creationRailForegroundWhiteAmount: Double
    let performanceTrackingIsActive: Bool
    let geometryTracker: SidebarSpacePagerGeometryTracker
    let creationPullController: SidebarSpaceCreationPullController
    let createSpace: () -> Void

    func makeNSView(context: Context) -> SidebarSpacePagerScrollInputScalingView {
        let view = SidebarSpacePagerScrollInputScalingView()
        view.geometryTracker = geometryTracker
        view.attachCreationPullController(creationPullController)
        view.createSpace = createSpace
        view.sensitivity = sensitivity
        view.pageWidth = pageWidth
        view.pageCount = pageCount
        view.creationIsAvailable = creationIsAvailable
        view.creationRailForegroundWhiteAmount = creationRailForegroundWhiteAmount
        view.performanceTrackingIsActive = performanceTrackingIsActive
        return view
    }

    func updateNSView(_ nsView: SidebarSpacePagerScrollInputScalingView, context: Context) {
        nsView.geometryTracker = geometryTracker
        nsView.attachCreationPullController(creationPullController)
        nsView.createSpace = createSpace
        nsView.sensitivity = sensitivity
        nsView.pageWidth = pageWidth
        nsView.pageCount = pageCount
        nsView.creationIsAvailable = creationIsAvailable
        nsView.creationRailForegroundWhiteAmount = creationRailForegroundWhiteAmount
        nsView.performanceTrackingIsActive = performanceTrackingIsActive
        nsView.installIfNeeded()
    }

    static func dismantleNSView(
        _ nsView: SidebarSpacePagerScrollInputScalingView,
        coordinator: ()
    ) {
        nsView.tearDown()
    }
}

enum SidebarSpacePagerPhysicalGestureEndReason: Equatable, Sendable {
    case physicalEnded
    case physicalCancelled
    case momentumBegan
    case unphasedInput
}

/// Tracks physical finger ownership with monotonically increasing identities so
/// a deferred completion from one gesture cannot terminate a newer gesture.
struct SidebarSpacePagerPhysicalGestureLifecycle: Equatable, Sendable {
    private(set) var activeGestureID: UInt64?
    private var nextGestureID: UInt64 = 0

    var isActive: Bool {
        activeGestureID != nil
    }

    mutating func begin() -> UInt64 {
        nextGestureID &+= 1
        activeGestureID = nextGestureID
        return nextGestureID
    }

    func shouldFinish(for reason: SidebarSpacePagerPhysicalGestureEndReason) -> Bool {
        isActive
    }

    @discardableResult
    mutating func finish(for reason: SidebarSpacePagerPhysicalGestureEndReason) -> UInt64? {
        guard shouldFinish(for: reason),
              let activeGestureID else {
            return nil
        }
        self.activeGestureID = nil
        return activeGestureID
    }

    @discardableResult
    mutating func reset() -> UInt64? {
        defer { activeGestureID = nil }
        return activeGestureID
    }
}


final class SidebarSpacePagerScrollInputScalingView:
    NSView,
    SidebarSpaceCreationPullRendering
{
    weak var geometryTracker: SidebarSpacePagerGeometryTracker?
    private weak var creationPullController: SidebarSpaceCreationPullController?
    var createSpace: (() -> Void)?
    var sensitivity: CGFloat = 1
    var creationRailForegroundWhiteAmount = 1.0 {
        didSet {
            creationRailForegroundWhiteAmount = min(
                max(
                    creationRailForegroundWhiteAmount.isFinite
                        ? creationRailForegroundWhiteAmount
                        : 0,
                    0
                ),
                1
            )
            applyCreationPullColors()
        }
    }
#if DEBUG
    var performanceTrackingIsActive = false {
        didSet {
            guard performanceTrackingIsActive != oldValue else {
                return
            }
            if performanceTrackingIsActive {
                startPerformanceDisplayLinkIfPossible()
            } else {
                stopPerformanceDisplayLink()
            }
        }
    }
#else
    var performanceTrackingIsActive = false
#endif
    var pageWidth: CGFloat = 0 {
        didSet {
            guard oldValue > 0,
                  abs(oldValue - pageWidth) > 0.5 else {
                return
            }

            ignoreRemainderOfPhysicalGesture()
        }
    }
    var pageCount = 0 {
        didSet {
            guard oldValue > 0,
                  oldValue != pageCount else {
                return
            }
            cancelCreationInteraction(animated: false)
        }
    }
    var creationIsAvailable = false {
        didSet {
            if !creationIsAvailable, !gestureLifecycle.isActive {
                cancelCreationInteraction(animated: false)
            }
        }
    }

    private weak var configuredScrollView: NSScrollView?
    private var eventMonitor: Any?
    private var deferredInstallationIsScheduled = false
    private var gestureLifecycle = SidebarSpacePagerPhysicalGestureLifecycle()
    private var gestureGate = SidebarSpacePagerPhysicalGestureGate()
    private var scrollAxisLock = SidebarSpacePagerScrollAxisLock()
    private var inputScalingState = SidebarSpacePagerScrollInputScalingState()
    private var horizontalGestureAccumulator =
        SidebarSpacePagerHorizontalGestureAccumulator()
    private var creationSession = SidebarSpaceCreationGestureSession()
    private var suppressesCreationMomentum = false
    private let creationRailLayer = CALayer()
    private let creationAffordanceLayer = CALayer()
    private let creationTrackLayer = CAShapeLayer()
    private let creationProgressLayer = CAShapeLayer()
    private let creationPlusHorizontalLayer = CAShapeLayer()
    private let creationPlusVerticalLayer = CAShapeLayer()
    private weak var creationDocumentView: NSView?
    private var renderedCreationPresentation = SidebarSpaceCreationPullPresentation()
#if DEBUG
    private var performanceDisplayLink: CADisplayLink?
    private var lastPerformanceTimestamp: CFTimeInterval?
    private var performanceFrameIntervals: [CFTimeInterval] = []
#endif

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureCreationPullLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCreationPullLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installIfNeeded()
#if DEBUG
        if performanceTrackingIsActive {
            startPerformanceDisplayLinkIfPossible()
        } else if window == nil {
            stopPerformanceDisplayLink()
        }
#endif
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        installIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            tearDown()
        }
    }

    override func layout() {
        super.layout()
        installIfNeeded()
        layoutCreationPullLayers()
    }

    deinit {
        MainActor.assumeIsolated {
            tearDown()
        }
    }

    func installIfNeeded() {
        guard window != nil else {
            return
        }

        let candidateScrollView = nearestScrollView
        if let configuredScrollView,
           configuredScrollView === candidateScrollView {
            installEventMonitorIfNeeded()
            return
        }

        let replacedConfiguredScrollView = configuredScrollView != nil
        clearConfiguredScrollView()
        if replacedConfiguredScrollView {
            ignoreRemainderOfPhysicalGesture()
        } else {
            resetLocalGestureState()
        }

        guard let candidateScrollView else {
            scheduleDeferredInstallation()
            return
        }

        configuredScrollView = candidateScrollView
        installCreationPullLayers(in: candidateScrollView)
        installEventMonitorIfNeeded()
    }

    func tearDown() {
#if DEBUG
        stopPerformanceDisplayLink()
#endif
        creationPullController?.detach(self)
        creationPullController = nil
        removeCreationPullLayers()
        clearConfiguredScrollView()
        removeEventMonitor()
        resetLocalGestureState()
        deferredInstallationIsScheduled = false
    }

    func attachCreationPullController(
        _ controller: SidebarSpaceCreationPullController
    ) {
        guard creationPullController !== controller else {
            return
        }
        creationPullController?.detach(self)
        creationPullController = controller
        controller.attach(self)
    }

    func setCreationPullPresentation(
        _ presentation: SidebarSpaceCreationPullPresentation,
        animated: Bool
    ) {
        let previousPresentation = renderedCreationPresentation
        renderedCreationPresentation = presentation
        applyCreationPullPresentation(presentation)
        if animated {
            animateCreationPullReturn(
                from: previousPresentation,
                to: presentation
            )
        }
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

    private func scheduleDeferredInstallation() {
        guard !deferredInstallationIsScheduled else {
            return
        }

        deferredInstallationIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.deferredInstallationIsScheduled = false
            self.installIfNeeded()
        }
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else {
            return
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else {
                return event
            }
            return self.eventForPagerInput(from: event)
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func clearConfiguredScrollView() {
        removeCreationPullLayers()
        configuredScrollView = nil
    }

    private func configureCreationPullLayers() {
        withoutImplicitLayerActions {
            creationRailLayer.masksToBounds = true

            creationAffordanceLayer.anchorPoint = CGPoint(x: 1, y: 0.5)
            creationRailLayer.addSublayer(creationAffordanceLayer)

            for ringLayer in [creationTrackLayer, creationProgressLayer] {
                ringLayer.fillColor = nil
                ringLayer.lineCap = .round
                creationAffordanceLayer.addSublayer(ringLayer)
            }
            creationTrackLayer.lineWidth = 2.2
            creationProgressLayer.lineWidth = 2.4
            creationProgressLayer.strokeStart = 0
            creationProgressLayer.strokeEnd = 0
            creationProgressLayer.transform = CATransform3DMakeRotation(
                -.pi / 2,
                0,
                0,
                1
            )

            for plusLayer in [
                creationPlusHorizontalLayer,
                creationPlusVerticalLayer
            ] {
                plusLayer.fillColor = nil
                plusLayer.lineWidth = 1.8
                plusLayer.lineCap = .round
                creationAffordanceLayer.addSublayer(plusLayer)
            }

            creationAffordanceLayer.opacity = 0
        }
        applyCreationPullColors()
    }

    private func installCreationPullLayers(in scrollView: NSScrollView) {
        scrollView.wantsLayer = true
        guard let scrollLayer = scrollView.layer else {
            return
        }

        if creationRailLayer.superlayer !== scrollLayer {
            creationRailLayer.removeFromSuperlayer()
            scrollLayer.addSublayer(creationRailLayer)
        }

        creationDocumentView = scrollView.documentView
        creationDocumentView?.wantsLayer = true
        layoutCreationPullLayers()
        applyCreationPullPresentation(renderedCreationPresentation)
    }

    private func removeCreationPullLayers() {
        withoutImplicitLayerActions {
            creationDocumentView?.layer?.sublayerTransform = CATransform3DIdentity
            creationRailLayer.removeFromSuperlayer()
        }
        creationDocumentView = nil
    }

    private func layoutCreationPullLayers() {
        guard let scrollView = configuredScrollView,
              creationRailLayer.superlayer != nil else {
            return
        }

        let maximumWidth = SidebarSpacePagerMetrics.creationRailMaximumWidth
        let diameter = SidebarSpacePagerMetrics.creationAffordanceDiameter
        let trailingPadding = SidebarSpacePagerMetrics.creationRailTrailingPadding
        let railFrame = CGRect(
            x: max(scrollView.bounds.maxX - maximumWidth, scrollView.bounds.minX),
            y: scrollView.bounds.minY,
            width: min(maximumWidth, scrollView.bounds.width),
            height: scrollView.bounds.height
        )
        let ringBounds = CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter))
        let ringPath = CGPath(
            ellipseIn: ringBounds.insetBy(dx: 1.5, dy: 1.5),
            transform: nil
        )
        let plusCenter = diameter / 2
        let plusHalfLength: CGFloat = 4.5
        let horizontalPath = CGMutablePath()
        horizontalPath.move(to: CGPoint(x: plusCenter - plusHalfLength, y: plusCenter))
        horizontalPath.addLine(to: CGPoint(x: plusCenter + plusHalfLength, y: plusCenter))
        let verticalPath = CGMutablePath()
        verticalPath.move(to: CGPoint(x: plusCenter, y: plusCenter - plusHalfLength))
        verticalPath.addLine(to: CGPoint(x: plusCenter, y: plusCenter + plusHalfLength))

        withoutImplicitLayerActions {
            creationRailLayer.frame = railFrame
            creationAffordanceLayer.bounds = ringBounds
            creationAffordanceLayer.position = CGPoint(
                x: railFrame.width - trailingPadding,
                y: railFrame.height / 2
            )
            for ringLayer in [creationTrackLayer, creationProgressLayer] {
                ringLayer.frame = ringBounds
                ringLayer.path = ringPath
            }
            creationPlusHorizontalLayer.frame = ringBounds
            creationPlusHorizontalLayer.path = horizontalPath
            creationPlusVerticalLayer.frame = ringBounds
            creationPlusVerticalLayer.path = verticalPath
            updateCreationPullContentsScale()
        }
    }

    private func applyCreationPullColors() {
        let foregroundColor = NSColor(
            calibratedWhite: creationRailForegroundWhiteAmount,
            alpha: 1
        )
        withoutImplicitLayerActions {
            creationTrackLayer.strokeColor = foregroundColor
                .withAlphaComponent(0.20)
                .cgColor
            let progressAlpha = renderedCreationPresentation.isArmed ? 1 : 0.84
            creationProgressLayer.strokeColor = foregroundColor
                .withAlphaComponent(progressAlpha)
                .cgColor
            let plusAlpha = renderedCreationPresentation.isArmed ? 1 : 0.78
            let plusColor = foregroundColor
                .withAlphaComponent(plusAlpha)
                .cgColor
            creationPlusHorizontalLayer.strokeColor = plusColor
            creationPlusVerticalLayer.strokeColor = plusColor
        }
    }

    private func applyCreationPullPresentation(
        _ presentation: SidebarSpaceCreationPullPresentation
    ) {
        let revealScale = SidebarSpaceCreationAffordanceLayout.revealScale(
            forDisplayedDistance: presentation.displayedDistance
        )
        withoutImplicitLayerActions {
            creationDocumentView?.layer?.sublayerTransform =
                CATransform3DMakeTranslation(
                    -presentation.displayedDistance,
                    0,
                    0
                )
            creationProgressLayer.strokeEnd = presentation.progress
            creationAffordanceLayer.opacity = Float(revealScale)
            creationAffordanceLayer.transform = CATransform3DMakeScale(
                revealScale,
                revealScale,
                1
            )
        }
        applyCreationPullColors()
    }

    private func animateCreationPullReturn(
        from source: SidebarSpaceCreationPullPresentation,
        to destination: SidebarSpaceCreationPullPresentation
    ) {
        let duration: CFTimeInterval = 0.24
        let timing = CAMediaTimingFunction(name: .easeOut)
        let sourceScale = SidebarSpaceCreationAffordanceLayout.revealScale(
            forDisplayedDistance: source.displayedDistance
        )
        let destinationScale = SidebarSpaceCreationAffordanceLayout.revealScale(
            forDisplayedDistance: destination.displayedDistance
        )

        addAnimation(
            to: creationDocumentView?.layer,
            keyPath: "sublayerTransform",
            from: CATransform3DMakeTranslation(-source.displayedDistance, 0, 0),
            to: CATransform3DMakeTranslation(-destination.displayedDistance, 0, 0),
            duration: duration,
            timing: timing
        )
        addAnimation(
            to: creationProgressLayer,
            keyPath: "strokeEnd",
            from: source.progress,
            to: destination.progress,
            duration: duration,
            timing: timing
        )
        addAnimation(
            to: creationAffordanceLayer,
            keyPath: "opacity",
            from: sourceScale,
            to: destinationScale,
            duration: duration,
            timing: timing
        )
        addAnimation(
            to: creationAffordanceLayer,
            keyPath: "transform",
            from: CATransform3DMakeScale(sourceScale, sourceScale, 1),
            to: CATransform3DMakeScale(destinationScale, destinationScale, 1),
            duration: duration,
            timing: timing
        )
    }

    private func addAnimation(
        to layer: CALayer?,
        keyPath: String,
        from source: Any,
        to destination: Any,
        duration: CFTimeInterval,
        timing: CAMediaTimingFunction
    ) {
        guard let layer else {
            return
        }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = source
        animation.toValue = destination
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "sidebarCreationPull.\(keyPath)")
    }

    private func updateCreationPullContentsScale() {
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        creationRailLayer.contentsScale = scale
        creationAffordanceLayer.contentsScale = scale
        for layer in [
            creationTrackLayer,
            creationProgressLayer,
            creationPlusHorizontalLayer,
            creationPlusVerticalLayer
        ] {
            layer.contentsScale = scale
        }
    }

    private func withoutImplicitLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

#if DEBUG
    private func startPerformanceDisplayLinkIfPossible() {
        guard performanceDisplayLink == nil,
              window != nil else {
            return
        }

        let displayLink = displayLink(
            target: self,
            selector: #selector(recordPerformanceDisplayFrame(_:))
        )
        performanceDisplayLink = displayLink
        lastPerformanceTimestamp = nil
        performanceFrameIntervals.removeAll(keepingCapacity: true)
        displayLink.add(to: .main, forMode: .common)
    }

    private func stopPerformanceDisplayLink() {
        performanceDisplayLink?.invalidate()
        performanceDisplayLink = nil
        lastPerformanceTimestamp = nil

        guard !performanceFrameIntervals.isEmpty else {
            return
        }
        let sortedIntervals = performanceFrameIntervals.sorted()
        let percentileIndex = min(
            Int(Double(sortedIntervals.count - 1) * 0.99),
            sortedIntervals.count - 1
        )
        let p99Milliseconds = sortedIntervals[percentileIndex] * 1_000
        let overBudgetCount = performanceFrameIntervals.filter {
            $0 > (1.0 / 120.0) * 1.10
        }.count
        os_signpost(
            .event,
            log: sidebarPagerPerformanceLog,
            name: "Sidebar Pager Frame Summary",
            "frames=%{public}d p99_ms=%{public}.3f over_8_33ms=%{public}d",
            performanceFrameIntervals.count,
            p99Milliseconds,
            overBudgetCount
        )
        performanceFrameIntervals.removeAll(keepingCapacity: true)
    }

    @objc
    private func recordPerformanceDisplayFrame(_ displayLink: CADisplayLink) {
        defer {
            lastPerformanceTimestamp = displayLink.timestamp
        }
        guard let lastPerformanceTimestamp else {
            return
        }

        let interval = displayLink.timestamp - lastPerformanceTimestamp
        guard interval.isFinite, interval > 0 else {
            return
        }
        performanceFrameIntervals.append(interval)
        os_signpost(
            .event,
            log: sidebarPagerPerformanceLog,
            name: "Sidebar Pager Display Frame",
            "interval_ms=%{public}.3f offered_ms=%{public}.3f",
            interval * 1_000,
            displayLink.duration * 1_000
        )
    }
#endif

    private func eventForPagerInput(from event: NSEvent) -> NSEvent? {
        guard let scrollView = configuredScrollView,
              event.window === scrollView.window else {
            return event
        }

        if !event.momentumPhase.isEmpty {
            if suppressesCreationMomentum {
                if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                    suppressesCreationMomentum = false
                }
                return nil
            }
            finishPhysicalGesture(cancelled: false, reason: .momentumBegan)
            return event
        }

        let phase = event.phase
        guard !phase.isEmpty else {
            finishPhysicalGesture(cancelled: false, reason: .unphasedInput)
            return event
        }
        guard event.hasPreciseScrollingDeltas else {
            finishPhysicalGesture(cancelled: true, reason: .physicalCancelled)
            return event
        }

        if phase.contains(.mayBegin) || phase.contains(.began) {
            prepareGestureIfInsidePager(event, scrollView: scrollView)
        }

        if phase.contains(.ended) || phase.contains(.cancelled) {
            let cancelled = phase.contains(.cancelled)
            finishPhysicalGesture(
                cancelled: cancelled,
                reason: cancelled ? .physicalCancelled : .physicalEnded
            )
            return event
        }

        guard !gestureGate.ignoresChangedEvents else {
            return event
        }

        guard phase.contains(.began) || phase.contains(.changed) else {
            return event
        }

        guard eventIsInsidePager(event, scrollView: scrollView) else {
            return event
        }

        switch scrollAxisLock.update(
            scrollingDeltaX: event.scrollingDeltaX,
            scrollingDeltaY: event.scrollingDeltaY,
            minimumDisplacement: SidebarSpacePagerMetrics.inputAxisLockMinimumDisplacement
        ) {
        case .undecided:
            return event
        case .vertical:
            // Preserve the boundary between the workspace pager and its nested
            // tab scrollboxes: vertical events stay byte-for-byte native and
            // never pay for a CGEvent copy or horizontal pager bookkeeping.
            ignoreRemainderOfPhysicalGesture()
            return event
        case .horizontal:
            break
        }

        if !gestureLifecycle.isActive {
            beginGesture()
        }

        guard gestureLifecycle.isActive,
              let horizontalInput = SidebarSpacePagerHorizontalInputSample(
                scrollingDeltaX: event.scrollingDeltaX
              ),
              let scaledEvent = inputScalingState.scaledEvent(
                from: event,
                sensitivity: sensitivity
              ) else {
            return event
        }

        horizontalGestureAccumulator.append(horizontalInput)
        geometryTracker?.adjustedGestureDisplacementX =
            horizontalGestureAccumulator.cumulativeAdjustedDisplacementX

        if creationSession.routesBoundaryInput {
            let wasCancelled = creationSession.isCancelled
            switch creationSession.routeAdjustedDelta(
                horizontalInput.adjustedDisplacementX,
                pageWidth: pageWidth
            ) {
            case .pending, .pagingBackward:
                return scaledEvent
            case .pulling(let update):
                geometryTracker?.setCreationPullLocksLastPage(true)
                creationPullController?.update(
                    displayedDistance: update.displayedDistance,
                    progress: update.progress
                )
                return nil
            case .cancelled:
                if !wasCancelled {
                    creationPullController?.returnToRest(animated: true)
                }
                // Once a creation pull reverses past its origin, this physical
                // gesture is cancelled and remains locked to the last page.
                return nil
            }
        }

        return scaledEvent
    }

    private func prepareGestureIfInsidePager(_ event: NSEvent, scrollView: NSScrollView) {
        guard eventIsInsidePager(event, scrollView: scrollView) else {
            resetLocalGestureState()
            return
        }

        if !gestureLifecycle.isActive {
            gestureGate.begin()
            scrollAxisLock.reset()
        }
    }

    private func beginGesture() {
        gestureGate.begin()
        let gestureID = gestureLifecycle.begin()
        inputScalingState.reset()
        horizontalGestureAccumulator.reset()
        suppressesCreationMomentum = false
        creationPullController?.returnToRest(animated: false)

        // Use the same logical origin as normal paging. If this gesture
        // interrupts an arrival animation, the previous resolved destination
        // is authoritative even though the clip view has not reached it yet.
        let gestureOrigin = geometryTracker?.beginPhysicalGesture(id: gestureID)
        let canPullPastLastPage: Bool
        let currentOffsetX = configuredScrollView?.contentView.bounds.origin.x
        if let gestureOrigin,
           let currentOffsetX,
           let lastPageOffsetX,
           let lastPageIndex {
            canPullPastLastPage = SidebarSpaceCreationPullEligibility.canBegin(
                creationIsAvailable: creationIsAvailable,
                gestureOrigin: gestureOrigin,
                currentOffsetX: currentOffsetX,
                lastPageOffsetX: lastPageOffsetX,
                lastPageIndex: lastPageIndex
            )
        } else {
            canPullPastLastPage = false
        }
        creationSession.begin(canPullForward: canPullPastLastPage)
    }

    private func eventIsInsidePager(_ event: NSEvent, scrollView: NSScrollView) -> Bool {
        let localPoint = scrollView.convert(event.locationInWindow, from: nil)
        return scrollView.bounds.contains(localPoint)
    }

    private func resetLocalGestureState() {
        cancelCreationInteraction(animated: false)
        suppressesCreationMomentum = false
        gestureGate.end()
        clearLocalGestureState()
    }

    private func finishPhysicalGesture(
        cancelled: Bool,
        reason: SidebarSpacePagerPhysicalGestureEndReason
    ) {
        guard let gestureID = gestureLifecycle.finish(for: reason) else {
            gestureGate.end()
            scrollAxisLock.reset()
            return
        }

        let consumedCreationInput = creationSession.isPulling || creationSession.isCancelled
        if consumedCreationInput {
            let outcome = creationSession.finishPull(cancelled: cancelled)
            suppressesCreationMomentum = true
            switch outcome {
            case .none:
                creationPullController?.returnToRest(animated: false)
            case .cancel:
                creationPullController?.returnToRest(animated: true)
            case .create:
                let createSpace = createSpace
                DispatchQueue.main.async { [weak creationPullController] in
                    createSpace?()
                    creationPullController?.returnToRest(animated: true)
                }
            }
        } else {
            creationSession.reset()
            creationPullController?.returnToRest(animated: false)
            geometryTracker?.setCreationPullLocksLastPage(false)
        }

        creationSession.end()
        gestureGate.end()
        scrollAxisLock.reset()
        inputScalingState.reset()
        horizontalGestureAccumulator.reset()

        let geometryTracker = geometryTracker
        DispatchQueue.main.async { [weak geometryTracker] in
            geometryTracker?.endPhysicalGesture(id: gestureID)
        }
    }

    private var lastPageOffsetX: CGFloat? {
        guard let lastPageIndex,
              pageWidth.isFinite,
              pageWidth > 0 else {
            return nil
        }
        return CGFloat(lastPageIndex) * pageWidth
    }

    private var lastPageIndex: Int? {
        pageCount > 0 ? pageCount - 1 : nil
    }

    private func cancelCreationInteraction(animated: Bool) {
        creationSession.reset()
        geometryTracker?.setCreationPullLocksLastPage(false)
        creationPullController?.returnToRest(animated: animated)
    }

    private func ignoreRemainderOfPhysicalGesture() {
        gestureGate.ignoreChangedEventsUntilNextGesture()
        cancelCreationInteraction(animated: false)
        clearLocalGestureState()
    }

    private func clearLocalGestureState() {
        _ = gestureLifecycle.reset()
        geometryTracker?.cancelDirectionalSnap()
        scrollAxisLock.reset()
        inputScalingState.reset()
        horizontalGestureAccumulator.reset()
    }
}
