import Foundation

@main
struct StorageTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw StorageError("TEST FAILED: " + message) }
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("storage-tests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let legacy = root.appendingPathComponent("video_index.json")
        let db = VideoDatabase(databaseURL: legacy)
        var library = db.library
        library.mediaRootPath = root.appendingPathComponent("OldMedia").path
        try db.replaceLibrary(library)
        try db.prepareStorage()
        let media = db.mediaRootURL.appendingPathComponent("Media/test/Original/movie.mp4")
        try fm.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original video".utf8).write(to: media)
        let item = try db.createItem(sources: [], metadata: MediaMetadata(title: "Edited title", summary: "Keep this metadata", tags: ["favorite"]), assets: [MediaAsset(role: .master, path: media.path, formatIdentifier: "mp4", storageKind: .managed)])
        let priorBackup = try db.backup()
        let stale = VideoDatabase(databaseURL: legacy)
        let target = root.appendingPathComponent("Portable")
        let report = try StorageMover().move(db: db, to: target)
        try check(db.databaseURL == target.appendingPathComponent("video_index.json"), "catalog moved")
        try check(fm.fileExists(atPath: report.backupURL.path), "reported backup exists")
        try check(fm.fileExists(atPath: target.appendingPathComponent("Backups/" + priorBackup.lastPathComponent).path), "prior backups copied")
        try check(!fm.fileExists(atPath: media.path), "verified source removed")
        try check(fm.fileExists(atPath: legacy.path), "legacy recovery catalog retained")
        var rejected = false
        do { try stale.save() } catch { rejected = true }
        try check(rejected, "stale writer blocked")
        stale.reload()
        try check(stale.databaseURL == db.databaseURL, "existing reader follows move")
        try check(stale.record(recordID: item.id)?.metadata.summary == "Keep this metadata", "metadata retained")
        let copied = root.appendingPathComponent("CopiedToNewComputer")
        try fm.copyItem(at: target, to: copied)
        let portable = VideoDatabase(databaseURL: copied.appendingPathComponent("video_index.json"))
        try check(portable.loadError == nil, "copied catalog opens")
        try check(portable.record(recordID: item.id)?.assets.first?.path == copied.appendingPathComponent("Media/test/Original/movie.mp4").path, "paths rebase after folder copy")
        let conflictRoot = root.appendingPathComponent("Conflict")
        try MediaStorage(root: conflictRoot, libraryID: db.library.libraryID).prepare(allowCreate: true)
        let conflict = conflictRoot.appendingPathComponent("video_index.json")
        try Data("existing catalog".utf8).write(to: conflict)
        rejected = false
        do { _ = try StorageMover().move(db: db, to: conflictRoot) } catch { rejected = true }
        try check(rejected, "existing catalog rejected")
        let preserved = try String(contentsOf: conflict, encoding: .utf8)
        try check(preserved == "existing catalog", "existing catalog untouched")
        try check(fm.fileExists(atPath: db.record(recordID: item.id)!.assets[0].path), "failed move retains source")
        try fm.removeItem(at: target)
        let missing = VideoDatabase(databaseURL: legacy)
        try check(missing.loadError != nil, "missing destination never creates empty library")
        let support = root.appendingPathComponent("Support")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let startup = support.appendingPathComponent("video_index.json")
        let seed = VideoDatabase(databaseURL: startup)
        var seedLibrary = seed.library
        seedLibrary.mediaRootPath = root.appendingPathComponent("Initial").path
        try seed.replaceLibrary(seedLibrary)
        _ = try seed.createItem(sources: [], metadata: MediaMetadata(title: "Recovered metadata"))
        let appDB = VideoDatabase(databaseURL: startup, bootstrapFromProject: true)
        try check(appDB.loadError == nil, "startup migration succeeds")
        try check(appDB.databaseURL == root.appendingPathComponent("Initial/video_index.json"), "startup catalog in selected folder")
        try check(appDB.allRecords().first?.metadata.title == "Recovered metadata", "startup migration preserves metadata")
        let worker = VideoDatabase(databaseURL: appDB.databaseURL)
        _ = try StorageMover().move(db: worker, to: root.appendingPathComponent("MovedAgain"))
        appDB.reload()
        try fm.removeItem(at: root.appendingPathComponent("Initial"))
        let restarted = VideoDatabase(databaseURL: startup, bootstrapFromProject: true)
        try check(restarted.loadError == nil && restarted.allRecords().count == 1, "startup pointer follows move without old folder")
        let catalog = restarted.databaseURL
        let pointer = startup.appendingPathExtension("location")
        let originalDate = Date(timeIntervalSince1970: 1_600_000_000)
        try fm.setAttributes([.modificationDate: originalDate], ofItemAtPath: catalog.path)
        try fm.setAttributes([.modificationDate: originalDate], ofItemAtPath: pointer.path)
        let backups = catalog.deletingLastPathComponent().appendingPathComponent("Backups")
        let backupsBefore = try fm.contentsOfDirectory(atPath: backups.path).sorted()
        let normalLaunch = VideoDatabase(databaseURL: startup, bootstrapFromProject: true)
        normalLaunch.reload()
        try check(normalLaunch.loadError == nil, "normal launch succeeds")
        let catalogDate = try fm.attributesOfItem(atPath: catalog.path)[.modificationDate] as? Date
        let pointerDate = try fm.attributesOfItem(atPath: pointer.path)[.modificationDate] as? Date
        let backupsAfter = try fm.contentsOfDirectory(atPath: backups.path).sorted()
        try check(catalogDate == originalDate && pointerDate == originalDate, "normal launch and refresh do not rewrite catalog or pointer")
        try check(backupsBefore == backupsAfter, "normal launch creates no migration backups")
        print("PASS: catalog migration, backups, metadata, redirects, stale writers, portable paths, conflicts, missing storage")
    }
}
