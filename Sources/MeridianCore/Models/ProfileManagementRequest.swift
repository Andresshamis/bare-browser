import Foundation

public struct ProfileManagementRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var initialProfileID: ProfileID?
    public var startsCreatingProfile: Bool

    public init(
        id: UUID = UUID(),
        initialProfileID: ProfileID? = nil,
        startsCreatingProfile: Bool = false
    ) {
        self.id = id
        self.initialProfileID = initialProfileID
        self.startsCreatingProfile = startsCreatingProfile
    }
}
