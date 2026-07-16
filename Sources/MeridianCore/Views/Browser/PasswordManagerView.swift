import SwiftUI

public struct PasswordManagerView: View {
    @ObservedObject private var store: BrowserStore
    @State private var accounts: [SavedPasswordAccount] = []
    @State private var searchText = ""
    @State private var selectedProfileID: ProfileID?
    @State private var keychainAccessIssue: String?

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            controls
            keychainAccessBanner
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshAccounts(checkKeychainAccess: true, allowsKeychainPrompt: false)
        }
        .onChange(of: store.profiles.map(\.id)) { _, profileIDs in
            if let selectedProfileID,
               !profileIDs.contains(selectedProfileID) {
                self.selectedProfileID = nil
            }
            refreshAccounts(checkKeychainAccess: true, allowsKeychainPrompt: false)
        }
        .onChange(of: store.lastUserMessage) { _, message in
            if message?.hasPrefix("Password saved for ") == true {
                refreshAccounts(checkKeychainAccess: true, allowsKeychainPrompt: false)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("Passwords")
                    .font(.title2.weight(.semibold))
                Text(summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                refreshAccounts(checkKeychainAccess: true, allowsKeychainPrompt: false)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Refresh saved accounts")
            .accessibilityLabel("Refresh saved accounts")
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search sites or accounts", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 11)
            .frame(minWidth: 260, maxWidth: 420)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }

            Picker("Profile", selection: $selectedProfileID) {
                Text("All Profiles").tag(ProfileID?.none)
                ForEach(store.persistentProfiles) { profile in
                    Text(profile.name).tag(ProfileID?.some(profile.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 190)
            .help("Filter by profile")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var keychainAccessBanner: some View {
        if let keychainAccessIssue {
            HStack(spacing: 10) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)

                Text(keychainAccessIssue)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button {
                    checkKeychainAccess(allowsKeychainPrompt: true)
                } label: {
                    Label("Unlock", systemImage: "lock.open")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Open the macOS Keychain permission prompt")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.12))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(height: 1)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        if filteredAccounts.isEmpty {
            emptyState
        } else {
            Table(filteredAccounts) {
                TableColumn("Site") { account in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayHost)
                            .lineLimit(1)
                        Text(account.origin.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help(account.origin.absoluteString)
                }
                TableColumn("Account") { account in
                    Text(account.username)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(account.username)
                }
                TableColumn("Profile") { account in
                    Text(profileName(for: account.profileID))
                        .lineLimit(1)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: accounts.isEmpty ? "key.slash" : "magnifyingglass")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(accounts.isEmpty ? "No saved passwords" : "No matching accounts")
                .font(.headline)
            Text(accounts.isEmpty
                ? "Saved website accounts for persistent profiles will appear here."
                : "Try a different search or profile filter.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var filteredAccounts: [SavedPasswordAccount] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return accounts.filter { account in
            let profileMatches = selectedProfileID == nil || account.profileID == selectedProfileID
            guard profileMatches else {
                return false
            }

            guard !trimmedSearch.isEmpty else {
                return true
            }

            let searchHaystack = [
                account.displayHost,
                account.origin.absoluteString,
                account.username,
                profileName(for: account.profileID)
            ].joined(separator: " ")

            return searchHaystack.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    private var summaryText: String {
        let count = filteredAccounts.count
        let base = count == 1 ? "1 saved account" : "\(count) saved accounts"
        guard let selectedProfileID else {
            return base
        }

        return "\(base) in \(profileName(for: selectedProfileID))"
    }

    private func profileName(for profileID: ProfileID) -> String {
        store.profiles.first { $0.id == profileID }?.name ?? "Unknown Profile"
    }

    private func refreshAccounts() {
        refreshAccounts(checkKeychainAccess: false)
    }

    private func refreshAccounts(
        checkKeychainAccess: Bool,
        allowsKeychainPrompt: Bool = false
    ) {
        accounts = store.savedPasswordAccounts()
        if checkKeychainAccess {
            self.checkKeychainAccess(allowsKeychainPrompt: allowsKeychainPrompt)
        }
    }

    private func checkKeychainAccess(allowsKeychainPrompt: Bool) {
        switch store.checkSavedPasswordKeychainAccess(
            for: accounts,
            allowsKeychainPrompt: allowsKeychainPrompt
        ) {
        case .available, .noSavedAccounts:
            keychainAccessIssue = nil
        case .unavailable:
            keychainAccessIssue = store.lastUserMessage ?? "Keychain access is needed to autofill saved passwords."
        }
    }
}
