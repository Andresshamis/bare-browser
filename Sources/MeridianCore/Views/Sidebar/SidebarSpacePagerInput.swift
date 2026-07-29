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
    let selectedPageIsLast: Bool
    let performanceTrackingIsActive: Bool
    let geometryTracker: SidebarSpacePagerGeometryTracker
    let creationPullController: SidebarSpaceCreationPullController
    let creationCommitCoordinator: SidebarSpaceCreationCommitCoordinator
    let createSpace: () -> SidebarSpacePagerPageID

    func makeNSView(context: Context) -> SidebarSpacePagerScrollInputScalingView {
        let view = SidebarSpacePagerScrollInputScalingView()
        view.geometryTracker = geometryTracker
        view.creationPullController = creationPullController
        view.creationCommitCoordinator = creationCommitCoordinator
        view.createSpace = createSpace
        view.sensitivity = sensitivity
        view.pageWidth = pageWidth
        view.pageCount = pageCount
        view.creationIsAvailable = creationIsAvailable
        view.selectedPageIsLast = selectedPageIsLast
        view.performanceTrackingIsActive = performanceTrackingIsActive
        return view
    }

    func updateNSView(_ nsView: SidebarSpacePagerScrollInputScalingView, context: Context) {
        nsView.geometryTracker = geometryTracker
        nsView.creationPullController = creationPullController
        nsView.creationCommitCoordinator = creationCommitCoordinator
        nsView.createSpace = createSpace
        nsView.sensitivity = sensitivity
        nsView.pageWidth = pageWidth
        nsView.pageCount = pageCount
        nsView.creationIsAvailable = creationIsAvailable
        nsView.selectedPageIsLast = selectedPageIsLast
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


final class SidebarSpacePagerScrollInputScalingView: NSView {
    weak var geometryTracker: SidebarSpacePagerGeometryTracker?
    weak var creationPullController: SidebarSpaceCreationPullController?
    weak var creationCommitCoordinator: SidebarSpaceCreationCommitCoordinator?
    var createSpace: (() -> SidebarSpacePagerPageID)?
    var sensitivity: CGFloat = 1
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
    var selectedPageIsLast = false
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
#if DEBUG
    private var performanceDisplayLink: CADisplayLink?
    private var lastPerformanceTimestamp: CFTimeInterval?
    private var performanceFrameIntervals: [CFTimeInterval] = []
#endif

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
        installEventMonitorIfNeeded()
    }

    func tearDown() {
#if DEBUG
        stopPerformanceDisplayLink()
#endif
        clearConfiguredScrollView()
        removeEventMonitor()
        resetLocalGestureState()
        deferredInstallationIsScheduled = false
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
        configuredScrollView = nil
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
                lastPageIndex: lastPageIndex,
                visibleFractionalPageIndex:
                    geometryTracker?.visibleFractionalPageIndex,
                selectedPageIsLast: selectedPageIsLast
            )
        } else {
            canPullPastLastPage = false
        }
#if DEBUG
        os_signpost(
            .event,
            log: sidebarPagerPerformanceLog,
            name: "Sidebar Creation Eligibility",
            "eligible=%{public}d idle=%{public}d anchored=%{public}d visible=%{public}.3f offset_error=%{public}.3f",
            canPullPastLastPage ? 1 : 0,
            gestureOrigin?.scrollWasIdle == true ? 1 : 0,
            gestureOrigin?.anchoredPageIndex ?? -1,
            Double(geometryTracker?.visibleFractionalPageIndex ?? -.infinity),
            Double(
                abs((currentOffsetX ?? -.infinity) - (lastPageOffsetX ?? .infinity))
            )
        )
#endif
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
#if DEBUG
            let outcomeCode: Int
            switch outcome {
            case .none:
                outcomeCode = 0
            case .cancel:
                outcomeCode = 1
            case .create:
                outcomeCode = 2
            }
            os_signpost(
                .event,
                log: sidebarPagerPerformanceLog,
                name: "Sidebar Creation Release",
                "outcome=%{public}d cancelled=%{public}d",
                outcomeCode,
                cancelled ? 1 : 0
            )
#endif
            suppressesCreationMomentum = true
            switch outcome {
            case .none:
                creationPullController?.returnToRest(animated: false)
            case .cancel:
                creationPullController?.returnToRest(animated: true)
            case .create:
                let createSpace = createSpace
                let creationPullController = creationPullController
                let creationCommitCoordinator = creationCommitCoordinator
                creationCommitCoordinator?.beginCreation()
                DispatchQueue.main.async {
                    [weak creationPullController, weak creationCommitCoordinator] in
                    guard let createSpace else {
                        creationCommitCoordinator?.cancelCreation()
                        creationPullController?.returnToRest(animated: true)
                        return
                    }
                    let createdPageID = createSpace()
                    creationCommitCoordinator?.completeCreation(
                        with: createdPageID
                    )
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
