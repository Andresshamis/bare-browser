import AppKit
import SwiftUI

public struct BrowserWindowView: View {
    @ObservedObject private var store: BrowserStore
    @StateObject private var webViewState = WebViewState()
    private let dataStoreProvider = ProfileWebsiteDataStoreProvider()

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        NavigationSplitView {
            if store.sidebarIsVisible {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            }
        } detail: {
            BrowserContentView(
                store: store,
                webViewState: webViewState,
                dataStoreProvider: dataStoreProvider
            )
            .overlay(alignment: .top) {
                if store.isCommandBarPresented {
                    CommandBarView(store: store, webViewState: webViewState)
                        .padding(.top, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .focusedSceneValue(\.browserNavigationCommandContext, browserNavigationCommandContext)
        .animation(.snappy(duration: 0.16), value: store.isCommandBarPresented)
        .alert(
            store.pendingURLConfirmation?.confirmationTitle ?? "Open Link?",
            isPresented: pendingURLConfirmationIsPresented,
            presenting: store.pendingURLConfirmation
        ) { request in
            Button("Cancel", role: .cancel) {
                store.cancelPendingURLConfirmation()
            }
            Button(request.confirmButtonTitle) {
                store.approvePendingURLConfirmation { url in
                    NSWorkspace.shared.open(url)
                }
            }
        } message: { request in
            Text(request.confirmationMessage)
        }
        .alert(
            store.pendingDownloadConfirmation?.confirmationTitle ?? "Download File?",
            isPresented: pendingDownloadConfirmationIsPresented,
            presenting: store.pendingDownloadConfirmation
        ) { request in
            Button("Cancel", role: .cancel) {
                store.cancelPendingDownloadConfirmation()
            }
            Button(request.confirmButtonTitle) {
                if store.beginPendingDownloadDestinationSelection() {
                    presentSavePanel(for: request)
                }
            }
        } message: { request in
            Text(request.confirmationMessage)
        }
    }

    private var browserNavigationCommandContext: BrowserNavigationCommandContext {
        BrowserNavigationCommandContext(
            canGoBack: webViewState.canGoBack,
            canGoForward: webViewState.canGoForward,
            canReload: store.activeTab?.url != nil,
            canStopLoading: webViewState.isLoading
        ) { command in
            webViewState.dispatch(command)
        }
    }

    private var pendingURLConfirmationIsPresented: Binding<Bool> {
        Binding {
            store.pendingURLConfirmation != nil
        } set: { isPresented in
            if !isPresented {
                store.cancelPendingURLConfirmation()
            }
        }
    }

    private var pendingDownloadConfirmationIsPresented: Binding<Bool> {
        Binding {
            store.pendingDownloadConfirmation != nil && !store.isChoosingDownloadDestination
        } set: { isPresented in
            if !isPresented {
                store.dismissPendingDownloadConfirmationAlert()
            }
        }
    }

    private func presentSavePanel(for request: DownloadConfirmationRequest) {
        let panel = NSSavePanel()
        panel.title = request.confirmationTitle
        panel.nameFieldStringValue = request.sanitizedFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let destinationURL = panel.url else {
                    store.cancelPendingDownloadConfirmation()
                    return
                }

                store.approvePendingDownloadConfirmation(destination: destinationURL)
            }
        }
    }
}
