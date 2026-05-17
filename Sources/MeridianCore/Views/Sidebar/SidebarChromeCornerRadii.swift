import SwiftUI

struct SidebarChromeCornerRadii: Equatable, Sendable {
    var topLeading: CGFloat
    var topTrailing: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat

    static func resolved(
        isPinned: Bool,
        edge: SidebarRevealEdge,
        radius: CGFloat
    ) -> SidebarChromeCornerRadii {
        guard isPinned else {
            return SidebarChromeCornerRadii(
                topLeading: radius,
                topTrailing: radius,
                bottomLeading: radius,
                bottomTrailing: radius
            )
        }

        switch edge {
        case .left:
            return SidebarChromeCornerRadii(
                topLeading: radius,
                topTrailing: 0,
                bottomLeading: radius,
                bottomTrailing: 0
            )
        case .right:
            return SidebarChromeCornerRadii(
                topLeading: 0,
                topTrailing: radius,
                bottomLeading: 0,
                bottomTrailing: radius
            )
        }
    }

    var maximumRadius: CGFloat {
        max(max(topLeading, topTrailing), max(bottomLeading, bottomTrailing))
    }

    var rectangleCornerRadii: RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: topLeading,
            bottomLeading: bottomLeading,
            bottomTrailing: bottomTrailing,
            topTrailing: topTrailing
        )
    }
}
