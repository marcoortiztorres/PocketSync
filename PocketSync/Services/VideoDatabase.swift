//
//  VideoDatabase.swift
//  PocketSync
//
//  Created by Marco Ortiz Torres on 3/8/26.
//

import Foundation
import Combine
import Darwin

nonisolated enum PocketSyncPaths {
    static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Models
            .deletingLastPathComponent() // PocketSync (inner source folder)
            .deletingLastPathComponent() // PocketSync (project root)
    }

    static var databaseURL: URL {
        applicationSupportURL.appendingPathComponent("video_index.json")
    }

    static var defaultMediaRoot: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        return movies.appendingPathComponent("PocketSync", isDirectory: true)
    }

    static var applicationSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let identifier = Bundle.main.bundleIdentifier ?? "PocketSync2"
        return base.appendingPathComponent(identifier, isDirectory: true)
    }
}

nonisolated final class VideoDatabase: ObservableObject {
    @Published private(set) var library: VideoLibrary = VideoLibrary()

    private(set) var databaseURL: URL
    private let startupCatalogURL: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var loadedData: Data?
    private(set) var loadError: Error?
    var mediaRootURL: URL { URL(fileURLWithPath: library.mediaRootPath, isDirectory: true) }
    var storage: MediaStorage { MediaStorage(root: mediaRootURL, libraryID: library.libraryID) }

    convenience init(filename: String = "video_index.json") {
        self.init(databaseURL: PocketSyncPaths.applicationSupportURL.appendingPathComponent(filename), bootstrapFromProject: true)
    }

    init(databaseURL: URL, bootstrapFromProject: Bool = false) {
        self.databaseURL = databaseURL
        self.startupCatalogURL = bootstrapFromProject ? databaseURL : nil

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        if bootstrapFromProject {
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                #if DEBUG
                // Upgrade only this checkout's current library; never read the legacy project.
                let existing = PocketSyncPaths.projectRoot.appendingPathComponent(databaseURL.lastPathComponent)
                if !fm.fileExists(atPath: databaseURL.path), fm.fileExists(atPath: existing.path) {
                    try fm.copyItem(at: existing, to: databaseURL)
                }
                #endif
            } catch { loadError = error; return }
        }
        load()
        #if DEBUG
        if bootstrapFromProject, loadError == nil, library.sdSyncManifest == nil,
           let data = try? Data(contentsOf: PocketSyncPaths.projectRoot.appendingPathComponent("sd_sync_manifest.json")) {
            do {
                library.sdSyncManifest = try decoder.decode(SDSyncManifest.self, from: data)
                try save()
            } catch { loadError = error }
        }
        #endif
        if bootstrapFromProject, loadError == nil,
           self.databaseURL.standardizedFileURL != mediaRootURL.appendingPathComponent("video_index.json").standardizedFileURL {
            do {
                try prepareStorage()
                try relocateLibrary(library, to: mediaRootURL.appendingPathComponent("video_index.json"))
            } catch { loadError = error }
        }
    }

    private func locationFile(for catalog: URL) -> URL {
        catalog.appendingPathExtension("location")
    }

    func load() {
        do {
            let fm = FileManager.default
            var visited = Set<String>()
            while fm.fileExists(atPath: locationFile(for: databaseURL).path) {
                guard visited.insert(databaseURL.path).inserted else {
                    throw StorageError("The library location contains a circular redirect.")
                }
                let path = try String(contentsOf: locationFile(for: databaseURL), encoding: .utf8)
                guard path.hasPrefix("/") else { throw StorageError("Invalid library location.") }
                let destination = URL(fileURLWithPath: path)
                guard fm.fileExists(atPath: destination.path) else {
                    throw StorageError("The selected library is unavailable. Reconnect its drive before continuing.")
                }
                databaseURL = destination
                loadedData = nil
            }
            if !fm.fileExists(atPath: databaseURL.path) {
                // An existing database disappearing must not silently reset the library.
                guard loadedData == nil else { throw StorageError("The library information file is missing.") }
                loadError = nil
                try save()
                return
            }
            let data = try Data(contentsOf: databaseURL)
            var decoded = try decoder.decode(VideoLibrary.self, from: data)
            let root = databaseURL.deletingLastPathComponent()
            let marker = root.appendingPathComponent(".pocketsync-library-id")
            if fm.fileExists(atPath: marker.path) {
                guard try String(contentsOf: marker, encoding: .utf8) == decoded.libraryID.uuidString else {
                    throw StorageError("The catalog and media folder belong to different libraries.")
                }
                decoded.rebaseManagedPaths(to: root)
            }
            library = decoded
            loadedData = data
            if let startupCatalogURL, startupCatalogURL != databaseURL {
                let pointer = locationFile(for: startupCatalogURL)
                let destination = Data(databaseURL.path.utf8)
                if try Data(contentsOf: pointer) != destination {
                    try destination.write(to: pointer, options: .atomic)
                }
            }
            loadError = nil
        } catch {
            loadError = error
        }
    }

    func save() throws { try replaceLibrary(library) }

    /// Compare-and-swap prevents a second window or stale worker overwriting a move.
    func replaceLibrary(_ updated: VideoLibrary) throws {
        if let loadError { throw loadError }
        guard !FileManager.default.fileExists(atPath: locationFile(for: databaseURL).path) else {
            throw StorageError("The library has moved. Refresh before saving changes.")
        }
        let lockPath = databaseURL.path + ".lock"
        let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw StorageError("Cannot lock the library information file.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw StorageError("The library is busy in another operation. Try again shortly.")
        }
        defer { flock(descriptor, LOCK_UN) }
        do {
            guard !FileManager.default.fileExists(atPath: locationFile(for: databaseURL).path) else {
                throw StorageError("The library has moved. Refresh before saving changes.")
            }
            let current = FileManager.default.fileExists(atPath: databaseURL.path) ? try Data(contentsOf: databaseURL) : nil
            guard current == loadedData else { throw StorageError("The library changed in another window. Refresh and try again.") }
            let data = try encoder.encode(updated)
            try data.write(to: databaseURL, options: [.atomic])
            library = updated
            loadedData = data
        } catch {
            if let loadedData, let original = try? decoder.decode(VideoLibrary.self, from: loadedData) { library = original }
            throw error
        }
    }

    /// Publish the destination before redirecting readers. The old catalog remains
    /// a recovery copy; stale writers are rejected by its redirect and source lock.
    func relocateLibrary(_ updated: VideoLibrary, to destination: URL) throws {
        if destination.standardizedFileURL == databaseURL.standardizedFileURL {
            try replaceLibrary(updated)
            return
        }
        if let loadError { throw loadError }
        let fm = FileManager.default
        let source = databaseURL
        let descriptor = open(source.path + ".lock", O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw StorageError("Cannot lock the library information file.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw StorageError("The library is busy. Try again shortly.") }
        defer { flock(descriptor, LOCK_UN) }
        guard !fm.fileExists(atPath: locationFile(for: source).path),
              try Data(contentsOf: source) == loadedData else {
            throw StorageError("The library changed. Refresh before moving it.")
        }
        guard !fm.fileExists(atPath: destination.path),
              !fm.fileExists(atPath: locationFile(for: destination).path) else {
            throw StorageError("The destination already contains a catalog. No existing catalog will be overwritten.")
        }
        let backupRoot = destination.deletingLastPathComponent().appendingPathComponent("Backups")
        try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let oldBackups = source.deletingLastPathComponent().appendingPathComponent("Backups")
        if oldBackups.standardizedFileURL != backupRoot.standardizedFileURL,
           fm.fileExists(atPath: oldBackups.path) {
            for file in try fm.contentsOfDirectory(at: oldBackups, includingPropertiesForKeys: [.isRegularFileKey]) {
                guard file.pathExtension == "json", try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                let target = backupRoot.appendingPathComponent(file.lastPathComponent)
                if fm.fileExists(atPath: target.path) {
                    guard try Data(contentsOf: file) == Data(contentsOf: target) else {
                        throw StorageError("A different backup already exists at the destination.")
                    }
                } else { try fm.copyItem(at: file, to: target) }
            }
        }
        try (loadedData ?? encoder.encode(library)).write(
            to: backupRoot.appendingPathComponent("library-\(UUID().uuidString).json"), options: .atomic)
        let data = try encoder.encode(updated)
        try data.write(to: destination, options: .withoutOverwriting)
        do {
            guard try Data(contentsOf: destination) == data else { throw StorageError("Catalog verification failed.") }
            try Data(destination.path.utf8).write(to: locationFile(for: source), options: .atomic)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
        databaseURL = destination
        library = updated
        loadedData = data
    }

    func prepareStorage() throws {
        if let loadError { throw loadError }
        try storage.prepare(allowCreate: !library.storageInitialized)
        if !library.storageInitialized {
            var updated = library
            updated.storageInitialized = true
            try replaceLibrary(updated)
        }
    }

    func backup() throws -> URL {
        if let loadError { throw loadError }
        let folder = databaseURL.deletingLastPathComponent().appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("library-\(UUID().uuidString).json")
        try (loadedData ?? encoder.encode(library)).write(to: url, options: [.atomic])
        return url
    }

    func reload() {
        load()
    }

    func record(forVideoID videoID: String) -> VideoRecord? {
        library.record(forVideoID: videoID)
    }

    func record(forSourceURL url: String) -> VideoRecord? {
        library.record(forSourceURL: url)
    }

    func record(videoID: String) -> VideoRecord? {
        library.record(forVideoID: videoID)
    }

    func record(recordID: UUID) -> VideoRecord? {
        library.records.first { $0.id == recordID }
    }

    var next3DSIndex: Int {
        library.next3DSIndex
    }

    func allRecords() -> [VideoRecord] {
        library.records
    }

    func setNext3DSIndex(_ nextIndex: Int) throws {
        library.next3DSIndex = max(nextIndex, 1)
        try save()
    }

    func upsert(_ record: VideoRecord) throws {
        var updated = record
        updated.updatedAt = Date()
        library.upsert(updated)
        try save()
    }

    func createRecord(
        sourceURL: String,
        extractor: String? = nil,
        extractorVideoID: String? = nil,
        webpageURL: String? = nil,
        title: String,
        uploader: String? = nil,
        channel: String? = nil,
        uploadDate: String? = nil,
        durationSeconds: Int? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        thumbnailURL: String? = nil
    ) throws -> VideoRecord {
        var sources = [
            MediaSource(
                kind: sourceURL.hasPrefix("http") ? .webLink : .localFile,
                locator: sourceURL,
                providerIdentifier: extractor,
                externalIdentifier: extractorVideoID
            )
        ]

        if let webpageURL, webpageURL != sourceURL {
            sources.append(
                MediaSource(
                    kind: .webLink,
                    locator: webpageURL,
                    providerIdentifier: extractor,
                    externalIdentifier: extractorVideoID
                )
            )
        }

        return try createItem(
            sources: sources,
            metadata: MediaMetadata(
                title: title,
                uploader: uploader,
                channel: channel,
                publishedDate: uploadDate,
                durationSeconds: durationSeconds,
                summary: description,
                tags: tags,
                thumbnailURL: thumbnailURL,
                origin: extractor == nil ? .user : .externalProvider,
                providerIdentifier: extractor,
                resolvedAt: extractor == nil ? nil : Date()
            )
        )
    }

    func createItem(
        id: UUID = UUID(),
        sources: [MediaSource],
        metadata: MediaMetadata,
        assets: [MediaAsset] = []
    ) throws -> MediaLibraryItem {
        let record = MediaLibraryItem(
            id: id,
            sources: sources,
            metadata: metadata,
            assets: assets
        )

        // Publish in-memory changes only after the record is persisted. In
        // particular, failed plugin imports must not retain a deleted asset path.
        var updatedLibrary = library
        updatedLibrary.upsert(record)
        try replaceLibrary(updatedLibrary)
        return record
    }

    func assignNext3DSFileName(to recordID: UUID) throws -> String {
        guard let index = library.records.firstIndex(where: { $0.id == recordID }) else {
            throw VideoDatabaseError.recordNotFound
        }

        if let existing = library.records[index].threeDSFileName {
            return existing
        }

        let nextName = library.next3DSFileName()
        library.records[index].threeDSFileName = nextName
        library.records[index].updatedAt = Date()
        try save()
        return nextName
    }

    func updateStatus(
        recordID: UUID,
        status: VideoStatus,
        errorMessage: String? = nil
    ) throws {
        guard let index = library.records.firstIndex(where: { $0.id == recordID }) else {
            throw VideoDatabaseError.recordNotFound
        }

        library.records[index].status = status
        library.records[index].errorMessage = errorMessage
        library.records[index].updatedAt = Date()
        try save()
    }

    func updateSyncIgnored(recordID: UUID, isIgnored: Bool) throws {
        guard let index = library.records.firstIndex(where: { $0.id == recordID }) else {
            throw VideoDatabaseError.recordNotFound
        }

        library.records[index].isIgnoredForSync = isIgnored
        library.records[index].updatedAt = Date()
        try save()
    }

    func updateFavorite(recordID: UUID, isFavorite: Bool) throws {
        guard let index = library.records.firstIndex(where: { $0.id == recordID }) else {
            throw VideoDatabaseError.recordNotFound
        }

        library.records[index].isFavorite = isFavorite
        library.records[index].updatedAt = Date()
        try save()
    }

    func updatePaths(
        recordID: UUID,
        highResPath: String? = nil,
        quickTimePath: String? = nil,
        aviPath: String? = nil,
        threeDSPath: String? = nil,
        syncedLocations: [SyncedLocation]? = nil
    ) throws {
        guard let index = library.records.firstIndex(where: { $0.id == recordID }) else {
            throw VideoDatabaseError.recordNotFound
        }

        if let highResPath {
            library.records[index].highResPath = highResPath
        }

        if let quickTimePath {
            library.records[index].quickTimePath = quickTimePath
        }

        if let aviPath {
            library.records[index].aviPath = aviPath
        }

        if let threeDSPath {
            library.records[index].threeDSPath = threeDSPath
        }

        if let syncedLocations {
            library.records[index].syncedLocations = syncedLocations
            library.records[index].lastSyncedAt = Date()
        }

        library.records[index].updatedAt = Date()
        try save()
    }

    func deleteRecord(recordID: UUID) throws {
        library.records.removeAll { $0.id == recordID }
        try save()
    }

    func hasRecord(videoID: String) -> Bool {
        library.record(forVideoID: videoID) != nil
    }

    func hasRecord(sourceURL: String) -> Bool {
        library.record(forSourceURL: sourceURL) != nil
    }
}

nonisolated enum VideoDatabaseError: Error, LocalizedError {
    case recordNotFound

    var errorDescription: String? {
        switch self {
        case .recordNotFound:
            return "The requested video record could not be found."
        }
    }
}
