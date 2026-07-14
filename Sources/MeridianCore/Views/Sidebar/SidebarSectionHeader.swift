import SwiftUI

public struct SidebarSectionHeader: View {
    private let title: String
    private let symbolName: String

    public init(title: String, symbolName: String) {
        self.title = title
        self.symbolName = symbolName
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.top, 2)
        .padding(.horizontal, 4)
    }
}
