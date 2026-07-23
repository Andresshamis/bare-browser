import SwiftUI

struct SidebarSpaceCreationPullEligibility {
    static func canBegin(
        creationIsAvailable: Bool,
        gestureOrigin: SidebarSpacePagerPhysicalGestureOrigin,
        currentOffsetX: CGFloat,
        lastPageOffsetX: CGFloat,
        lastPageIndex: Int
    ) -> Bool {
        guard creationIsAvailable,
              currentOffsetX.isFinite,
              lastPageOffsetX.isFinite,
              lastPageIndex >= 0 else {
            return false
        }

        if gestureOrigin.anchoredPageIndex == lastPageIndex {
            return true
        }

        return gestureOrigin.scrollWasIdle
            && abs(currentOffsetX - lastPageOffsetX)
                <= SidebarSpacePagerMetrics.creationSettledOffsetTolerance
    }
}

enum SidebarSpaceCreationPullDisposition: Equatable, Sendable {
    case pulling
    case cancelled
}

struct SidebarSpaceCreationPullUpdate: Equatable, Sendable {
    let disposition: SidebarSpaceCreationPullDisposition
    let displayedDistance: CGFloat
    let progress: CGFloat
}

enum SidebarSpaceCreationPullReleaseOutcome: Equatable, Sendable {
    case none
    case cancel
    case create
}

struct SidebarSpaceCreationPullState: Equatable, Sendable {
    private(set) var unresistedDistance: CGFloat = 0
    private(set) var displayedDistance: CGFloat = 0
    private(set) var progress: CGFloat = 0
    private var isActive = false

    mutating func begin(
        initialForwardDistance: CGFloat,
        pageWidth: CGFloat
    ) -> SidebarSpaceCreationPullUpdate? {
        guard initialForwardDistance.isFinite,
              initialForwardDistance > 0 else {
            return nil
        }

        isActive = true
        unresistedDistance = 0
        return applyForwardDistance(initialForwardDistance, pageWidth: pageWidth)
    }

    mutating func consumeAdjustedDelta(
        _ adjustedDeltaX: CGFloat,
        pageWidth: CGFloat
    ) -> SidebarSpaceCreationPullUpdate? {
        guard isActive,
              adjustedDeltaX.isFinite else {
            return nil
        }

        let proposedDistance = unresistedDistance + adjustedDeltaX
        guard proposedDistance > 0 else {
            cancel()
            return SidebarSpaceCreationPullUpdate(
                disposition: .cancelled,
                displayedDistance: 0,
                progress: 0
            )
        }

        return applyForwardDistance(proposedDistance, pageWidth: pageWidth)
    }

    mutating func release() -> SidebarSpaceCreationPullReleaseOutcome {
        guard isActive else {
            return .none
        }

        isActive = false
        return progress >= 1 ? .create : .cancel
    }

    mutating func cancel() {
        isActive = false
        unresistedDistance = 0
        displayedDistance = 0
        progress = 0
    }

    static func resistedDistance(for distance: CGFloat, pageWidth: CGFloat) -> CGFloat {
        guard distance.isFinite,
              distance > 0,
              pageWidth.isFinite,
              pageWidth > 0 else {
            return 0
        }

        let coefficient = SidebarSpacePagerMetrics.creationPullResistance
        let resistedDistance = (distance * pageWidth * coefficient)
            / (pageWidth + coefficient * distance)
        return min(resistedDistance, SidebarSpacePagerMetrics.creationRailMaximumWidth)
    }

    private mutating func applyForwardDistance(
        _ distance: CGFloat,
        pageWidth: CGFloat
    ) -> SidebarSpaceCreationPullUpdate {
        unresistedDistance = distance
        displayedDistance = Self.resistedDistance(for: distance, pageWidth: pageWidth)
        progress = min(
            max(distance / SidebarSpacePagerMetrics.creationPullThreshold, 0),
            1
        )
        return SidebarSpaceCreationPullUpdate(
            disposition: .pulling,
            displayedDistance: displayedDistance,
            progress: progress
        )
    }
}

enum SidebarSpaceCreationGestureMode: Equatable, Sendable {
    case disabled
    case pendingDirection
    case pulling
    case pagingBackward
    case cancelled
}

enum SidebarSpaceCreationGestureRouting: Equatable, Sendable {
    case pending
    case pagingBackward
    case pulling(SidebarSpaceCreationPullUpdate)
    case cancelled
}

/// Owns only the pull-past-the-last-space state machine. AppKit event routing,
/// pager snapping, and SwiftUI presentation side effects remain outside it.
struct SidebarSpaceCreationGestureSession: Equatable, Sendable {
    private(set) var mode = SidebarSpaceCreationGestureMode.disabled
    private(set) var pullState = SidebarSpaceCreationPullState()
    private var pendingAdjustedDisplacementX: CGFloat = 0

    var isPendingDirection: Bool { mode == .pendingDirection }
    var isPulling: Bool { mode == .pulling }
    var isCancelled: Bool { mode == .cancelled }
    var routesBoundaryInput: Bool { mode != .disabled }

    mutating func begin(canPullForward: Bool) {
        reset()
        guard canPullForward else {
            return
        }

        mode = .pendingDirection
    }

    mutating func routeAdjustedDelta(
        _ adjustedDeltaX: CGFloat,
        pageWidth: CGFloat,
        minimumDisplacement: CGFloat = SidebarSpacePagerMetrics.creationDirectionInferenceDistance
    ) -> SidebarSpaceCreationGestureRouting {
        switch mode {
        case .disabled:
            return .pagingBackward
        case .pagingBackward:
            return .pagingBackward
        case .cancelled:
            return .cancelled
        case .pulling:
            guard let update = pullState.consumeAdjustedDelta(
                adjustedDeltaX,
                pageWidth: pageWidth
            ) else {
                return .cancelled
            }
            if update.disposition == .cancelled {
                mode = .cancelled
                return .cancelled
            }
            return .pulling(update)
        case .pendingDirection:
            guard adjustedDeltaX.isFinite else {
                return .pending
            }
            pendingAdjustedDisplacementX += adjustedDeltaX
        }

        guard let intent = SidebarSpacePagerHorizontalIntent.intent(
            forAdjustedDisplacement: pendingAdjustedDisplacementX,
            minimumDisplacement: minimumDisplacement
        ) else {
            return .pending
        }

        switch intent {
        case .backward:
            mode = .pagingBackward
            clearPendingDirection()
            return .pagingBackward
        case .forward:
            guard let update = pullState.begin(
                initialForwardDistance: pendingAdjustedDisplacementX,
                pageWidth: pageWidth
            ) else {
                return .pending
            }

            mode = .pulling
            clearPendingDirection()
            return .pulling(update)
        }
    }

    mutating func finishPull(cancelled: Bool) -> SidebarSpaceCreationPullReleaseOutcome {
        switch mode {
        case .pulling:
            return cancelled ? cancelPull() : pullState.release()
        case .cancelled:
            pullState.cancel()
            return .cancel
        case .disabled, .pendingDirection, .pagingBackward:
            pullState.cancel()
            return .none
        }
    }

    mutating func end() {
        mode = .disabled
        clearPendingDirection()
    }

    mutating func reset() {
        mode = .disabled
        pullState.cancel()
        clearPendingDirection()
    }

    private mutating func cancelPull() -> SidebarSpaceCreationPullReleaseOutcome {
        pullState.cancel()
        return .cancel
    }

    private mutating func clearPendingDirection() {
        pendingAdjustedDisplacementX = 0
    }
}

struct SidebarSpaceCreationPullPresentation: Equatable, Sendable {
    var displayedDistance: CGFloat = 0
    var progress: CGFloat = 0

    var isArmed: Bool {
        progress >= 1
    }
}

struct SidebarSpaceCreationAffordanceLayout {
    static func revealScale(forDisplayedDistance displayedDistance: CGFloat) -> CGFloat {
        guard displayedDistance.isFinite else {
            return 0
        }

        let availableWidth = max(
            displayedDistance - SidebarSpacePagerMetrics.creationRailTrailingPadding,
            0
        )
        return min(
            availableWidth / SidebarSpacePagerMetrics.creationAffordanceDiameter,
            1
        )
    }
}

@MainActor
final class SidebarSpaceCreationPullController: ObservableObject {
    @Published private(set) var presentation = SidebarSpaceCreationPullPresentation()

    func update(displayedDistance: CGFloat, progress: CGFloat) {
        let presentation = SidebarSpaceCreationPullPresentation(
            displayedDistance: max(displayedDistance, 0),
            progress: min(max(progress, 0), 1)
        )
        guard self.presentation != presentation else {
            return
        }
        self.presentation = presentation
    }

    func returnToRest(animated: Bool) {
        let update = {
            self.presentation = SidebarSpaceCreationPullPresentation()
        }
        if animated {
            withAnimation(SidebarSpacePagerMetrics.creationReturnAnimation, update)
        } else {
            update()
        }
    }
}

private struct SidebarSpaceCreationRailView: View {
    let presentation: SidebarSpaceCreationPullPresentation
    let foregroundColor: Color

    var body: some View {
        let revealScale = SidebarSpaceCreationAffordanceLayout.revealScale(
            forDisplayedDistance: presentation.displayedDistance
        )

        HStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .stroke(foregroundColor.opacity(0.20), lineWidth: 2.2)

                Circle()
                    .trim(from: 0, to: presentation.progress)
                    .stroke(
                        foregroundColor.opacity(presentation.isArmed ? 1 : 0.84),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(foregroundColor.opacity(presentation.isArmed ? 1 : 0.78))
            }
            .frame(
                width: SidebarSpacePagerMetrics.creationAffordanceDiameter,
                height: SidebarSpacePagerMetrics.creationAffordanceDiameter
            )
            // Keep the complete circular affordance inside the revealed gap.
            // The former rectangular clip sliced through the ring and exposed
            // its darker gradient backing as a visible square.
            .scaleEffect(revealScale, anchor: .trailing)
            .opacity(revealScale)

            Spacer()
                .frame(width: SidebarSpacePagerMetrics.creationRailTrailingPadding)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SidebarSpaceCreationPullPresentationModifier: ViewModifier {
    @ObservedObject var controller: SidebarSpaceCreationPullController
    let foregroundColor: Color

    func body(content: Content) -> some View {
        let presentation = controller.presentation

        ZStack(alignment: .trailing) {
            SidebarSpaceCreationRailView(
                presentation: presentation,
                foregroundColor: foregroundColor
            )
            .frame(width: SidebarSpacePagerMetrics.creationRailMaximumWidth)

            content
                .offset(x: -presentation.displayedDistance)
        }
        .clipped()
    }
}
