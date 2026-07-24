import SwiftUI

public struct SidebarSectionHeader: View {
    private let title: String
    private let symbolName: String

    public init(title: String, symbolName: String) {
        self.title = title
        self.symbolName = symbolName
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.top, SidebarLayoutMetrics.sectionHeaderTopInset)
        .padding(.bottom, SidebarLayoutMetrics.sectionHeaderBottomInset)
        .padding(.horizontal, SidebarLayoutMetrics.sectionHeaderHorizontalInset)
    }
}
