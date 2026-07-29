import AppKit
import OSLog
import QuartzCore
import SwiftUI

#if DEBUG
let sidebarPagerPerformanceLog = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "MeridianBrowser",
    category: .pointsOfInterest
)
#endif

@MainActor
protocol SidebarAddressMorphRendering: AnyObject {
    func setMorphState(_ state: SidebarAddressMorphState?)
}

@MainActor
private final class SidebarAddressWeakRenderer {
    weak var renderer: (any SidebarAddressMorphRendering)?

    init(_ renderer: any SidebarAddressMorphRendering) {
        self.renderer = renderer
    }
}

/// A reference-only bridge for the address transition.
///
/// Scroll samples terminate at retained AppKit/Core Animation objects instead
/// of publishing through SwiftUI's observation graph.
@MainActor
final class SidebarAddressMorphController {
    private(set) var state: SidebarAddressMorphState?
    private var renderers: [SidebarAddressWeakRenderer] = []

    func update(_ state: SidebarAddressMorphState?) {
        guard self.state != state else {
            return
        }

        self.state = state
        renderers.removeAll { $0.renderer == nil }
        for renderer in renderers {
            renderer.renderer?.setMorphState(state)
        }
    }

    func attach(_ renderer: any SidebarAddressMorphRendering) {
        renderers.removeAll {
            guard let attachedRenderer = $0.renderer else {
                return true
            }
            return attachedRenderer === renderer
        }
        renderers.append(SidebarAddressWeakRenderer(renderer))
        renderer.setMorphState(state)
    }

    func detach(_ renderer: any SidebarAddressMorphRendering) {
        renderers.removeAll {
            guard let attachedRenderer = $0.renderer else {
                return true
            }
            return attachedRenderer === renderer
        }
    }

    var attachedRendererCountForTesting: Int {
        renderers.lazy.compactMap(\.renderer).count
    }
}

/// Owns all display-rate side effects of horizontal space paging.
///
/// Only the retained chrome and address renderers are updated per sample.
/// Fixed SwiftUI chrome and browser-content preview state change only when the
/// directional target crosses an endpoint.
@MainActor
final class SidebarPagerLiveRenderController {
    private var pageIDs: [SidebarSpacePagerPageID] = []
    private var pageTexts: [String] = []
    private var pageStyles: [SidebarChromeLiveStyle] = []
    private var directionalTargetPageID: SidebarSpacePagerPageID?
    private var previewPageID: SidebarSpacePagerPageID?
    private var hasPreviewPageID = false
#if DEBUG
    private var gestureSignpostID: OSSignpostID?
#endif

    func begin(
        pageIDs: [SidebarSpacePagerPageID],
        pageTexts: [String],
        pageStyles: [SidebarChromeLiveStyle]
    ) {
        self.pageIDs = pageIDs
        self.pageTexts = pageTexts
        self.pageStyles = pageStyles
        directionalTargetPageID = nil
        previewPageID = nil
        hasPreviewPageID = false
#if DEBUG
        if let gestureSignpostID {
            os_signpost(
                .end,
                log: sidebarPagerPerformanceLog,
                name: "Sidebar Space Paging",
                signpostID: gestureSignpostID
            )
        }
        let signpostID = OSSignpostID(log: sidebarPagerPerformanceLog)
        gestureSignpostID = signpostID
        os_signpost(
            .begin,
            log: sidebarPagerPerformanceLog,
            name: "Sidebar Space Paging",
            signpostID: signpostID
        )
#endif
    }

    func update(
        fractionalPageIndex: CGFloat,
        directionalTargetPageID: SidebarSpacePagerPageID?,
        selectedPageID: SidebarSpacePagerPageID?,
        addressController: SidebarAddressMorphController,
        updateChrome: (SidebarChromeLiveStyle?) -> Void,
        updateFixedChrome: (SidebarChromeLiveStyle?, Bool) -> Void,
        previewPage: (SidebarSpacePagerPageID?) -> Void
    ) {
#if DEBUG
        let sampleSignpostID = OSSignpostID(log: sidebarPagerPerformanceLog)
        os_signpost(
            .begin,
            log: sidebarPagerPerformanceLog,
            name: "Sidebar Pager Live Render",
            signpostID: sampleSignpostID
        )
        defer {
            os_signpost(
                .end,
                log: sidebarPagerPerformanceLog,
                name: "Sidebar Pager Live Render",
                signpostID: sampleSignpostID
            )
        }
#endif
        addressController.update(
            SidebarAddressScrollMorph.state(
                at: fractionalPageIndex,
                pageTexts: pageTexts
            )
        )
        updateChrome(
            SidebarSpacePagerChrome.liveStyle(
                at: fractionalPageIndex,
                styles: pageStyles
            )
        )

        if self.directionalTargetPageID != directionalTargetPageID {
            self.directionalTargetPageID = directionalTargetPageID
            updateFixedChrome(style(for: directionalTargetPageID), true)
        }

        let resolvedPreviewPageID = directionalTargetPageID.flatMap {
            SidebarSpacePagerPreview.pageID(
                for: $0,
                selectedPageID: selectedPageID
            )
        }
        guard !hasPreviewPageID || previewPageID != resolvedPreviewPageID else {
            return
        }

        hasPreviewPageID = true
        previewPageID = resolvedPreviewPageID
        previewPage(resolvedPreviewPageID)
    }

    func end(
        settledPageID: SidebarSpacePagerPageID?,
        fallbackStyle: SidebarChromeLiveStyle?,
        addressController: SidebarAddressMorphController,
        updateChrome: (SidebarChromeLiveStyle?) -> Void,
        updateFixedChrome: (SidebarChromeLiveStyle?, Bool) -> Void,
        previewPage: (SidebarSpacePagerPageID?) -> Void
    ) {
        let settledStyle = style(for: settledPageID) ?? fallbackStyle
        updateChrome(settledStyle)
        updateFixedChrome(settledStyle, false)
        addressController.update(nil)

        if !hasPreviewPageID || previewPageID != nil {
            previewPage(nil)
        }
        directionalTargetPageID = nil
        previewPageID = nil
        hasPreviewPageID = true
#if DEBUG
        if let gestureSignpostID {
            os_signpost(
                .end,
                log: sidebarPagerPerformanceLog,
                name: "Sidebar Space Paging",
                signpostID: gestureSignpostID
            )
            self.gestureSignpostID = nil
        }
#endif
    }

    func reset(
        addressController: SidebarAddressMorphController,
        updateChrome: (SidebarChromeLiveStyle?) -> Void,
        updateFixedChrome: (SidebarChromeLiveStyle?, Bool) -> Void,
        previewPage: (SidebarSpacePagerPageID?) -> Void
    ) {
        pageIDs = []
        pageTexts = []
        pageStyles = []
        directionalTargetPageID = nil
        previewPageID = nil
        hasPreviewPageID = false
        addressController.update(nil)
        updateChrome(nil)
        updateFixedChrome(nil, false)
        previewPage(nil)
#if DEBUG
        if let gestureSignpostID {
            os_signpost(
                .end,
                log: sidebarPagerPerformanceLog,
                name: "Sidebar Space Paging",
                signpostID: gestureSignpostID
            )
            self.gestureSignpostID = nil
        }
#endif
    }

    private func style(
        for pageID: SidebarSpacePagerPageID?
    ) -> SidebarChromeLiveStyle? {
        guard let pageID,
              let index = pageIDs.firstIndex(of: pageID),
              pageStyles.indices.contains(index) else {
            return nil
        }
        return pageStyles[index]
    }
}

struct SidebarAddressCrossfadePresentation: Equatable, Sendable {
    let sourceOpacity: Double
    let destinationOpacity: Double
    let sourceTranslationY: CGFloat
    let destinationTranslationY: CGFloat

    static func resolved(
        progress: Double,
        isActive: Bool
    ) -> SidebarAddressCrossfadePresentation {
        guard isActive else {
            return SidebarAddressCrossfadePresentation(
                sourceOpacity: 1,
                destinationOpacity: 0,
                sourceTranslationY: 0,
                destinationTranslationY: 0
            )
        }

        let clampedProgress = min(max(progress.isFinite ? progress : 0, 0), 1)
        let smoothProgress =
            clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
        return SidebarAddressCrossfadePresentation(
            sourceOpacity: 1 - smoothProgress,
            destinationOpacity: smoothProgress,
            sourceTranslationY: CGFloat(-1.5 * smoothProgress),
            destinationTranslationY: CGFloat(1.5 * (1 - smoothProgress))
        )
    }
}

enum SidebarAddressTextLayout {
    static let controlHeight: CGFloat = 30

    static func textFrame(
        in bounds: CGRect,
        preferredHeight: CGFloat
    ) -> CGRect {
        let finiteHeight = preferredHeight.isFinite ? preferredHeight : 0
        let height = min(max(ceil(finiteHeight), 0), max(bounds.height, 0))
        return CGRect(
            x: bounds.minX,
            y: bounds.minY + floor((bounds.height - height) / 2),
            width: max(bounds.width, 0),
            height: height
        )
    }
}

struct SidebarAddressMorphingText: NSViewRepresentable {
    let settledText: String
    let foregroundWhiteAmount: Double
    let controller: SidebarAddressMorphController

    func makeNSView(context: Context) -> SidebarAddressMorphView {
        let view = SidebarAddressMorphView()
        view.updateConfiguration(
            settledText: settledText,
            foregroundWhiteAmount: foregroundWhiteAmount
        )
        view.attach(to: controller)
        return view
    }

    func updateNSView(_ nsView: SidebarAddressMorphView, context: Context) {
        nsView.updateConfiguration(
            settledText: settledText,
            foregroundWhiteAmount: foregroundWhiteAmount
        )
        nsView.attach(to: controller)
    }

    static func dismantleNSView(
        _ nsView: SidebarAddressMorphView,
        coordinator: ()
    ) {
        nsView.detachFromController()
    }
}

@MainActor
final class SidebarAddressMorphView: NSView, SidebarAddressMorphRendering {
    private let sourceField = NSTextField(labelWithString: "")
    private let destinationField = NSTextField(labelWithString: "")
    private weak var controller: SidebarAddressMorphController?
    private var settledText = ""
    private var foregroundWhiteAmount = 1.0
    private var morphState: SidebarAddressMorphState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: SidebarAddressTextLayout.controlHeight
        )
    }

    override func layout() {
        super.layout()
        let preferredHeight = max(
            sourceField.intrinsicContentSize.height,
            destinationField.intrinsicContentSize.height
        )
        let textFrame = SidebarAddressTextLayout.textFrame(
            in: bounds,
            preferredHeight: preferredHeight
        )
        withoutImplicitLayerActions {
            sourceField.frame = textFrame
            destinationField.frame = textFrame
            updateContentsScale()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        withoutImplicitLayerActions {
            updateContentsScale()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func updateConfiguration(
        settledText: String,
        foregroundWhiteAmount: Double
    ) {
        let clampedWhiteAmount = min(
            max(foregroundWhiteAmount.isFinite ? foregroundWhiteAmount : 0, 0),
            1
        )
        guard self.settledText != settledText
                || self.foregroundWhiteAmount != clampedWhiteAmount else {
            return
        }

        self.settledText = settledText
        self.foregroundWhiteAmount = clampedWhiteAmount
        let color = NSColor(
            calibratedWhite: clampedWhiteAmount,
            alpha: 1
        )
        sourceField.textColor = color
        destinationField.textColor = color
        applyPresentation()
    }

    func attach(to controller: SidebarAddressMorphController) {
        guard self.controller !== controller else {
            return
        }

        self.controller?.detach(self)
        self.controller = controller
        controller.attach(self)
    }

    func detachFromController() {
        controller?.detach(self)
        controller = nil
    }

    func setMorphState(_ state: SidebarAddressMorphState?) {
        guard morphState != state else {
            return
        }
        morphState = state
        applyPresentation()
    }

    private func configureView() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        for field in [sourceField, destinationField] {
            field.font = .systemFont(ofSize: 13)
            field.alignment = .left
            field.lineBreakMode = .byTruncatingMiddle
            field.maximumNumberOfLines = 1
            field.cell?.wraps = false
            field.cell?.isScrollable = true
            field.wantsLayer = true
            field.layerContentsRedrawPolicy = .never
            addSubview(field)
        }

        destinationField.alphaValue = 0
    }

    private func applyPresentation() {
        let state = morphState
        let sourceText = state?.sourceText ?? settledText
        let destinationText = state?.destinationText ?? settledText
        if sourceField.stringValue != sourceText {
            sourceField.stringValue = sourceText
        }
        if destinationField.stringValue != destinationText {
            destinationField.stringValue = destinationText
        }

        let presentation = SidebarAddressCrossfadePresentation.resolved(
            progress: state?.progress ?? 0,
            isActive: state != nil
        )
        withoutImplicitLayerActions {
            sourceField.alphaValue = presentation.sourceOpacity
            destinationField.alphaValue = presentation.destinationOpacity
            sourceField.layer?.setAffineTransform(
                CGAffineTransform(
                    translationX: 0,
                    y: presentation.sourceTranslationY
                )
            )
            destinationField.layer?.setAffineTransform(
                CGAffineTransform(
                    translationX: 0,
                    y: presentation.destinationTranslationY
                )
            )
        }
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        sourceField.layer?.contentsScale = scale
        destinationField.layer?.contentsScale = scale
    }

    private func withoutImplicitLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}
