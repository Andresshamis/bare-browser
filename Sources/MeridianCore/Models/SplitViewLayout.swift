import Foundation

public struct SplitViewLayout: Identifiable, Hashable, Codable, Sendable {
    public var id: SplitViewID
    public var tabIDs: [TabID]
    public var fractions: [Double]
    public var orientation: SplitOrientation

    public init(
        id: SplitViewID = UUID(),
        tabIDs: [TabID],
        fractions: [Double],
        orientation: SplitOrientation = .horizontal
    ) {
        self.id = id
        self.tabIDs = tabIDs
        self.fractions = fractions
        self.orientation = orientation
    }
}

public enum SplitOrientation: String, Codable, Sendable {
    case horizontal
    case vertical
}
