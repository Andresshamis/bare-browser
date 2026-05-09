import Foundation

public protocol LocalHistoryPersisting: AnyObject {
    func loadHistory(profiles: [BrowserProfile]) -> LocalHistoryPersistenceLoadResult
    func saveHistory(_ entries: [BrowserHistoryEntry], profiles: [BrowserProfile]) throws
}
