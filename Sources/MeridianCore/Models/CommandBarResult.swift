import Foundation

public enum CommandBarResult: Identifiable, Equatable, Sendable {
    case openTab(BrowserTab)
    case history(BrowserHistoryEntry)

    public var id: String {
        switch self {
        case .openTab(let tab):
            "tab-\(tab.id.uuidString)"
        case .history(let entry):
            "history-\(entry.id.uuidString)"
        }
    }

    public var title: String {
        switch self {
        case .openTab(let tab):
            tab.title
        case .history(let entry):
            entry.title
        }
    }

    public var subtitle: String {
        switch self {
        case .openTab(let tab):
            tab.url?.host(percentEncoded: false) ?? ""
        case .history(let entry):
            entry.displayHost
        }
    }

    public var symbolName: String {
        switch self {
        case .openTab:
            "globe"
        case .history:
            "clock.arrow.circlepath"
        }
    }

    public var kindLabel: String {
        switch self {
        case .openTab:
            "Tab"
        case .history:
            "History"
        }
    }
}
