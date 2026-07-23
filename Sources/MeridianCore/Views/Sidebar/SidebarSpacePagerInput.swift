import AppKit
import SwiftUI

struct SidebarSpacePagerScrollInputScalingInstaller: NSViewRepresentable {
    let sensitivity: CGFloat
    let pageWidth: CGFloat
    let pageCount: Int
    let creationIsAvailable: Bool
    let geometryTracker: SidebarSpacePagerGeometryTracker
    let creationPullController: SidebarSpaceCreationPullController
    let createSpace: () -> Void

    func makeNSView(context: Context) -> SidebarSpacePagerScrollInputScalingView {
        let view = SidebarSpacePagerScrollInputScalingView()
        view.geometryTracker = geometryTracker
        view.creationPullController = creationPullController
        view.createSpace = createSpace
        view.sensitivity = sensitivity
        view.pageWidth = pageWidth
        view.pageCount = pageCount
        view.creationIsAvailable = creationIsAvailable
        return view
    }

    func updateNSView(_ nsView: SidebarSpacePagerScrollInputScalingView, context: Context) {
        nsView.geometryTracker = geometryTracker
        nsView.creationPullController = creationPullController
        nsView.createSpace = createSpace
        nsView.sensitivity = sensitivity
        nsView.pageWidth = pageWidth
        nsView.pageCount = pageCount
        nsView.creationIsAvailable = creationIsAvailable
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
    var createSpace: (() -> Void)?
    var sensitivity: CGFloat = 1
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
    private var inputScalingState = SidebarSpacePagerScrollInputScalingState()
    private var horizontalGestureAccumulator =
        SidebarSpacePagerHorizontalGestureAccumulator()
    private var creationSession = SidebarSpaceCreationGestureSession()
    private var suppressesCreationMomentum = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installIfNeeded()
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
            beginGestureIfInsidePager(event, scrollView: scrollView)
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

        if !gestureLifecycle.isActive {
            guard phase.contains(.changed),
                  eventIsInsidePager(event, scrollView: scrollView) else {
                return event
            }

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

    private func beginGestureIfInsidePager(_ event: NSEvent, scrollView: NSScrollView) {
        guard eventIsInsidePager(event, scrollView: scrollView) else {
            resetLocalGestureState()
            return
        }

        if !gestureLifecycle.isActive {
            beginGesture()
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
        inputScalingState.reset()
        horizontalGestureAccumulator.reset()
    }
}
