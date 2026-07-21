import Foundation
import Security

public struct PasswordCredentialCandidate: Equatable, Sendable {
    public static let maximumUsernameLength = 512
    public static let maximumPasswordLength = 4096
    public static let maximumPageTitleLength = 256

    public var origin: URL
    public var username: String
    public var password: String
    public var pageTitle: String?

    public init?(
        originURL: URL,
        username: String,
        password: String,
        pageTitle: String? = nil
    ) {
        guard let origin = Self.normalizedSecureOrigin(from: originURL) else {
            return nil
        }

        let cleanedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPassword = password.trimmingCharacters(in: .newlines)
        guard !cleanedUsername.isEmpty,
              !cleanedPassword.isEmpty,
              cleanedUsername.count <= Self.maximumUsernameLength,
              cleanedPassword.count <= Self.maximumPasswordLength else {
            return nil
        }

        self.origin = origin
        self.username = cleanedUsername
        self.password = cleanedPassword
        self.pageTitle = Self.normalizedPageTitle(pageTitle)
    }

    public init?(messageBody: Any, fallbackUsername: String? = nil) {
        let body = messageBody as? [String: Any]
            ?? (messageBody as? NSDictionary) as? [String: Any]

        guard let originString = Self.string(from: body?["origin"]),
              let originURL = URL(string: originString),
              let password = Self.string(from: body?["password"]) else {
            return nil
        }
        let postedUsername = Self.string(from: body?["username"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let username = postedUsername?.isEmpty == false ? postedUsername : fallbackUsername

        self.init(
            originURL: originURL,
            username: username ?? "",
            password: password,
            pageTitle: Self.string(from: body?["pageTitle"])
        )
    }

    public var displayHost: String {
        Self.displayHost(for: origin)
    }

    public static func normalizedSecureOrigin(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        guard scheme == "https" || (scheme == "http" && isLoopbackHost(host)) else {
            return nil
        }

        components.scheme = scheme
        components.host = host
        if (scheme == "https" && components.port == 443)
            || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil

        return components.url
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
    }

    public static func displayHost(for origin: URL) -> String {
        guard let components = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              let host = components.host,
              !host.isEmpty else {
            return origin.host(percentEncoded: false) ?? "this site"
        }

        if let port = components.port {
            return "\(host):\(port)"
        }

        return host
    }

    private static func string(from value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSString:
            return value as String
        default:
            return nil
        }
    }

    private static func normalizedPageTitle(_ pageTitle: String?) -> String? {
        guard let pageTitle else {
            return nil
        }

        let cleanedTitle = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            return nil
        }

        if cleanedTitle.count <= maximumPageTitleLength {
            return cleanedTitle
        }

        return String(cleanedTitle.prefix(maximumPageTitleLength))
    }
}

public struct PasswordSaveRequest: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var profileID: ProfileID
    public var origin: URL
    public var username: String
    public var password: String
    public var pageTitle: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        candidate: PasswordCredentialCandidate,
        profileID: ProfileID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.origin = candidate.origin
        self.username = candidate.username
        self.password = candidate.password
        self.pageTitle = candidate.pageTitle
        self.createdAt = createdAt
    }

    public var displayHost: String {
        PasswordCredentialCandidate.displayHost(for: origin)
    }

    public var confirmationTitle: String {
        "Save Password?"
    }

    public var confirmationMessage: String {
        "Save the password for \(username) on \(displayHost) in the local macOS Keychain?"
    }

    public var confirmButtonTitle: String {
        "Save Password"
    }

    public var pendingMessage: String {
        "Password save is waiting for confirmation."
    }

    public var savedMessage: String {
        "Password saved for \(displayHost)."
    }

    public var cancelledMessage: String {
        "Password was not saved."
    }
}

public struct SavedPasswordCredential: Equatable, Sendable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct SavedPasswordAccount: Identifiable, Equatable, Sendable {
    public var profileID: ProfileID
    public var origin: URL
    public var username: String

    public init(profileID: ProfileID, origin: URL, username: String) {
        self.profileID = profileID
        self.origin = origin
        self.username = username
    }

    public var id: String {
        "\(profileID.uuidString)|\(origin.absoluteString)|\(username)"
    }

    public var displayHost: String {
        PasswordCredentialCandidate.displayHost(for: origin)
    }
}

public enum PasswordCredentialStoreError: Error, Equatable {
    case passwordEncodingFailed
    case keychainStatus(OSStatus)
}

public struct PasswordCredentialReadOptions: Equatable, Sendable {
    public var allowsKeychainPrompt: Bool

    public init(allowsKeychainPrompt: Bool = true) {
        self.allowsKeychainPrompt = allowsKeychainPrompt
    }

    public static let userInitiated = PasswordCredentialReadOptions(allowsKeychainPrompt: true)
    public static let nonInteractive = PasswordCredentialReadOptions(allowsKeychainPrompt: false)
}

public protocol PasswordCredentialPersisting: AnyObject {
    func save(_ request: PasswordSaveRequest) throws
    func deleteCredentials(for profileID: ProfileID) throws
    func savedCredentials(
        for origin: URL,
        profileID: ProfileID,
        options: PasswordCredentialReadOptions
    ) throws -> [SavedPasswordCredential]
    func savedAccounts(for profileID: ProfileID) throws -> [SavedPasswordAccount]
}

public extension PasswordCredentialPersisting {
    func savedCredentials(for origin: URL, profileID: ProfileID) throws -> [SavedPasswordCredential] {
        try savedCredentials(for: origin, profileID: profileID, options: .userInitiated)
    }
}

public final class KeychainPasswordCredentialStore: PasswordCredentialPersisting {
    public static let defaultServicePrefix = "BareBrowser.WebsitePasswords"
    public static let legacyServicePrefixes = ["MeridianBrowser.WebsitePasswords"]

    private let servicePrefix: String
    private let legacyServicePrefixes: [String]
    private let keychainLabelPrefix = "Bare Browser password for "
    private let keychainDescription = "Website password"

    public init(
        servicePrefix: String = KeychainPasswordCredentialStore.defaultServicePrefix,
        legacyServicePrefixes: [String] = KeychainPasswordCredentialStore.legacyServicePrefixes
    ) {
        self.servicePrefix = servicePrefix
        self.legacyServicePrefixes = legacyServicePrefixes.filter { $0 != servicePrefix }
    }

    public convenience init(servicePrefix: String) {
        self.init(
            servicePrefix: servicePrefix,
            legacyServicePrefixes: KeychainPasswordCredentialStore.legacyServicePrefixes
        )
    }

    public func save(_ request: PasswordSaveRequest) throws {
        guard let passwordData = request.password.data(using: .utf8) else {
            throw PasswordCredentialStoreError.passwordEncodingFailed
        }

        migrateLegacyItemIfNeeded(for: request)
        let query = keychainQuery(for: request)
        let displayHost = request.displayHost
        let updateAttributes: [String: Any] = [
            kSecValueData as String: passwordData,
            kSecAttrLabel as String: keychainLabel(for: displayHost),
            kSecAttrDescription as String: keychainDescription,
            kSecAttrComment as String: request.origin.absoluteString
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            let replacementStatus = replacePasswordItem(
                existingQuery: query,
                replacementQuery: query,
                passwordData: passwordData,
                displayHost: displayHost,
                origin: request.origin
            )
            if case let .failed(status) = replacementStatus {
                throw PasswordCredentialStoreError.keychainStatus(status)
            }
            return
        case errSecItemNotFound:
            let addStatus = addPasswordItem(
                query: query,
                passwordData: passwordData,
                displayHost: displayHost,
                origin: request.origin
            )
            guard addStatus == errSecSuccess else {
                throw PasswordCredentialStoreError.keychainStatus(addStatus)
            }
        default:
            throw PasswordCredentialStoreError.keychainStatus(updateStatus)
        }
    }

    public func savedCredentials(
        for origin: URL,
        profileID: ProfileID,
        options: PasswordCredentialReadOptions
    ) throws -> [SavedPasswordCredential] {
        guard let normalizedOrigin = PasswordCredentialCandidate.normalizedSecureOrigin(from: origin) else {
            return []
        }

        let accountPrefix = "\(normalizedOrigin.absoluteString)\n"
        var credentials: [SavedPasswordCredential] = []
        var seenUsernames = Set<String>()
        for serviceName in serviceNames(for: profileID) {
            let items = try keychainItems(forServiceName: serviceName)
            for item in items {
                guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(accountPrefix) else {
                    continue
                }

                let username = String(account.dropFirst(accountPrefix.count))
                guard !username.isEmpty,
                      !seenUsernames.contains(username) else {
                    continue
                }
                guard let passwordData = try passwordData(
                    forAccount: account,
                    serviceName: serviceName,
                    allowsKeychainPrompt: options.allowsKeychainPrompt
                ),
                      let password = String(data: passwordData, encoding: .utf8),
                      !password.isEmpty else {
                    continue
                }
                if options.allowsKeychainPrompt {
                    repairPasswordItemAfterApprovedRead(
                        forAccount: account,
                        serviceName: serviceName,
                        profileID: profileID,
                        origin: normalizedOrigin,
                        passwordData: passwordData
                    )
                }

                seenUsernames.insert(username)
                credentials.append(SavedPasswordCredential(username: username, password: password))
            }
        }

        return credentials.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    public func savedAccounts(for profileID: ProfileID) throws -> [SavedPasswordAccount] {
        var accounts: [SavedPasswordAccount] = []
        var seenAccountKeys = Set<String>()
        for serviceName in serviceNames(for: profileID) {
            let items = try keychainItems(forServiceName: serviceName)
            for item in items {
                guard let accountName = item[kSecAttrAccount as String] as? String,
                      let separatorIndex = accountName.firstIndex(of: "\n") else {
                    continue
                }

                let originString = String(accountName[..<separatorIndex])
                let usernameStartIndex = accountName.index(after: separatorIndex)
                let username = String(accountName[usernameStartIndex...])
                guard let originURL = URL(string: originString),
                      let origin = PasswordCredentialCandidate.normalizedSecureOrigin(from: originURL),
                      !username.isEmpty else {
                    continue
                }
                let accountKey = "\(origin.absoluteString)\n\(username)"
                guard !seenAccountKeys.contains(accountKey) else {
                    continue
                }

                seenAccountKeys.insert(accountKey)
                accounts.append(SavedPasswordAccount(profileID: profileID, origin: origin, username: username))
            }
        }

        return accounts.sorted { lhs, rhs in
            let hostOrder = lhs.displayHost.localizedCaseInsensitiveCompare(rhs.displayHost)
            if hostOrder != .orderedSame {
                return hostOrder == .orderedAscending
            }

            return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
        }
    }

    public func deleteCredentials(for profileID: ProfileID) throws {
        for serviceName in serviceNames(for: profileID) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw PasswordCredentialStoreError.keychainStatus(status)
            }
        }
    }

    private func keychainQuery(for request: PasswordSaveRequest) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: request.profileID, prefix: servicePrefix),
            kSecAttrAccount as String: accountName(for: request),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    private func serviceNames(for profileID: ProfileID) -> [String] {
        ([servicePrefix] + legacyServicePrefixes).map { serviceName(for: profileID, prefix: $0) }
    }

    private func serviceName(for profileID: ProfileID, prefix: String) -> String {
        "\(prefix).\(profileID.uuidString)"
    }

    private func accountName(for request: PasswordSaveRequest) -> String {
        "\(request.origin.absoluteString)\n\(request.username)"
    }

    private func keychainLabel(for displayHost: String) -> String {
        "\(keychainLabelPrefix)\(displayHost)"
    }

    private enum PasswordItemReplacementStatus: Equatable {
        case replaced
        case skipped
        case failed(OSStatus)
    }

    private func addPasswordItem(
        query: [String: Any],
        passwordData: Data,
        displayHost: String,
        origin: URL
    ) -> OSStatus {
        var addAttributes = query
        addAttributes[kSecValueData as String] = passwordData
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addAttributes[kSecAttrLabel as String] = keychainLabel(for: displayHost)
        addAttributes[kSecAttrDescription as String] = keychainDescription
        addAttributes[kSecAttrComment as String] = origin.absoluteString

        if let access = currentApplicationAccess(for: displayHost) {
            addAttributes[kSecAttrAccess as String] = access
        }

        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
        guard addStatus != errSecSuccess,
              addAttributes[kSecAttrAccess as String] != nil else {
            return addStatus
        }

        addAttributes.removeValue(forKey: kSecAttrAccess as String)
        return SecItemAdd(addAttributes as CFDictionary, nil)
    }

    private func replacePasswordItem(
        existingQuery: [String: Any],
        replacementQuery: [String: Any],
        passwordData: Data,
        displayHost: String,
        origin: URL
    ) -> PasswordItemReplacementStatus {
        let deleteStatus = SecItemDelete(existingQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            return .skipped
        }

        let addStatus = addPasswordItem(
            query: replacementQuery,
            passwordData: passwordData,
            displayHost: displayHost,
            origin: origin
        )
        guard addStatus != errSecSuccess else {
            return .replaced
        }

        if replacementQuery[kSecAttrService as String] as? String
            != existingQuery[kSecAttrService as String] as? String {
            _ = addPasswordItem(
                query: existingQuery,
                passwordData: passwordData,
                displayHost: displayHost,
                origin: origin
            )
        }

        return .failed(addStatus)
    }

    private func currentApplicationAccess(for displayHost: String) -> SecAccess? {
        let descriptor = keychainLabel(for: displayHost) as CFString
        var access: SecAccess?

        if let trustedApplication = trustedApplicationForCurrentBundle() {
            let trustedList = [trustedApplication] as CFArray
            let status = SecAccessCreate(descriptor, trustedList, &access)
            if status == errSecSuccess {
                return access
            }
        }

        let status = SecAccessCreate(descriptor, nil, &access)
        return status == errSecSuccess ? access : nil
    }

    private func trustedApplicationForCurrentBundle() -> SecTrustedApplication? {
        let bundleURL = Bundle.main.bundleURL
        let trustedPath: String
        if bundleURL.pathExtension == "app" {
            trustedPath = bundleURL.path
        } else if let executablePath = Bundle.main.executablePath {
            trustedPath = executablePath
        } else {
            return nil
        }

        var trustedApplication: SecTrustedApplication?
        let status = trustedPath.withCString { path in
            SecTrustedApplicationCreateFromPath(path, &trustedApplication)
        }
        return status == errSecSuccess ? trustedApplication : nil
    }

    private func keychainItems(forServiceName serviceName: String) throws -> [[String: Any]] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: kCFBooleanTrue as Any
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return []
        default:
            throw PasswordCredentialStoreError.keychainStatus(status)
        }

        if let itemArray = result as? [[String: Any]] {
            return itemArray
        }
        if let item = result as? [String: Any] {
            return [item]
        }

        return []
    }

    @discardableResult
    private func updateDisplayMetadataIfNeeded(
        forAccount account: String,
        serviceName: String,
        profileID: ProfileID,
        origin: URL
    ) -> String {
        let displayHost = PasswordCredentialCandidate.displayHost(for: origin)
        let currentServiceName = self.serviceName(for: profileID, prefix: servicePrefix)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let displayAttributes: [String: Any] = [
            kSecAttrLabel as String: keychainLabel(for: displayHost),
            kSecAttrDescription as String: keychainDescription,
            kSecAttrComment as String: origin.absoluteString
        ]
        _ = SecItemUpdate(query as CFDictionary, displayAttributes as CFDictionary)

        guard serviceName != currentServiceName else {
            return currentServiceName
        }

        let serviceUpdateAttributes: [String: Any] = [
            kSecAttrService as String: currentServiceName,
            kSecAttrLabel as String: keychainLabel(for: displayHost),
            kSecAttrDescription as String: keychainDescription,
            kSecAttrComment as String: origin.absoluteString
        ]
        let serviceUpdateStatus = SecItemUpdate(
            query as CFDictionary,
            serviceUpdateAttributes as CFDictionary
        )
        return serviceUpdateStatus == errSecSuccess ? currentServiceName : serviceName
    }

    private func repairPasswordItemAfterApprovedRead(
        forAccount account: String,
        serviceName: String,
        profileID: ProfileID,
        origin: URL,
        passwordData: Data
    ) {
        let currentServiceName = self.serviceName(for: profileID, prefix: servicePrefix)
        let displayHost = PasswordCredentialCandidate.displayHost(for: origin)
        let existingQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        let replacementQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: currentServiceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        let replacementStatus = replacePasswordItem(
            existingQuery: existingQuery,
            replacementQuery: replacementQuery,
            passwordData: passwordData,
            displayHost: displayHost,
            origin: origin
        )
        if replacementStatus == .skipped {
            _ = updateDisplayMetadataIfNeeded(
                forAccount: account,
                serviceName: serviceName,
                profileID: profileID,
                origin: origin
            )
        }
    }

    private func migrateLegacyItemIfNeeded(for request: PasswordSaveRequest) {
        for legacyPrefix in legacyServicePrefixes {
            _ = updateDisplayMetadataIfNeeded(
                forAccount: accountName(for: request),
                serviceName: serviceName(for: request.profileID, prefix: legacyPrefix),
                profileID: request.profileID,
                origin: request.origin
            )
        }
    }

    private func passwordData(
        forAccount account: String,
        serviceName: String,
        allowsKeychainPrompt: Bool
    ) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: kCFBooleanTrue as Any
        ]
        if !allowsKeychainPrompt {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw PasswordCredentialStoreError.keychainStatus(status)
        }
    }
}
