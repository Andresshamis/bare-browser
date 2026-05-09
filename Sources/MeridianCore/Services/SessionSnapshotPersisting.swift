import Foundation

public protocol SessionSnapshotPersisting: AnyObject {
    func saveSnapshot(_ snapshot: BrowserSessionSnapshot, fallback: BrowserSessionSnapshot) throws
}
