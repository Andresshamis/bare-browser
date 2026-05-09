import Foundation

public enum SitePermissionKind: String, CaseIterable, Codable, Sendable {
    case camera
    case microphone
    case cameraAndMicrophone
    case geolocation
    case notifications
    case autoplay
    case popupWindow

    public var displayName: String {
        switch self {
        case .camera:
            "camera"
        case .microphone:
            "microphone"
        case .cameraAndMicrophone:
            "camera and microphone"
        case .geolocation:
            "location"
        case .notifications:
            "notifications"
        case .autoplay:
            "autoplay"
        case .popupWindow:
            "pop-up windows"
        }
    }
}

public enum SitePermissionDecision: String, Codable, Sendable {
    case ask
    case allow
    case deny
}

public enum SitePermissionSupport: String, Codable, Sendable {
    case webKitPermissionDelegate
    case webKitUIDelegate
    case webKitConfiguration
    case unsupported
}

public struct SitePermissionOrigin: Hashable, Codable, Sendable {
    public var scheme: String
    public var host: String
    public var port: Int?

    public init?(url: URL) {
        self.init(
            scheme: url.scheme,
            host: url.host(percentEncoded: false),
            port: url.port
        )
    }

    public init?(scheme: String?, host: String?, port: Int?) {
        guard let scheme = scheme?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let host = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !scheme.isEmpty,
              !host.isEmpty else {
            return nil
        }

        self.scheme = scheme
        self.host = host
        self.port = port.flatMap { $0 > 0 ? $0 : nil }
    }

    public var displayString: String {
        guard let port else {
            return host
        }
        return "\(host):\(port)"
    }

    public var serializedOrigin: String {
        let renderedHost = host.contains(":") ? "[\(host)]" : host
        guard let port else {
            return "\(scheme)://\(renderedHost)"
        }
        return "\(scheme)://\(renderedHost):\(port)"
    }
}

public struct SitePermissionRequest: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: SitePermissionKind
    public var origin: SitePermissionOrigin
    public var profileID: ProfileID
    public var isEphemeralProfile: Bool
    public var requestedAt: Date

    public init(
        id: UUID = UUID(),
        kind: SitePermissionKind,
        origin: SitePermissionOrigin,
        profileID: ProfileID,
        isEphemeralProfile: Bool,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.origin = origin
        self.profileID = profileID
        self.isEphemeralProfile = isEphemeralProfile
        self.requestedAt = requestedAt
    }

    public var promptMessage: String {
        "\(origin.displayString) wants to use \(kind.displayName)."
    }
}

public struct SitePermissionSetting: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var kind: SitePermissionKind
    public var origin: SitePermissionOrigin
    public var profileID: ProfileID
    public var decision: SitePermissionDecision
    public var persistsBeyondSession: Bool
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: SitePermissionKind,
        origin: SitePermissionOrigin,
        profileID: ProfileID,
        decision: SitePermissionDecision,
        persistsBeyondSession: Bool,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.origin = origin
        self.profileID = profileID
        self.decision = decision
        self.persistsBeyondSession = persistsBeyondSession
        self.updatedAt = updatedAt
    }

    public func matches(_ request: SitePermissionRequest) -> Bool {
        kind == request.kind
            && origin == request.origin
            && profileID == request.profileID
    }
}

public struct SitePermissionPolicy: Sendable {
    public enum Evaluation: Equatable, Sendable {
        case allow
        case ask
        case deny(reason: String)
    }

    public init() {}

    public func support(for kind: SitePermissionKind) -> SitePermissionSupport {
        switch kind {
        case .camera, .microphone, .cameraAndMicrophone:
            .webKitPermissionDelegate
        case .popupWindow:
            .webKitUIDelegate
        case .autoplay:
            .webKitConfiguration
        case .geolocation, .notifications:
            .unsupported
        }
    }

    public func defaultDecision(for kind: SitePermissionKind) -> SitePermissionDecision {
        switch support(for: kind) {
        case .webKitPermissionDelegate, .webKitUIDelegate:
            .ask
        case .webKitConfiguration, .unsupported:
            .deny
        }
    }

    public func evaluation(
        for request: SitePermissionRequest,
        settings: [SitePermissionSetting]
    ) -> Evaluation {
        if let setting = settings.last(where: { $0.matches(request) }) {
            return evaluation(for: setting.decision, kind: request.kind)
        }

        return evaluation(for: defaultDecision(for: request.kind), kind: request.kind)
    }

    public func evaluation(
        for decision: SitePermissionDecision,
        kind: SitePermissionKind
    ) -> Evaluation {
        switch decision {
        case .allow:
            if support(for: kind) == .unsupported {
                return .deny(reason: unsupportedReason(for: kind))
            }
            return .allow
        case .ask:
            if support(for: kind) == .unsupported {
                return .deny(reason: unsupportedReason(for: kind))
            }
            if kind == .autoplay {
                return .deny(reason: "Autoplay requires a user gesture.")
            }
            return .ask
        case .deny:
            if support(for: kind) == .unsupported {
                return .deny(reason: unsupportedReason(for: kind))
            }
            return .deny(reason: "\(kind.displayName.capitalized) is blocked for this site.")
        }
    }

    public func setting(
        for request: SitePermissionRequest,
        decision: SitePermissionDecision,
        date: Date = Date()
    ) -> SitePermissionSetting? {
        guard decision != .ask else {
            return nil
        }

        return SitePermissionSetting(
            kind: request.kind,
            origin: request.origin,
            profileID: request.profileID,
            decision: decision,
            persistsBeyondSession: !request.isEphemeralProfile,
            updatedAt: date
        )
    }

    public var requiresUserActionForAutoplay: Bool {
        defaultDecision(for: .autoplay) == .deny
    }

    private func unsupportedReason(for kind: SitePermissionKind) -> String {
        "\(kind.displayName.capitalized) permissions are not supported by Meridian on this WebKit version."
    }
}
