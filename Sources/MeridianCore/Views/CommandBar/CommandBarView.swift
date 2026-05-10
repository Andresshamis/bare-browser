import SwiftUI

public struct CommandBarView: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var webViewState: WebViewState
    @FocusState private var isFocused: Bool
    @State private var query = ""

    public init(store: BrowserStore, webViewState: WebViewState) {
        self.store = store
        self.webViewState = webViewState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Search or enter address", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isFocused)
                    .onSubmit(submit)

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
                                    .frame(width: 42, alignment: .trailing)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            store.hideCommandBar()
        }
    }

    private var commandBarResults: [CommandBarResult] {
        store.commandBarResults(for: query, browserActionAvailability: browserActionAvailability)
    }

    private func submit() {
        store.submitCommandInput(query, browserActionHandler: performBrowserAction)
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
        case .closeTab, .pinTab, .addTabToEssentials, .moveTabToRegular, .splitActiveTab:
            return false
        }
    }
}
