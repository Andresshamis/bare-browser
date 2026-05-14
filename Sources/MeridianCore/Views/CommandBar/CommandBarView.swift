import AppKit
import SwiftUI

public struct CommandBarView: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var webViewState: WebViewState
    @State private var query = ""
    @State private var focusRequest = 0

    public init(store: BrowserStore, webViewState: WebViewState) {
        self.store = store
        self.webViewState = webViewState
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                CommandBarTextField(
                    text: $query,
                    placeholder: "Search or enter address",
                    focusRequest: focusRequest,
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
            .padding(.top, 10)
            .padding(.bottom, commandBarResults.isEmpty ? 10 : 2)

            if !commandBarResults.isEmpty {
                Divider()
                VStack(spacing: 2) {
                    ForEach(commandBarResults) { result in
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
                            .padding(.vertical, 6)
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
                }
                .padding(.bottom, 6)
            }
        }
        .frame(width: 620)
        .glassEffect(.regular, in: shape)
        .overlay(
            shape.stroke(.separator.opacity(0.45), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
        .onAppear {
            prepareInitialQuery()
        }
        .onChange(of: store.commandBarMode) { _, _ in
            prepareInitialQuery()
        }
        .onExitCommand {
            store.hideCommandBar()
        }
    }

    private var commandBarResults: [CommandBarResult] {
        store.commandBarResults(for: query, browserActionAvailability: browserActionAvailability)
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
        focusRequest += 1
    }

    private var browserActionAvailability: CommandRouter.BrowserActionAvailability {
        let activeTab = store.activeTab
        return CommandRouter.BrowserActionAvailability(
            canGoBack: webViewState.canGoBack,
            canGoForward: webViewState.canGoForward,
            canReload: activeTab?.url != nil,
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
            guard store.activeTab?.url != nil else {
                return false
            }
            webViewState.dispatch(webViewState.isLoading ? .stopLoading : .reload)
            return true
        case .stopLoading:
            guard store.activeTab?.url != nil, webViewState.isLoading else {
                return false
            }
            webViewState.dispatch(.stopLoading)
            return true
        case .goBack:
            guard webViewState.canGoBack else {
                return false
            }
            webViewState.dispatch(.goBack)
            return true
        case .goForward:
            guard webViewState.canGoForward else {
                return false
            }
            webViewState.dispatch(.goForward)
            return true
        case .closeTab, .pinTab, .addTabToEssentials, .moveTabToRegular, .moveTabUp, .moveTabDown, .splitActiveTab:
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
        DispatchQueue.main.async {
            guard let window = textField.window else {
                return
            }

            window.makeKey()
            window.makeFirstResponder(textField)

            guard selectAll else {
                return
            }

            textField.selectText(nil)
            textField.currentEditor()?.selectAll(nil)
        }
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
