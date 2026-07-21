import Foundation

public enum SessionPersistenceBoundary {
    public static func repairPersistentSnapshot(
        from snapshot: BrowserSessionSnapshot,
        fallback: BrowserSessionSnapshot
    ) -> SessionIntegrityRepairResult {
        SessionIntegrityRepair.repair(snapshot, fallback: fallback)
    }

    public static func persistentSnapshot(
        from snapshot: BrowserSessionSnapshot,
        fallback: BrowserSessionSnapshot
    ) -> BrowserSessionSnapshot {
        repairPersistentSnapshot(from: snapshot, fallback: fallback).snapshot
    }
}
