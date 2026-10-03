import Foundation

/// Sync state shares the library's atomic JSON transaction, including storage moves.
nonisolated final class SDSyncManifestStore {
    private let db: VideoDatabase
    init(db: VideoDatabase = VideoDatabase()) { self.db = db }
    var exists: Bool { db.library.sdSyncManifest != nil }
    func load() throws -> SDSyncManifest {
        if let error = db.loadError { throw error }
        return db.library.sdSyncManifest ?? SDSyncManifest()
    }
    func save(_ manifest: SDSyncManifest) throws {
        var updated = db.library
        var manifest = manifest
        manifest.updatedAt = Date()
        updated.sdSyncManifest = manifest
        try db.replaceLibrary(updated)
    }
    @discardableResult
    func removeEntries(recordID: UUID) throws -> [SDSyncManifestEntry] {
        guard exists else { return [] }
        var manifest = try load()
        let removed = manifest.entries.filter { $0.recordID == recordID }
        manifest.entries.removeAll { $0.recordID == recordID }
        try save(manifest)
        return removed
    }
    func reset() throws {
        var updated = db.library
        updated.sdSyncManifest = nil
        try db.replaceLibrary(updated)
    }
}
