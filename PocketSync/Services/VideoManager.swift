//
//  VideoManager.swift
//  PocketSync
//
//  Created by Marco Ortiz Torres on 3/8/26.
//

import Foundation
import Combine

@MainActor
final class VideoManager: ObservableObject {
    @Published var logOutput: String = ""
    @Published var records: [VideoRecord] = []
    @Published var isProcessing: Bool = false
    @Published var needsFirstTimeSDSync: Bool = true
    @Published var pendingMetadataRecordIDs: [UUID] = []

    @Published private(set) var mediaStoragePath = ""
    @Published private(set) var libraryInformationPath = ""
    @Published private(set) var storageNeedsOrganization = false
    @Published private(set) var storageError: String?
    @Published private(set) var isMovingStorage = false
    @Published private(set) var isPluginImportRunning = false
    private var pluginTask: Task<Void, Never>?

    private let db: VideoDatabase
    private var databaseURL: URL { db.databaseURL }
    private let syncManifestStore: SDSyncManifestStore

    init(db: VideoDatabase) {
        self.db = db
        self.syncManifestStore = SDSyncManifestStore(db: db)
        refresh()
    }

    convenience init() {
        self.init(db: VideoDatabase())
    }

    func refresh() {
        db.reload()
        records = db.allRecords()
            .sorted { $0.updatedAt > $1.updatedAt }
        needsFirstTimeSDSync = !syncManifestStore.exists
        mediaStoragePath = db.mediaRootURL.path
        libraryInformationPath = db.databaseURL.path
        storageNeedsOrganization = records.flatMap(\.assets).contains {
            $0.isManagedByPocketSync && $0.role != .deviceCopy && MediaStorage.relativePath(URL(fileURLWithPath: $0.path), under: db.mediaRootURL) == nil
        }
        storageError = db.loadError?.localizedDescription
        if storageError == nil && db.library.storageInitialized {
            do { try db.storage.prepare(allowCreate: false) }
            catch { storageError = error.localizedDescription }
        }
    }

    func appendLog(_ text: String) {
        if !logOutput.isEmpty {
            logOutput += "\n"
        }

        logOutput += text
    }

    func clearLog() {
        logOutput = ""
    }

    func importLocalMedia(urls: [URL], mode: LocalMediaImportMode) {
        guard !urls.isEmpty, !isProcessing else { return }

        isProcessing = true
        appendLog("Importing local video files...")
        let databaseURL = databaseURL

        Task.detached(priority: .userInitiated) {
            let importer = LocalMediaImporter(db: VideoDatabase(databaseURL: databaseURL))
            let report = importer.importURLs(urls, mode: mode)

            await MainActor.run {
                self.appendLog("Imported \(report.importedCount) video\(report.importedCount == 1 ? "" : "s").")
                if report.skippedCount > 0 {
                    self.appendLog("Skipped \(report.skippedCount) duplicate or unsupported item\(report.skippedCount == 1 ? "" : "s").")
                }
                for failure in report.failures {
                    self.appendLog("Could not import \(URL(fileURLWithPath: failure.path).lastPathComponent): \(failure.message)")
                }
                self.refresh()
                self.pendingMetadataRecordIDs.append(contentsOf: report.importedRecordIDs)
                self.isProcessing = false
            }
        }
    }

    func importFromPlugin(_ plugin: InstalledPlugin, locator: String) {
        guard !isProcessing else { return }
        let input = locator.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if records.contains(where: { record in
            record.sources.contains { $0.providerIdentifier == plugin.id && $0.locator == input }
        }) {
            appendLog("This source is already in the library.")
            return
        }
        isProcessing = true
        isPluginImportRunning = true
        appendLog("Importing with \(plugin.manifest.name)…")
        let databaseURL = databaseURL
        pluginTask = Task.detached(priority: .userInitiated) {
            let workerDB = VideoDatabase(databaseURL: databaseURL)
            let storage = workerDB.storage
            let service = PluginService(outputRoot: storage.stagingRoot)
            var pendingCandidate: PluginMediaCandidate?
            var adoptedID: UUID?
            var saved = false
            do {
                try workerDB.prepareStorage()
                let candidate = try service.importMedia(using: plugin, locator: input, isCancelled: { Task.isCancelled })
                pendingCandidate = candidate
                try Task.checkCancellation()
                let id = UUID()
                adoptedID = id
                let adopted = try storage.adopt(candidate, id: id)
                try Task.checkCancellation()
                let record = try workerDB.createItem(id: id, sources: adopted.sources, metadata: adopted.metadata, assets: adopted.assets)
                saved = true
                service.discard(candidate)
                pendingCandidate = nil
                await MainActor.run {
                    self.isPluginImportRunning = false
                    self.appendLog("Imported: \(record.displayName). Creating the QuickTime copy…")
                    self.refresh()
                }
                // After the original is saved, conversion failure must never discard it.
                do {
                    try VideoPipeline(db: workerDB).convertQuickTimeStep(recordID: id)
                    await MainActor.run { self.appendLog("QuickTime copy is ready.") }
                } catch {
                    await MainActor.run {
                        self.appendLog("The original and metadata are saved. QuickTime conversion failed: \(error.localizedDescription). Use Mac conversion to retry.")
                    }
                }
            } catch {
                if let pendingCandidate { service.discard(pendingCandidate) }
                if !saved, let adoptedID { try? FileManager.default.removeItem(at: storage.itemDirectory(adoptedID)) }
                await MainActor.run {
                    self.appendLog(error is CancellationError ? "Plugin import cancelled." : "Plugin import failed: \(error.localizedDescription)")
                }
            }
            await MainActor.run { self.finishPluginImport() }
        }
    }

    func moveStorage(to root: URL) {
        guard !isProcessing else { return }
        isProcessing = true
        isMovingStorage = true
        appendLog("Moving managed media. Originals and conversions will be verified before the library location changes…")
        let databaseURL = databaseURL
        Task.detached(priority: .userInitiated) {
            do {
                let report = try StorageMover().move(db: VideoDatabase(databaseURL: databaseURL), to: root)
                await MainActor.run {
                    self.appendLog("Moved \(report.movedFiles) managed files. Library backup: \(report.backupURL.path)")
                    for path in report.retainedSources { self.appendLog("Kept an original copy for safety: \(path)") }
                }
            } catch {
                await MainActor.run { self.appendLog("Storage move failed: \(error.localizedDescription)") }
            }
            await MainActor.run {
                self.refresh()
                self.isProcessing = false
                self.isMovingStorage = false
            }
        }
    }

    func cancelPluginImport() {
        pluginTask?.cancel()
    }

    private func finishPluginImport() {
        refresh()
        isProcessing = false
        isPluginImportRunning = false
        pluginTask = nil
    }

    func saveMetadata(recordID: UUID, metadata: MediaMetadata, linkedWebURL: URL?) throws {
        guard !isProcessing else { throw StorageError("Wait for the current operation before editing metadata.") }
        guard var record = db.record(recordID: recordID) else {
            throw VideoDatabaseError.recordNotFound
        }

        record.metadata = metadata
        if let linkedWebURL {
            if let index = record.sources.firstIndex(where: { $0.kind == .webLink }) {
                record.sources[index].locator = linkedWebURL.absoluteString
            } else {
                record.sources.append(MediaSource(kind: .webLink, locator: linkedWebURL.absoluteString))
            }
        }
        try db.upsert(record)
        refresh()
    }

    func finishPendingMetadata(recordID: UUID) {
        pendingMetadataRecordIDs.removeAll { $0 == recordID }
    }

    func convertSelectedToMac(recordID: UUID?) {
        guard let recordID else {
            appendLog("No video selected for Mac conversion.")
            return
        }

        guard !isProcessing else { return }

        isProcessing = true
        appendLog("Starting Mac/QuickTime conversion...")

        let databaseURL = databaseURL

        Task.detached(priority: .userInitiated) {
            let pipeline = VideoPipeline(db: VideoDatabase(databaseURL: databaseURL))

            do {
                try pipeline.convertQuickTimeStep(recordID: recordID, force: true)

                await MainActor.run {
                    self.appendLog("Finished Mac/QuickTime conversion.")
                    self.refresh()
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.appendLog("Mac conversion error: \(error.localizedDescription)")
                    self.appendLog("Full error: \(String(describing: error))")
                    self.refresh()
                    self.isProcessing = false
                }
            }
        }
    }

    func convertSelectedToAVI(recordID: UUID?) {
        guard let recordID else {
            appendLog("No video selected for AVI conversion.")
            return
        }

        guard !isProcessing else { return }

        isProcessing = true
        appendLog("Starting AVI conversion...")

        let databaseURL = databaseURL

        Task.detached(priority: .userInitiated) {
            let pipeline = VideoPipeline(db: VideoDatabase(databaseURL: databaseURL))

            do {
                try pipeline.convertAVIStep(recordID: recordID, force: true)

                await MainActor.run {
                    self.appendLog("Finished AVI conversion.")
                    self.refresh()
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.appendLog("AVI convert failed: \(error.localizedDescription)")
                    self.appendLog("Full error: \(String(describing: error))")
                    self.refresh()
                    self.isProcessing = false
                }
            }
        }
    }

    func firstTimeSyncSDCard() {
        guard !isProcessing else { return }

        isProcessing = true
        appendLog("Starting first-time SD sync...")

        let databaseURL = databaseURL

        Task.detached(priority: .userInitiated) {
            let syncService = SDCardSyncService(db: VideoDatabase(databaseURL: databaseURL))

            do {
                let report = try syncService.syncAllPending(options: .firstTime)

                await MainActor.run {
                    self.appendSyncReport(report)
                    self.refresh()
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.appendLog("First-time sync failed: \(error.localizedDescription)")
                    self.appendLog("Full error: \(String(describing: error))")
                    self.refresh()
                    self.isProcessing = false
                }
            }
        }
    }

    func syncSDCard() {
        if needsFirstTimeSDSync {
            firstTimeSyncSDCard()
        } else {
            syncAllPendingToSDCard()
        }
    }

    func syncAllPendingToSDCard() {
        guard !isProcessing else { return }

        isProcessing = true
        appendLog("Starting SD sync...")

        let databaseURL = databaseURL

        Task.detached(priority: .userInitiated) {
            let syncService = SDCardSyncService(db: VideoDatabase(databaseURL: databaseURL))

            do {
                let report = try syncService.syncAllPending(options: .standard)

                await MainActor.run {
                    self.appendSyncReport(report)
                    self.refresh()
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.appendLog("Sync failed: \(error.localizedDescription)")
                    self.appendLog("Full error: \(String(describing: error))")
                    self.refresh()
                    self.isProcessing = false
                }
            }
        }
    }

    func syncSelectedToSDCard(recordID: UUID?) {
        guard let recordID else {
            appendLog("No video selected for SD sync.")
            return
        }

        guard !isProcessing else { return }

        isProcessing = true
        appendLog("Starting selected SD sync...")

        let databaseURL = databaseURL

        Task.detached(priority: .userInitiated) {
            let syncService = SDCardSyncService(db: VideoDatabase(databaseURL: databaseURL))

            do {
                let report = try syncService.sync(recordID: recordID, options: .standard)

                await MainActor.run {
                    self.appendSyncReport(report)
                    self.refresh()
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.appendLog("Selected sync failed: \(error.localizedDescription)")
                    self.appendLog("Full error: \(String(describing: error))")
                    self.refresh()
                    self.isProcessing = false
                }
            }
        }
    }

    func toggleSyncIgnored(recordID: UUID?) {
        guard !isProcessing else { return }
        guard let recordID else {
            appendLog("No video selected for sync ignore.")
            return
        }

        guard let record = records.first(where: { $0.id == recordID }) else {
            appendLog("Selected video is no longer in the library.")
            return
        }

        do {
            let shouldIgnore = record.isIgnoredForSync != true
            try db.updateSyncIgnored(recordID: recordID, isIgnored: shouldIgnore)
            appendLog("\(shouldIgnore ? "Ignored for SD sync" : "Allowed for SD sync"): \(record.displayName)")
            refresh()
        } catch {
            appendLog("Could not update sync ignore: \(error.localizedDescription)")
            appendLog("Full error: \(String(describing: error))")
            refresh()
        }
    }

    func toggleFavorite(recordID: UUID?) {
        guard !isProcessing else { return }
        guard let recordID,
              let record = records.first(where: { $0.id == recordID }) else {
            appendLog("No video selected for favorite.")
            return
        }

        do {
            try db.updateFavorite(recordID: recordID, isFavorite: !record.isFavorite)
            refresh()
        } catch {
            appendLog("Could not update favorite: \(error.localizedDescription)")
            refresh()
        }
    }

    func deleteVideo(recordID: UUID?) {
        guard let recordID else {
            appendLog("No video selected to delete.")
            return
        }

        guard !isProcessing else { return }

        isProcessing = true
        appendLog("Deleting selected video...")

        let databaseURL = databaseURL

        Task.detached(priority: .userInitiated) {
            let db = VideoDatabase(databaseURL: databaseURL)
            let manifestStore = SDSyncManifestStore(db: db)
            let fileManager = FileManager.default

            do {
                guard let record = db.record(recordID: recordID) else {
                    throw VideoDatabaseError.recordNotFound
                }

                let removedManifestEntries = try manifestStore.removeEntries(recordID: recordID)
                var pathsToDelete = Set<String>()

                record.assets
                    .filter(\.isManagedByPocketSync)
                    .map(\.path)
                    .forEach { pathsToDelete.insert($0) }

                record.syncedLocations?
                    .map(\.path)
                    .forEach { pathsToDelete.insert($0) }

                for entry in removedManifestEntries {
                    pathsToDelete.insert(entry.path)

                    let localCachePath = URL(
                        fileURLWithPath: AppPaths.forMediaRoot(db.mediaRootURL).localSDVideoFolder,
                        isDirectory: true
                    )
                    .appendingPathComponent(entry.fileName)
                    .path
                    pathsToDelete.insert(localCachePath)
                }

                for path in pathsToDelete {
                    if fileManager.fileExists(atPath: path) {
                        try fileManager.removeItem(atPath: path)
                    }
                }

                try db.deleteRecord(recordID: recordID)

                await MainActor.run {
                    self.appendLog("Deleted: \(record.displayName)")
                    self.refresh()
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.appendLog("Delete failed: \(error.localizedDescription)")
                    self.appendLog("Full error: \(String(describing: error))")
                    self.refresh()
                    self.isProcessing = false
                }
            }
        }
    }

    func reconcileSDCardOnly() {
        guard !isProcessing else { return }

        isProcessing = true
        appendLog("Reconciling SD card...")

        let databaseURL = databaseURL

        Task.detached(priority: .userInitiated) {
            let syncService = SDCardSyncService(db: VideoDatabase(databaseURL: databaseURL))

            do {
                let report = try syncService.reconcileOnly(options: .standard)

                await MainActor.run {
                    self.appendSyncReport(report)
                    self.refresh()
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.appendLog("Reconcile failed: \(error.localizedDescription)")
                    self.appendLog("Full error: \(String(describing: error))")
                    self.refresh()
                    self.isProcessing = false
                }
            }
        }
    }

    private func appendSyncReport(_ report: SDSyncReport) {
        appendLog("SD sync finished.")
        appendLog("Scanned: \(report.scannedFileCount), system: \(report.systemFileCount), PocketSync: \(report.pocketSyncFileCount), synced: \(report.syncedRecordCount), skipped: \(report.skippedRecordCount), highest HNI: \(report.highestHNIIndex)")

        for message in report.messages {
            appendLog(message)
        }
    }

}
