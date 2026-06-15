import SwiftUI

struct StartPageSurfaceSnapshot: Equatable, Sendable {
    let spaceID: SpaceID
    let name: String
    let symbolName: String
    let colorHex: String
    let tintHex: String
    let profileName: String

    init?(space: BrowserSpace?, profiles: [BrowserProfile]) {
        guard let space else {
            return nil
        }

        let trimmedName = space.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.spaceID = space.id
        self.name = trimmedName.isEmpty ? "Untitled Space" : trimmedName
        self.symbolName = space.symbolName
        self.colorHex = space.colorHex
        self.tintHex = space.sidebarAppearance.tintHex(forSpaceColorHex: space.colorHex)
        self.profileName = profiles.first { $0.id == space.profileID }?.name ?? "Profile"
    }
}

public struct StartPageView: View {
    @ObservedObject private var store: BrowserStore

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        if let snapshot = StartPageSurfaceSnapshot(
            space: store.selectedSpace,
            profiles: store.profiles
        ) {
            StartPageSurface(snapshot: snapshot) {
                store.showCommandBar()
            } customizeSpace: {
                _ = store.openSpaceCustomizer(for: snapshot.spaceID)
            } createFolder: {
                _ = store.createFolder(name: "New Folder")
            }
        }
    }
}

struct StartPageSurface: View {
    let snapshot: StartPageSurfaceSnapshot
    let open: () -> Void
    let customizeSpace: () -> Void
    let createFolder: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var spaceHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(spaceTint.opacity(colorScheme == .dark ? 0.22 : 0.14))

                SpaceIconGlyph(
                    symbolName: snapshot.symbolName,
                    colorHex: snapshot.colorHex,
                    size: 54,
                    foregroundColor: .secondary
                )
            }
            .frame(width: 78, height: 78)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(spaceTint.opacity(0.30), lineWidth: 0.8)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(snapshot.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    metadataPill(snapshot.profileName, systemName: "person.crop.circle")
                    metadataPill("No tabs", systemName: "rectangle.stack")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            startAction(
                title: "Open",
                systemName: "magnifyingglass",
                isProminent: true
            ) {
                open()
            }

            startAction(
                title: "Customize",
                systemName: "slider.horizontal.3"
            ) {
                customizeSpace()
            }

            startAction(
                title: "New Folder",
                systemName: "folder.badge.plus"
            ) {
                createFolder()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            spaceHeader
            actionRow
        }
        .frame(maxWidth: 620, alignment: .center)
        .padding(.horizontal, 44)
        .padding(.vertical, 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(.background)
    }

    private func startAction(
        title: String,
        systemName: String,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.callout.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isProminent ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isProminent ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.10),
                            lineWidth: 0.7
                        )
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isProminent ? Color.primary : Color.secondary)
    }

    private func metadataPill(_ title: String, systemName: String) -> some View {
        Label(title, systemImage: systemName)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            }
    }

    private var spaceTint: Color {
        Color(hex: snapshot.tintHex)
    }
}
