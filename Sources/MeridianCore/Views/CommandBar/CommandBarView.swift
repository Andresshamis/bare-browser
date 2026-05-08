import SwiftUI

public struct CommandBarView: View {
    @ObservedObject private var store: BrowserStore
    @FocusState private var isFocused: Bool
    @State private var query = ""

    public init(store: BrowserStore) {
        self.store = store
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

            if !matchingTabs.isEmpty {
                Divider()
                VStack(spacing: 2) {
                    ForEach(matchingTabs.prefix(5)) { tab in
                        Button {
                            store.selectTab(tab.id)
                            store.hideCommandBar()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(tab.title)
                                    .lineLimit(1)
                                Spacer()
                                Text(tab.url?.host(percentEncoded: false) ?? "")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
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

    private var matchingTabs: [BrowserTab] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        return store.tabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(trimmed)
                || (tab.url?.absoluteString.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private func submit() {
        store.submitCommandInput(query)
    }
}
