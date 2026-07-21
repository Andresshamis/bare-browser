import AppKit
import SwiftUI

enum CommandBarMetrics {
    static let width: CGFloat = 620
    static var maximumHeight: CGFloat {
        expandedHeight
    }

    static let maximumVisibleResults = 6
    static let searchAreaHeight: CGFloat = 48
    static let resultRowHeight: CGFloat = 28
    static let resultRowSpacing: CGFloat = 2
    static let resultsBottomPadding: CGFloat = 6
    static let dividerHeight: CGFloat = 1
    static var resultsAreaHeight: CGFloat {
        CGFloat(maximumVisibleResults) * resultRowHeight
            + CGFloat(maximumVisibleResults - 1) * resultRowSpacing
            + resultsBottomPadding
    }
    static let compactHeight = searchAreaHeight
    static var expandedHeight: CGFloat {
        searchAreaHeight + dividerHeight + resultsAreaHeight
    }
}

public struct CommandBarView: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var webViewState: WebViewState
    @State private var query = ""
    @Namespace private var glassNamespace

    public init(store: BrowserStore, webViewState: WebViewState) {
        self.store = store
        self.webViewState = webViewState
    }

    public var body: some View {
        let results = visibleCommandBarResults
        let hasResults = !results.isEmpty
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        GlassEffectContainer(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    CommandBarTextField(
                        text: $query,
                        placeholder: "Search or enter address",
                        focusRequest: store.commandBarFocusRequest,
                        submit: submit,
                        cancel: { store.hideCommandBar() }
                    )
                    .frame(height: 28)

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Clear")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: CommandBarMetrics.searchAreaHeight)

                if hasResults {
                    Divider()
                        .frame(height: CommandBarMetrics.dividerHeight)

                    VStack(spacing: CommandBarMetrics.resultRowSpacing) {
                        ForEach(results) { result in
                            Button {
                                store.activateCommandBarResult(result, browserActionHandler: performBrowserAction)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: result.symbolName)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    Text(result.title)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(result.subtitle)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(result.kindLabel)
                                        .foregroundStyle(.tertiary)
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: 54, alignment: .trailing)
                                }
                                .font(.system(size: 13))
                                .padding(.horizontal, 12)
                                .frame(height: CommandBarMetrics.resultRowHeight)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if case .history(let entry) = result {
                                    Button("Delete History Entry", role: .destructive) {
                                        store.deleteHistoryEntry(entry.id, profileID: entry.profileID)
                                    }
                                }
                            }
                        }

                        if results.count < CommandBarMetrics.maximumVisibleResults {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: CommandBarMetrics.resultsAreaHeight - CommandBarMetrics.resultsBottomPadding, alignment: .top)
                    .padding(.bottom, CommandBarMetrics.resultsBottomPadding)
                    .transition(.opacity)
                }
            }
            .frame(
                width: CommandBarMetrics.width,
                height: hasResults ? CommandBarMetrics.expandedHeight : CommandBarMetrics.compactHeight,
                alignment: .topLeading
            )
            .contentShape(shape)
            .glassEffect(.regular.interactive(false), in: shape)
            .glassEffectID("commandBarSurface", in: glassNamespace)
            .glassEffectTransition(.matchedGeometry)
            .compositingGroup()
        }
        .overlay(
            shape.stroke(.separator.opacity(0.45), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
        .onAppear {
            prepareInitialQuery()
        }
        .onChange(of: store.commandBarFocusRequest) { _, _ in
            prepareInitialQuery()
        }
        .onExitCommand {
            store.hideCommandBar()
        }
        .animation(.smooth(duration: 0.18), value: hasResults)
    }

    private var commandBarResults: [CommandBarResult] {
        store.commandBarResults(for: query, browserActionAvailability: browserActionAvailability)
    }

    private var visibleCommandBarResults: [CommandBarResult] {
        Array(commandBarResults.prefix(CommandBarMetrics.maximumVisibleResults))
    }

    private func submit() {
        store.submitAddressInput(query, browserActionHandler: performBrowserAction)
    }

    private func prepareInitialQuery() {
        switch store.commandBarMode {
        case .address:
            query = store.activeTab?.url?.absoluteString ?? ""
        case .newTab:
            query = ""
        }
    }

    private var browserActionAvailability: CommandRouter.BrowserActionAvailability {
        let activeTab = store.activeTab
        return CommandRouter.BrowserActionAvailability(
            canGoBack: webViewState.canGoBack,
            canGoForward: webViewState.canGoForward,
            canReload: activeTab?.content.isWeb == true && activeTab?.url != nil,
            canCloseTab: activeTab != nil,
            canPinTab: activeTab.map { !$0.isPinned || $0.isFavorite || $0.parentFolderID != nil } ?? false,
            canAddTabToEssentials: activeTab.map { !$0.isFavorite || $0.isPinned || $0.parentFolderID != nil } ?? false,
            canMoveTabToRegular: activeTab.map { $0.isPinned || $0.isFavorite || $0.parentFolderID != nil } ?? false,
            canMoveTabUp: store.canMoveSelectedTab(.up),
            canMoveTabDown: store.canMoveSelectedTab(.down),
            isLoading: webViewState.isLoading
        )
    }

    private func performBrowserAction(_ action: CommandRouter.BrowserAction) -> Bool {
        switch action {
        case .reload:
            guard store.activeTab?.content.isWeb == true, store.activeTab?.url != nil else {
                return false
            }
            webViewState.dispatch(webViewState.isLoading ? .stopLoading : .reload, targetTabID: store.selectedTabID)
            return true
        case .stopLoading:
            guard store.activeTab?.content.isWeb == true, store.activeTab?.url != nil, webViewState.isLoading else {
                return false
            }
            webViewState.dispatch(.stopLoading, targetTabID: store.selectedTabID)
            return true
        case .goBack:
            guard webViewState.canGoBack else {
                return false
            }
            webViewState.dispatch(.goBack, targetTabID: store.selectedTabID)
            return true
        case .goForward:
            guard webViewState.canGoForward else {
                return false
            }
            webViewState.dispatch(.goForward, targetTabID: store.selectedTabID)
            return true
        case .closeTab, .pinTab, .addTabToEssentials, .moveTabToRegular, .moveTabUp, .moveTabDown,
             .splitActiveTab, .openPasswordManager:
            return false
        }
    }
}

private struct CommandBarTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequest: Int
    let submit: () -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> FocusableCommandBarTextField {
        let textField = FocusableCommandBarTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: 18, weight: .medium)
        textField.lineBreakMode = .byTruncatingMiddle
        textField.isEditable = true
        textField.isSelectable = true
        textField.refusesFirstResponder = false
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ textField: FocusableCommandBarTextField, context: Context) {
        context.coordinator.parent = self
        textField.onMouseDown = {
            focus(textField, selectAll: false)
        }

        if textField.stringValue != text {
            textField.stringValue = text
        }

        guard context.coordinator.lastFocusRequest != focusRequest else {
            return
        }
        context.coordinator.lastFocusRequest = focusRequest
        focus(textField, selectAll: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func focus(_ textField: FocusableCommandBarTextField, selectAll: Bool) {
        attemptFocus(textField, selectAll: selectAll, remainingAttempts: 8)
    }

    private func attemptFocus(
        _ textField: FocusableCommandBarTextField,
        selectAll: Bool,
        remainingAttempts: Int
    ) {
        let delay = remainingAttempts == 8 ? 0 : 0.03
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = textField.window else {
                retryFocusIfNeeded(textField, selectAll: selectAll, remainingAttempts: remainingAttempts)
                return
            }

            guard window.isKeyWindow else {
                return
            }
            guard window.makeFirstResponder(textField) else {
                retryFocusIfNeeded(textField, selectAll: selectAll, remainingAttempts: remainingAttempts)
                return
            }

            guard selectAll else {
                return
            }

            textField.selectText(nil)
            textField.currentEditor()?.selectAll(nil)
        }
    }

    private func retryFocusIfNeeded(
        _ textField: FocusableCommandBarTextField,
        selectAll: Bool,
        remainingAttempts: Int
    ) {
        guard remainingAttempts > 0 else {
            return
        }
        attemptFocus(textField, selectAll: selectAll, remainingAttempts: remainingAttempts - 1)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandBarTextField
        var lastFocusRequest = 0

        init(parent: CommandBarTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }
            parent.text = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.submit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.cancel()
                return true
            default:
                return false
            }
        }
    }
}

private final class FocusableCommandBarTextField: NSTextField {
    var onMouseDown: (() -> Void)?

    override var allowsVibrancy: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}
