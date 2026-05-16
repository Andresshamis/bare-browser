import Foundation

public struct AddressResolver: Sendable {
    public enum Resolution: Equatable, Sendable {
        case url(URL)
        case search(URL, query: String)
        case empty
    }

    public var searchURL: @Sendable (String) -> URL

    public init(searchURL: @escaping @Sendable (String) -> URL = AddressResolver.googleSearchURL) {
        self.searchURL = searchURL
    }

    public func resolve(_ rawInput: String) -> Resolution {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return .empty
        }

        if let url = URL(string: input), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return .url(url)
        }

        if looksLikeLocalhost(input), let url = URL(string: "http://\(input)") {
            return .url(url)
        }

        if looksLikeHost(input), let url = URL(string: "https://\(input)") {
            return .url(url)
        }

        return .search(searchURL(input), query: input)
    }

    private func looksLikeHost(_ input: String) -> Bool {
        guard !input.contains(" ") else {
            return false
        }

        if input.contains(".") {
            return true
        }

        if input.contains(":") {
            return true
        }

        return false
    }

    private func looksLikeLocalhost(_ input: String) -> Bool {
        input == "localhost"
            || input.hasPrefix("localhost:")
            || input.hasPrefix("127.0.0.1")
            || input.hasPrefix("[::1]")
    }

    public static func googleSearchURL(for query: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        return components.url!
    }
}
