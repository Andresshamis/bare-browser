import AppKit
import SwiftUI

enum SidebarSpacePagerMetrics {
    static let selectionAnimation: Animation = .smooth(duration: 0.18, extraBounce: 0)
    static let activeScrollSensitivity: CGFloat = 0.35
    static let directionalDistanceThresholdInPages: CGFloat = 0.0025
    static let directionalVelocityThreshold: CGFloat = 20
    static let creationDirectionInferenceDistance: CGFloat = 2
    static let creationSettledOffsetTolerance: CGFloat = 0.75
    static let creationPullThreshold: CGFloat = 160
    static let creationPullResistance: CGFloat = 0.55
    static let creationRailMaximumWidth: CGFloat = 72
    static let creationAffordanceDiameter: CGFloat = 32
    static let creationRailTrailingPadding: CGFloat = 12
    static let creationReturnAnimation: Animation = .smooth(duration: 0.24, extraBounce: 0.08)
}

enum SidebarSpacePagerHorizontalIntent: Equatable, Sendable {
    case backward
    case forward

    static func intent(
        forAdjustedDisplacement displacement: CGFloat,
        minimumDisplacement: CGFloat
    ) -> Self? {
        guard displacement.isFinite,
              minimumDisplacement.isFinite,
              abs(displacement) >= max(minimumDisplacement, 0),
              displacement != 0 else {
            return nil
        }
        return displacement > 0 ? .forward : .backward
    }
}

/// Converts AppKit wheel coordinates into the pager's content coordinates.
/// `NSScrollView` moves its horizontal content offset opposite to
/// `NSEvent.scrollingDeltaX`, so this conversion is the only place where that
/// sign inversion belongs.
struct SidebarSpacePagerHorizontalInputSample: Equatable, Sendable {
    let adjustedDisplacementX: CGFloat

    init?(scrollingDeltaX: CGFloat) {
        guard scrollingDeltaX.isFinite else {
            return nil
        }
        adjustedDisplacementX = -scrollingDeltaX
    }
}

struct SidebarSpacePagerHorizontalGestureAccumulator: Equatable, Sendable {
    private(set) var cumulativeAdjustedDisplacementX: CGFloat = 0

    mutating func append(_ sample: SidebarSpacePagerHorizontalInputSample) {
        cumulativeAdjustedDisplacementX += sample.adjustedDisplacementX
    }

    mutating func reset() {
        cumulativeAdjustedDisplacementX = 0
    }
}

struct SidebarSpacePagerPhysicalGestureOrigin: Equatable, Sendable {
    let scrollWasIdle: Bool
    let anchoredPageIndex: Int?
}

/// Non-observable gesture geometry shared by SwiftUI's phase callbacks and the
/// scroll-target policy. Live samples never invalidate the pager view tree.
final class SidebarSpacePagerGeometryTracker {
    var visibleFractionalPageIndex: CGFloat?
    var gestureStartFractionalPageIndex: CGFloat?
    var gestureSourcePageIndex: Int?
    var adjustedGestureDisplacementX: CGFloat?
    var acceptsDirectionalSnap = false
    private(set) var resolvedTargetPageIndex: Int?
    private(set) var creationPullLocksLastPage = false
    private(set) var activePhysicalGestureID: UInt64?
    private var scrollPhase = ScrollPhase.idle

    var scrollIsIdle: Bool {
        scrollPhase == .idle && activePhysicalGestureID == nil
    }

    func transition(from oldPhase: ScrollPhase, to newPhase: ScrollPhase) {
        scrollPhase = newPhase
        switch newPhase {
        case .tracking:
            if activePhysicalGestureID == nil {
                beginDirectionalSnap(
                    sourcePageIndex: interruptedTargetPageIndex(after: oldPhase)
                )
            } else {
                acceptsDirectionalSnap = true
            }
        case .interacting:
            if activePhysicalGestureID != nil {
                acceptsDirectionalSnap = true
            } else if oldPhase != .tracking {
                beginDirectionalSnap(
                    sourcePageIndex: interruptedTargetPageIndex(after: oldPhase)
                )
            } else {
                acceptsDirectionalSnap = true
            }
        case .decelerating:
            acceptsDirectionalSnap = true
        case .animating:
            // Preserve the captured gesture origin through SwiftUI's alignment
            // animation. Programmatic animations opt out of the active snap but
            // retain their destination so a physical interruption can anchor to it.
            if oldPhase == .idle, activePhysicalGestureID == nil {
                resetDirectionalSnap(preservingResolvedTarget: true)
            }
        case .idle:
            if activePhysicalGestureID == nil {
                resetDirectionalSnap()
            }
        }
    }

    func cancelDirectionalSnap() {
        activePhysicalGestureID = nil
        resetDirectionalSnap()
    }

    @discardableResult
    func beginPhysicalGesture(id: UInt64) -> SidebarSpacePagerPhysicalGestureOrigin {
        let origin = SidebarSpacePagerPhysicalGestureOrigin(
            scrollWasIdle: scrollIsIdle,
            anchoredPageIndex: resolvedTargetPageIndex
        )
        activePhysicalGestureID = id
        creationPullLocksLastPage = false
        beginDirectionalSnap(sourcePageIndex: resolvedTargetPageIndex)
        return origin
    }

    func endPhysicalGesture(id: UInt64) {
        guard activePhysicalGestureID == id else {
            return
        }

        activePhysicalGestureID = nil
        if scrollPhase == .idle {
            resetDirectionalSnap()
        }
    }

    func setCreationPullLocksLastPage(_ isLocked: Bool) {
        creationPullLocksLastPage = isLocked
    }

    func clearAdjustedGestureDisplacement() {
        adjustedGestureDisplacementX = nil
    }

    func recordResolvedTargetPageIndex(_ pageIndex: Int) {
        resolvedTargetPageIndex = pageIndex
    }

    func prepareForProgrammaticNavigation(to pageIndex: Int) {
        activePhysicalGestureID = nil
        resetDirectionalSnap()
        resolvedTargetPageIndex = pageIndex
    }

    private func resetDirectionalSnap(preservingResolvedTarget: Bool = false) {
        acceptsDirectionalSnap = false
        gestureStartFractionalPageIndex = nil
        gestureSourcePageIndex = nil
        adjustedGestureDisplacementX = nil
        if !preservingResolvedTarget {
            resolvedTargetPageIndex = nil
        }
        creationPullLocksLastPage = false
    }

    private func interruptedTargetPageIndex(after phase: ScrollPhase) -> Int? {
        switch phase {
        case .animating, .decelerating:
            return resolvedTargetPageIndex
        case .idle, .tracking, .interacting:
            return nil
        }
    }

    private func beginDirectionalSnap(sourcePageIndex: Int?) {
        gestureStartFractionalPageIndex = visibleFractionalPageIndex
        gestureSourcePageIndex = sourcePageIndex
        adjustedGestureDisplacementX = nil
        acceptsDirectionalSnap = true
    }
}

/// Rewrites only the active horizontal displacement fields. Gesture direction
/// accumulation is deliberately owned by `SidebarSpacePagerHorizontalGestureAccumulator`.
struct SidebarSpacePagerScrollInputScalingState {
    private var pointDeltaResidualX = 0.0

    mutating func scaledEvent(
        from event: NSEvent,
        sensitivity: CGFloat
    ) -> NSEvent? {
        guard event.type == .scrollWheel,
              let copiedCGEvent = event.cgEvent?.copy() else {
            return nil
        }

        let normalizedSensitivity = Self.normalizedSensitivity(sensitivity)
        let originalFixedPointDeltaX = copiedCGEvent.getDoubleValueField(
            .scrollWheelEventFixedPtDeltaAxis2
        )
        let originalPointDeltaX = copiedCGEvent.getIntegerValueField(
            .scrollWheelEventPointDeltaAxis2
        )
        if originalFixedPointDeltaX.isFinite {
            copiedCGEvent.setDoubleValueField(
                .scrollWheelEventFixedPtDeltaAxis2,
                value: originalFixedPointDeltaX * normalizedSensitivity
            )
        }
        copiedCGEvent.setIntegerValueField(
            .scrollWheelEventPointDeltaAxis2,
            value: Self.scaledIntegralDelta(
                originalPointDeltaX,
                sensitivity: normalizedSensitivity,
                residual: &pointDeltaResidualX
            )
        )

        return NSEvent(cgEvent: copiedCGEvent)
    }

    mutating func reset() {
        pointDeltaResidualX = 0
    }

    static func normalizedSensitivity(_ sensitivity: CGFloat) -> Double {
        guard sensitivity.isFinite else {
            return 1
        }

        return Double(min(max(sensitivity, 0), 1))
    }

    private static func scaledIntegralDelta(
        _ delta: Int64,
        sensitivity: Double,
        residual: inout Double
    ) -> Int64 {
        let exactValue = Double(delta) * sensitivity + residual
        guard exactValue.isFinite,
              exactValue > Double(Int64.min),
              exactValue < Double(Int64.max) else {
            residual = 0
            return delta
        }

        let scaledValue = Int64(exactValue.rounded(.toNearestOrAwayFromZero))
        residual = exactValue - Double(scaledValue)
        return scaledValue
    }
}

struct SidebarSpacePagerPhysicalGestureGate {
    private(set) var ignoresChangedEvents = false

    mutating func begin() {
        ignoresChangedEvents = false
    }

    mutating func ignoreChangedEventsUntilNextGesture() {
        ignoresChangedEvents = true
    }

    mutating func end() {
        ignoresChangedEvents = false
    }
}

struct SidebarSpacePagerFixedChromeTarget {
    static func pageID(
        visibleFractionalPageIndex: CGFloat,
        gestureStartFractionalPageIndex: CGFloat?,
        gestureSourcePageIndex: Int? = nil,
        adjustedGestureDisplacementX: CGFloat?,
        pageWidth: CGFloat,
        pages: [SidebarSpacePagerPageSnapshot]
    ) -> SidebarSpacePagerPageID? {
        guard !pages.isEmpty,
              visibleFractionalPageIndex.isFinite,
              pageWidth.isFinite,
              pageWidth > 0 else {
            return nil
        }

        let gestureOrigin: CGFloat
        if let gestureStartFractionalPageIndex,
           gestureStartFractionalPageIndex.isFinite {
            gestureOrigin = gestureStartFractionalPageIndex
        } else {
            gestureOrigin = visibleFractionalPageIndex.rounded()
        }

        let pageIndex = SidebarSpacePagerSnap.targetPageIndex(
            originalOffsetX: gestureOrigin * pageWidth,
            proposedOffsetX: visibleFractionalPageIndex * pageWidth,
            gestureStartFractionalPageIndex: gestureOrigin,
            gestureSourcePageIndex: gestureSourcePageIndex,
            visibleFractionalPageIndex: visibleFractionalPageIndex,
            adjustedGestureDisplacementX: adjustedGestureDisplacementX,
            velocityX: 0,
            pageWidth: pageWidth,
            pageCount: pages.count
        )
        return pages[pageIndex].id
    }
}

struct SidebarSpacePagerChrome {
    static func shouldDeferSettledStyle(
        from currentPageID: SidebarSpacePagerPageID?,
        to targetPageID: SidebarSpacePagerPageID?
    ) -> Bool {
        guard let targetPageID else {
            return false
        }
        return currentPageID != targetPageID
    }

    static func theme(
        for pageID: SidebarSpacePagerPageID?,
        in pages: [SidebarSpacePagerPageSnapshot]
    ) -> SidebarChromeTheme? {
        guard let pageID else {
            return nil
        }
        return pages.first(where: { $0.id == pageID })?.chromeTheme
    }

    static func color(
        for pageID: SidebarSpacePagerPageID?,
        in pages: [SidebarSpacePagerPageSnapshot]
    ) -> SidebarChromeColor? {
        theme(for: pageID, in: pages).map(SidebarChromeColor.init(theme:))
    }

    static func liveStyle(
        for pageID: SidebarSpacePagerPageID?,
        in pages: [SidebarSpacePagerPageSnapshot]
    ) -> SidebarChromeLiveStyle? {
        theme(for: pageID, in: pages).map(SidebarChromeLiveStyle.init(theme:))
    }

    static func liveColor(
        at fractionalPageIndex: CGFloat,
        in pages: [SidebarSpacePagerPageSnapshot]
    ) -> SidebarChromeColor? {
        liveColor(at: fractionalPageIndex, themes: pages.map(\.chromeTheme))
    }

    static func liveColor(
        at fractionalPageIndex: CGFloat,
        themes: [SidebarChromeTheme]
    ) -> SidebarChromeColor? {
        SidebarChromeColor.interpolated(
            themes: themes,
            fractionalIndex: Double(fractionalPageIndex)
        )
    }

    static func liveStyle(
        at fractionalPageIndex: CGFloat,
        themes: [SidebarChromeTheme]
    ) -> SidebarChromeLiveStyle? {
        SidebarChromeLiveStyle.interpolated(
            themes: themes,
            fractionalIndex: Double(fractionalPageIndex)
        )
    }

    static func liveStyle(
        at fractionalPageIndex: CGFloat,
        styles: [SidebarChromeLiveStyle]
    ) -> SidebarChromeLiveStyle? {
        SidebarChromeLiveStyle.interpolated(
            styles: styles,
            fractionalIndex: Double(fractionalPageIndex)
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

struct SidebarSpacePagerPreview {
    static func spaceID(
        for targetPageID: SidebarSpacePagerPageID,
        selectedPageID: SidebarSpacePagerPageID?
    ) -> SpaceID? {
        guard targetPageID != selectedPageID,
              case .space(let spaceID) = targetPageID else {
            return nil
        }
        return spaceID
    }
}

struct SidebarAdjacentPageScrollTargetBehavior: ScrollTargetBehavior {
    let pageCount: Int
    let geometryTracker: SidebarSpacePagerGeometryTracker

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard context.axes.contains(.horizontal),
              pageCount > 0 else {
            return
        }

        let pageWidth = context.containerSize.width
        guard pageWidth.isFinite,
              pageWidth > 0 else {
            return
        }

        let targetPageIndex: Int
        if geometryTracker.creationPullLocksLastPage {
            targetPageIndex = pageCount - 1
        } else if geometryTracker.acceptsDirectionalSnap {
            targetPageIndex = SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: context.originalTarget.rect.minX,
                proposedOffsetX: target.rect.minX,
                gestureStartFractionalPageIndex: geometryTracker.gestureStartFractionalPageIndex,
                gestureSourcePageIndex: geometryTracker.gestureSourcePageIndex,
                visibleFractionalPageIndex: geometryTracker.visibleFractionalPageIndex,
                adjustedGestureDisplacementX: geometryTracker.adjustedGestureDisplacementX,
                velocityX: context.velocity.dx,
                pageWidth: pageWidth,
                pageCount: pageCount
            )
        } else {
            targetPageIndex = SidebarSpacePagerSnap.nearestPageIndex(
                offsetX: target.rect.minX,
                pageWidth: pageWidth,
                pageCount: pageCount
            )
        }

        geometryTracker.recordResolvedTargetPageIndex(targetPageIndex)
        target.rect.origin.x = CGFloat(targetPageIndex) * pageWidth
        target.anchor = .topLeading
    }
}

struct SidebarSpacePagerSnap {
    static func targetPageIndex(
        originalOffsetX: CGFloat,
        proposedOffsetX: CGFloat,
        gestureStartFractionalPageIndex: CGFloat? = nil,
        gestureSourcePageIndex: Int? = nil,
        visibleFractionalPageIndex: CGFloat?,
        adjustedGestureDisplacementX: CGFloat? = nil,
        velocityX: CGFloat,
        pageWidth: CGFloat,
        pageCount: Int
    ) -> Int {
        guard pageCount > 0,
              pageWidth.isFinite,
              pageWidth > 0 else {
            return 0
        }

        let originalPagePosition = finiteOffset(originalOffsetX) / pageWidth
        let gestureStartPagePosition = finiteValue(gestureStartFractionalPageIndex)
            ?? originalPagePosition
        let currentPageIndex = clampedPageIndex(
            gestureSourcePageIndex ?? Int(gestureStartPagePosition.rounded()),
            pageCount: pageCount
        )
        let proposedDirection: Int?
        if originalOffsetX.isFinite, proposedOffsetX.isFinite {
            let proposedPagePosition = proposedOffsetX / pageWidth
            proposedDirection = pageDirection(from: proposedPagePosition - gestureStartPagePosition)
        } else {
            proposedDirection = nil
        }

        let visibleDirection: Int?
        if let visibleFractionalPageIndex,
           visibleFractionalPageIndex.isFinite {
            visibleDirection = pageDirection(
                from: visibleFractionalPageIndex - gestureStartPagePosition
            )
        } else {
            visibleDirection = nil
        }

        let adjustedGestureDirection: Int?
        if let adjustedGestureDisplacementX,
           adjustedGestureDisplacementX.isFinite {
            adjustedGestureDirection = pageDirection(
                from: adjustedGestureDisplacementX / pageWidth
            )
        } else {
            adjustedGestureDirection = nil
        }

        let pageStep = proposedDirection
            ?? velocityDirection(from: velocityX)
            ?? adjustedGestureDirection
            ?? visibleDirection
            ?? 0
        return clampedPageIndex(currentPageIndex + pageStep, pageCount: pageCount)
    }

    static func nearestPageIndex(
        offsetX: CGFloat,
        pageWidth: CGFloat,
        pageCount: Int
    ) -> Int {
        guard pageCount > 0,
              pageWidth.isFinite,
              pageWidth > 0 else {
            return 0
        }

        return clampedPageIndex(
            Int((finiteOffset(offsetX) / pageWidth).rounded()),
            pageCount: pageCount
        )
    }

    private static func finiteOffset(_ offset: CGFloat) -> CGFloat {
        offset.isFinite ? offset : 0
    }

    private static func finiteValue(_ value: CGFloat?) -> CGFloat? {
        guard let value,
              value.isFinite else {
            return nil
        }
        return value
    }

    private static func pageDirection(from delta: CGFloat) -> Int? {
        guard let intent = SidebarSpacePagerHorizontalIntent.intent(
            forAdjustedDisplacement: delta,
            minimumDisplacement: SidebarSpacePagerMetrics.directionalDistanceThresholdInPages
        ) else {
            return nil
        }
        return intent == .forward ? 1 : -1
    }

    private static func velocityDirection(from velocityX: CGFloat) -> Int? {
        guard velocityX.isFinite,
              abs(velocityX) >= SidebarSpacePagerMetrics.directionalVelocityThreshold else {
            return nil
        }
        return velocityX > 0 ? 1 : -1
    }

    private static func clampedPageIndex(_ pageIndex: Int, pageCount: Int) -> Int {
        min(max(pageIndex, 0), pageCount - 1)
    }
}
