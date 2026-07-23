import SwiftUI

private enum ProfileEditorSelection: Hashable {
    case profile(ProfileID)
    case newProfile
}

struct ProfileManagementView: View {
    @ObservedObject private var store: BrowserStore
    private let request: ProfileManagementRequest

    @State private var selection: ProfileEditorSelection?
    @State private var lastExistingProfileID: ProfileID?
    @State private var draftName: String
    @State private var draftColorHex: String
    @State private var pendingDeletionProfileID: ProfileID?
    @State private var pendingDeletionProfileName = ""
    @State private var isDeletingProfile = false
    @FocusState private var nameFieldIsFocused: Bool

    private static let colorPresets = [
        "#6B8F71",
        "#0A84FF",
        "#5E5CE6",
        "#BF5AF2",
        "#FF375F",
        "#FF9F0A",
        "#30D158",
        "#64D2FF"
    ]

    init(store: BrowserStore, request: ProfileManagementRequest) {
        self.store = store
        self.request = request

        let initialProfile = request.initialProfileID.flatMap { profileID in
            store.persistentProfiles.first { $0.id == profileID }
        } ?? store.persistentProfiles.first

        if request.startsCreatingProfile {
            _selection = State(initialValue: .newProfile)
            _draftName = State(initialValue: store.suggestedPersistentProfileName)
            _draftColorHex = State(initialValue: Self.suggestedColorHex(for: store.persistentProfiles.count))
        } else {
            _selection = State(initialValue: initialProfile.map { .profile($0.id) })
            _draftName = State(initialValue: initialProfile?.name ?? "")
            _draftColorHex = State(initialValue: initialProfile?.colorHex ?? Self.colorPresets[0])
        }
        _lastExistingProfileID = State(initialValue: initialProfile?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                profileList
                    .frame(width: 230)

                Divider()

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack {
                Text("Profiles keep website sessions, history, Lumen Browser-managed passwords, and supported site permissions separate. macOS AutoFill suggestions are device-wide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    store.dismissProfileManager()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 760, height: 540)
        .alert("Remove Profile?", isPresented: deletionConfirmationIsPresented) {
            Button("Cancel", role: .cancel) {
                pendingDeletionProfileID = nil
            }
            Button("Remove Profile", role: .destructive) {
                removePendingProfile()
            }
        } message: {
            Text("This permanently removes \(pendingDeletionProfileName)’s website data, history, permissions, download records, and saved passwords.")
        }
        .task {
            if request.startsCreatingProfile {
                nameFieldIsFocused = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Profiles")
                    .font(.title3.weight(.semibold))
                Text("Create and manage separate browsing identities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var profileList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                if selection == .newProfile {
                    HStack(spacing: 10) {
                        ProfileManagementAvatar(
                            name: displayDraftName,
                            colorHex: draftColorHex,
                            size: 30
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayDraftName)
                                .lineLimit(1)
                            Text("Not saved")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(ProfileEditorSelection.newProfile)
                }

                ForEach(store.persistentProfiles) { profile in
                    ProfileManagementRow(
                        profile: profile,
                        spaceCount: spaces(for: profile.id).count
                    )
                    .tag(ProfileEditorSelection.profile(profile.id))
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selection) { _, newSelection in
                loadDraft(for: newSelection)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    beginNewProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New profile")

                Button {
                    prepareSelectedProfileForDeletion()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(!selectedProfileCanBeDeleted || isDeletingProfile)
                .help(profileDeletionHelp)

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .newProfile:
            profileEditor(profile: nil)
        case .profile(let profileID):
            if let profile = store.persistentProfiles.first(where: { $0.id == profileID }) {
                profileEditor(profile: profile)
            } else {
                unavailableSelection
            }
        case nil:
            unavailableSelection
        }
    }

    private var unavailableSelection: some View {
        ContentUnavailableView(
            "Select a Profile",
            systemImage: "person.crop.circle",
            description: Text("Choose a profile to view or edit its details.")
        )
    }

    private func profileEditor(profile: BrowserProfile?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                editorIdentityHeader(profile: profile)

                profileIdentitySection

                if let profile {
                    assignedSpacesSection(profile: profile)
                    removalSection(profile: profile)
                } else {
                    newProfileExplanation
                }

                editorActions(profile: profile)
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.visible)
    }

    private func editorIdentityHeader(profile: BrowserProfile?) -> some View {
        HStack(spacing: 14) {
            ProfileManagementAvatar(
                name: displayDraftName,
                colorHex: draftColorHex,
                size: 58
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(profile == nil ? "New Profile" : displayDraftName)
                    .font(.title3.weight(.semibold))
                Text(editorSubtitle(profile: profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var profileIdentitySection: some View {
        ProfileManagementPanel(title: "Identity", systemName: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Profile Name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Profile name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldIsFocused)
                        .onSubmit {
                            saveSelectedProfileIfPossible()
                        }
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("Color")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 9) {
                        ForEach(Self.colorPresets, id: \.self) { colorHex in
                            ProfileColorPresetButton(
                                colorHex: colorHex,
                                isSelected: colorHex.caseInsensitiveCompare(draftColorHex) == .orderedSame
                            ) {
                                draftColorHex = colorHex
                            }
                        }

                        ColorPicker(
                            "Custom color",
                            selection: draftColorBinding,
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .frame(width: 24)
                    }
                }
            }
        }
    }

    private func assignedSpacesSection(profile: BrowserProfile) -> some View {
        let assignedSpaces = spaces(for: profile.id)

        return ProfileManagementPanel(title: "Spaces", systemName: "square.grid.2x2") {
            VStack(alignment: .leading, spacing: 12) {
                if assignedSpaces.isEmpty {
                    Text("No spaces use this profile yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(assignedSpaces) { space in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: space.colorHex))
                                .frame(width: 9, height: 9)

                            Text(space.name)
                                .lineLimit(1)

                            Spacer()

                            Button("Customize…") {
                                store.selectSpace(space.id)
                                _ = store.openSpaceCustomizer(for: space.id)
                                store.dismissProfileManager()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }

                Divider()

                Button {
                    let space = store.createSpace(name: "New Space", profileID: profile.id)
                    _ = store.openSpaceCustomizer(for: space.id)
                    store.dismissProfileManager()
                } label: {
                    Label("Create a Space with This Profile", systemImage: "plus")
                }
            }
        }
    }

    private var newProfileExplanation: some View {
        ProfileManagementPanel(title: "What Happens Next", systemName: "checkmark.shield") {
            Text("Creating this profile also creates and selects its first space. Website sessions in that space stay separate from your other profiles.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func removalSection(profile: BrowserProfile) -> some View {
        ProfileManagementPanel(title: "Remove Profile", systemName: "trash") {
            VStack(alignment: .leading, spacing: 10) {
                Text(removalExplanation(for: profile))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Remove Profile…", role: .destructive) {
                    prepareProfileForDeletion(profile)
                }
                .disabled(!store.canDeletePersistentProfile(profile.id) || isDeletingProfile)
            }
        }
    }

    private func editorActions(profile: BrowserProfile?) -> some View {
        HStack {
            if let profile {
                Button("Revert") {
                    loadDraft(for: .profile(profile.id))
                }
                .disabled(!hasChanges(to: profile))
            } else {
                Button("Cancel") {
                    cancelNewProfile()
                }
            }

            Spacer()

            Button(profile == nil ? "Create Profile" : "Save Changes") {
                if let profile {
                    save(profile: profile)
                } else {
                    createProfile()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!draftIsValid || (profile.map { !hasChanges(to: $0) } ?? false))
        }
    }

    private var selectedProfile: BrowserProfile? {
        guard case .profile(let profileID) = selection else {
            return nil
        }
        return store.persistentProfiles.first { $0.id == profileID }
    }

    private var selectedProfileCanBeDeleted: Bool {
        selectedProfile.map { store.canDeletePersistentProfile($0.id) } ?? false
    }

    private var profileDeletionHelp: String {
        guard let profile = selectedProfile else {
            return "Select a profile to remove"
        }
        return removalExplanation(for: profile)
    }

    private var draftIsValid: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayDraftName: String {
        let cleanedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedName.isEmpty ? "Untitled Profile" : cleanedName
    }

    private func editorSubtitle(profile: BrowserProfile?) -> String {
        guard let profile else {
            return "Nothing is created until you confirm."
        }
        return "Created \(profile.createdAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var draftColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: draftColorHex) },
            set: { color in
                if let colorHex = color.hexString {
                    draftColorHex = colorHex
                }
            }
        )
    }

    private var deletionConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletionProfileID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletionProfileID = nil
                }
            }
        )
    }

    private func spaces(for profileID: ProfileID) -> [BrowserSpace] {
        store.spaces.filter { $0.profileID == profileID }
    }

    private func beginNewProfile() {
        if case .profile(let profileID) = selection {
            lastExistingProfileID = profileID
        }
        selection = .newProfile
        draftName = store.suggestedPersistentProfileName
        draftColorHex = Self.suggestedColorHex(for: store.persistentProfiles.count)
        nameFieldIsFocused = true
    }

    private func cancelNewProfile() {
        let fallbackID = lastExistingProfileID.flatMap { candidateID in
            store.persistentProfiles.contains { $0.id == candidateID } ? candidateID : nil
        } ?? store.persistentProfiles.first?.id
        selection = fallbackID.map { .profile($0) }
    }

    private func loadDraft(for selection: ProfileEditorSelection?) {
        switch selection {
        case .profile(let profileID):
            guard let profile = store.persistentProfiles.first(where: { $0.id == profileID }) else {
                return
            }
            lastExistingProfileID = profileID
            draftName = profile.name
            draftColorHex = profile.colorHex
        case .newProfile:
            break
        case nil:
            draftName = ""
            draftColorHex = Self.colorPresets[0]
        }
    }

    private func createProfile() {
        guard draftIsValid else {
            return
        }
        let result = store.createPersistentProfileWithInitialSpace(
            name: draftName,
            colorHex: draftColorHex
        )
        store.publishStatusMessage("Profile “\(result.profile.name)” and its first space were created.")
        lastExistingProfileID = result.profile.id
        selection = .profile(result.profile.id)
        loadDraft(for: selection)
    }

    private func save(profile: BrowserProfile) {
        guard store.updatePersistentProfile(
            profile.id,
            name: draftName,
            colorHex: draftColorHex
        ) else {
            return
        }
        loadDraft(for: .profile(profile.id))
        store.publishStatusMessage("Profile changes saved.")
    }

    private func saveSelectedProfileIfPossible() {
        switch selection {
        case .newProfile:
            createProfile()
        case .profile(let profileID):
            guard let profile = store.persistentProfiles.first(where: { $0.id == profileID }),
                  hasChanges(to: profile) else {
                return
            }
            save(profile: profile)
        case nil:
            break
        }
    }

    private func hasChanges(to profile: BrowserProfile) -> Bool {
        profile.name != draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            || profile.colorHex.caseInsensitiveCompare(draftColorHex) != .orderedSame
    }

    private func removalExplanation(for profile: BrowserProfile) -> String {
        let assignedSpaceCount = spaces(for: profile.id).count
        if store.persistentProfiles.count <= 1 {
            return "The only remaining profile cannot be removed."
        }
        if assignedSpaceCount > 0 {
            let noun = assignedSpaceCount == 1 ? "space" : "spaces"
            return "Move this profile’s \(assignedSpaceCount) \(noun) to another profile before removing it."
        }
        if store.downloads.contains(where: { $0.profileID == profile.id && $0.state.isActive }) {
            return "Wait for this profile’s active downloads to finish before removing it."
        }
        return "This permanently removes the profile and its browsing data."
    }

    private func prepareSelectedProfileForDeletion() {
        guard let selectedProfile else {
            return
        }
        prepareProfileForDeletion(selectedProfile)
    }

    private func prepareProfileForDeletion(_ profile: BrowserProfile) {
        guard store.canDeletePersistentProfile(profile.id) else {
            return
        }
        pendingDeletionProfileName = profile.name
        pendingDeletionProfileID = profile.id
    }

    private func removePendingProfile() {
        guard let profileID = pendingDeletionProfileID else {
            return
        }
        pendingDeletionProfileID = nil
        isDeletingProfile = true
        Task { @MainActor in
            let didDelete = await store.deletePersistentProfile(profileID)
            isDeletingProfile = false
            guard didDelete else {
                return
            }
            let fallbackID = store.persistentProfiles.first?.id
            selection = fallbackID.map { .profile($0) }
            loadDraft(for: selection)
        }
    }

    private static func suggestedColorHex(for profileCount: Int) -> String {
        colorPresets[profileCount % colorPresets.count]
    }
}

private struct ProfileManagementRow: View {
    let profile: BrowserProfile
    let spaceCount: Int

    var body: some View {
        HStack(spacing: 10) {
            ProfileManagementAvatar(name: profile.name, colorHex: profile.colorHex, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .lineLimit(1)
                Text(spaceCount == 1 ? "1 space" : "\(spaceCount) spaces")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ProfileManagementAvatar: View {
    let name: String
    let colorHex: String
    let size: CGFloat

    var body: some View {
        let color = Color(hex: colorHex)

        ZStack {
            Circle()
                .fill(color.gradient)

            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.35), lineWidth: 0.8)
        }
        .accessibilityHidden(true)
    }

    private var initial: String {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedName.first.map { String($0).uppercased() } ?? "P"
    }
}

private struct ProfileColorPresetButton: View {
    let colorHex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.55), lineWidth: 1)
                }
                .padding(3)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colorHex)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ProfileManagementPanel<Content: View>: View {
    let title: String
    let systemName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemName)
                .font(.subheadline.weight(.semibold))

            content
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.28), lineWidth: 0.5)
        }
    }
}
