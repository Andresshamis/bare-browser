import SwiftUI
import UniformTypeIdentifiers

enum SidebarTabReorderInteractionMetrics {
    static let animation = Animation.smooth(duration: 0.18, extraBounce: 0)
    static let indicatorAnimation = Animation.smooth(duration: 0.12, extraBounce: 0)
    static let rowDropMidlineY: CGFloat = 14
}

struct SidebarTabDropState: Equatable {
    var activeSlotID: String?
    var suppressTargetsUntilNextDrag = false

    mutating func beginDrag() {
        activeSlotID = nil
        suppressTargetsUntilNextDrag = false
    }

    mutating func target(_ slotID: String) {
        guard !suppressTargetsUntilNextDrag else {
            return
        }

        activeSlotID = slotID
    }

    mutating func clearTarget(_ slotID: String? = nil) {
        guard slotID == nil || activeSlotID == slotID else {
            return
        }

        activeSlotID = nil
    }

    mutating func finishDrop() {
        activeSlotID = nil
        suppressTargetsUntilNextDrag = true
    }
}

struct SidebarTabDropSlot: View {
    let slotID: String
    let resetToken: String
    @Binding var dropState: SidebarTabDropState
    let moveTab: (TabID) -> Bool

    private var isTargeted: Bool {
        dropState.activeSlotID == slotID && !dropState.suppressTargetsUntilNextDrag
    }

    var body: some View {
        Capsule()
            .frame(height: 2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 10)
            .frame(maxWidth: .infinity)
            .opacity(isTargeted ? 1 : 0)
            .scaleEffect(x: isTargeted ? 1 : 0.88, anchor: .leading)
            .contentShape(Rectangle())
            .animation(SidebarTabReorderInteractionMetrics.indicatorAnimation, value: isTargeted)
            .onDrop(
                of: SidebarTabDragPayload.acceptedTypes,
                delegate: SidebarTabDropSlotDelegate(
                    slotID: slotID,
                    dropState: $dropState,
                    moveTab: moveTab
                )
            )
            .onAppear {
                clearTarget(animated: false)
            }
            .onChange(of: resetToken) { _, _ in
                clearTarget(animated: false)
            }
    }

    private func clearTarget(animated: Bool) {
        if animated {
            withAnimation(SidebarTabReorderInteractionMetrics.indicatorAnimation) {
                dropState.clearTarget(slotID)
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                dropState.clearTarget(slotID)
            }
        }
    }
}

struct SidebarTabDropTarget {
    let slotID: String
    let moveTab: (TabID) -> Bool
}

struct SidebarTabDropRegion<Content: View>: View {
    let upperTarget: SidebarTabDropTarget
    let lowerTarget: SidebarTabDropTarget
    @Binding var dropState: SidebarTabDropState
    let content: Content

    init(
        upperTarget: SidebarTabDropTarget,
        lowerTarget: SidebarTabDropTarget,
        dropState: Binding<SidebarTabDropState>,
        @ViewBuilder content: () -> Content
    ) {
        self.upperTarget = upperTarget
        self.lowerTarget = lowerTarget
        self._dropState = dropState
        self.content = content()
    }

    var body: some View {
        content
            .onDrop(
                of: SidebarTabDragPayload.acceptedTypes,
                delegate: SidebarTabDropRegionDelegate(
                    upperTarget: upperTarget,
                    lowerTarget: lowerTarget,
                    dropState: $dropState
                )
            )
    }
}

private enum SidebarTabDragPayload {
    static let acceptedTypes: [UTType] = [.plainText, .text]

    static func loadTabID(from info: DropInfo, completion: @escaping @MainActor (TabID?) -> Void) {
        guard let provider = info.itemProviders(for: acceptedTypes).first else {
            Task { @MainActor in
                completion(nil)
            }
            return
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            let value = (object as? String) ?? (object as? NSString).map(String.init)
            let tabID = value.flatMap(UUID.init(uuidString:))

            Task { @MainActor in
                completion(tabID)
            }
        }
    }
}

private struct SidebarTabDropRegionDelegate: DropDelegate {
    let upperTarget: SidebarTabDropTarget
    let lowerTarget: SidebarTabDropTarget
    @Binding var dropState: SidebarTabDropState

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: SidebarTabDragPayload.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        setTargeted(target(for: info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        setTargeted(target(for: info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearCurrentRegionTarget()
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = target(for: info)
        finishDrop()

        SidebarTabDragPayload.loadTabID(from: info) { draggedTabID in
            guard let draggedTabID else {
                finishDrop()
                return
            }

            _ = target.moveTab(draggedTabID)

            finishDrop()
        }

        return true
    }

    private func target(for info: DropInfo) -> SidebarTabDropTarget {
        info.location.y < SidebarTabReorderInteractionMetrics.rowDropMidlineY ? upperTarget : lowerTarget
    }

    private func clearCurrentRegionTarget() {
        guard dropState.activeSlotID == upperTarget.slotID ||
                dropState.activeSlotID == lowerTarget.slotID else {
            return
        }

        withAnimation(SidebarTabReorderInteractionMetrics.indicatorAnimation) {
            dropState.clearTarget()
        }
    }

    private func finishDrop() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            dropState.finishDrop()
        }
    }

    private func setTargeted(_ target: SidebarTabDropTarget) {
        guard !dropState.suppressTargetsUntilNextDrag,
              dropState.activeSlotID != target.slotID else {
            return
        }

        withAnimation(SidebarTabReorderInteractionMetrics.indicatorAnimation) {
            dropState.target(target.slotID)
        }
    }
}

private struct SidebarTabDropSlotDelegate: DropDelegate {
    let slotID: String
    @Binding var dropState: SidebarTabDropState
    let moveTab: (TabID) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: SidebarTabDragPayload.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        setTargeted()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        setTargeted()
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearTarget(animated: true)
    }

    func performDrop(info: DropInfo) -> Bool {
        clearTargetAfterDrop()

        SidebarTabDragPayload.loadTabID(from: info) { draggedTabID in
            guard let draggedTabID else {
                clearTargetAfterDrop()
                return
            }

            _ = moveTab(draggedTabID)

            clearTargetAfterDrop()
        }

        return true
    }

    private func clearTarget(animated: Bool) {
        if animated {
            withAnimation(SidebarTabReorderInteractionMetrics.indicatorAnimation) {
                dropState.clearTarget(slotID)
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                dropState.clearTarget(slotID)
            }
        }
    }

    private func clearTargetAfterDrop() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            dropState.finishDrop()
        }
    }

    private func setTargeted() {
        guard !dropState.suppressTargetsUntilNextDrag,
              dropState.activeSlotID != slotID else {
            return
        }

        withAnimation(SidebarTabReorderInteractionMetrics.indicatorAnimation) {
            dropState.target(slotID)
        }
    }
}
