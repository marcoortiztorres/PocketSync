//
//  SDCardSyncService.swift
//  PocketSync
//

import Foundation

nonisolated struct SDCardSyncOptions: Hashable {
    var firstTimeSync: Bool = false
    var includeRemovedRecords: Bool = false
    var requireMountedSDCard: Bool = true
    var mirrorToLocalCache: Bool = true

    static let standard = SDCardSyncOptions()
    static let firstTime = SDCardSyncOptions(firstTimeSync: true)
}

nonisolated final class SDCardSyncService {
    private let db: VideoDatabase
    private let mounts: MountResolver
    private let manifestStore: SDSyncManifestStore
    private let fileManager: FileManager

    init(
        db: VideoDatabase,
        mounts: MountResolver? = nil,
        manifestStore: SDSyncManifestStore? = nil,
        fileManager: FileManager = .default
    ) {
        self.db = db
        self.mounts = mounts ?? MountResolver(appPaths: .forMediaRoot(db.mediaRootURL))
        self.manifestStore = manifestStore ?? SDSyncManifestStore(db: db)
        self.fileManager = fileManager
    }

    func syncAllPending(options: SDCardSyncOptions = .standard) throws -> SDSyncReport {
        let records = db.allRecords()
        let candidateIDs = records
            .filter { shouldAutoSync($0, includeRemovedRecords: options.includeRemovedRecords) }
            .map(\.id)

        return try sync(recordIDs: candidateIDs, options: options)
    }

    func sync(recordID: UUID, options: SDCardSyncOptions = .standard) throws -> SDSyncReport {
        try sync(recordIDs: [recordID], options: options)
    }

    func sync(recordIDs: [UUID], options: SDCardSyncOptions = .standard) throws -> SDSyncReport {
        try db.prepareStorage()
        let paths = try mounts.resolvePaths()

        if options.requireMountedSDCard && !paths.is3DSSDMounted {
            throw SDCardSyncError.sdCardNotMounted(paths.sdVideoRoot.path)
        }

        let scannedFiles = try scanDCIMFolder(paths.sdVideoRoot)
        let highestOnCard = highestHNIIndex(in: scannedFiles)
        let firstSync = options.firstTimeSync || !manifestStore.exists

        var manifest = firstSync
            ? SDSyncManifest(sdVideoRootPath: paths.sdVideoRoot.path)
            : try manifestStore.load()

        manifest.sdVideoRootPath = paths.sdVideoRoot.path

        var report = SDSyncReport(
            isFirstSync: firstSync,
            scannedFileCount: scannedFiles.count,
            systemFileCount: 0,
            pocketSyncFileCount: 0,
            newSystemFileCount: 0,
            missingPocketSyncFileCount: 0,
            changedPocketSyncFileCount: 0,
            syncedRecordCount: 0,
            skippedRecordCount: 0,
            highestHNIIndex: highestOnCard,
            messages: []
        )

        if firstSync {
            manifest.entries = scannedFiles.map { fingerprint in
                SDSyncManifestEntry(
                    origin: .system,
                    fileName: fingerprint.fileName,
                    path: fingerprint.path,
                    fileSize: fingerprint.fileSize,
                    modifiedAt: fingerprint.modifiedAt,
                    note: "Found on SD during first sync. Treated as 3DS/system-owned."
                )
            }
            report.newSystemFileCount = scannedFiles.count
            report.messages.append("First sync: marked \(scannedFiles.count) existing SD files as system-owned.")
        } else {
            try reconcileManifest(
                manifest: &manifest,
                scannedFiles: scannedFiles,
                report: &report,
                paths: paths,
                options: options
            )
        }

        let currentHighest = paths.is3DSSDMounted
            ? highestOnCard
            : max(highestOnCard, manifest.highestKnownHNIIndex)
        var nextIndex = currentHighest + 1

        let uniqueIDs = Array(Set(recordIDs))
        for recordID in uniqueIDs {
            guard var record = db.record(recordID: recordID) else {
                report.skippedRecordCount += 1
                report.messages.append("Skipped missing record: \(recordID.uuidString)")
                continue
            }

            guard shouldSyncExplicitly(record, includeRemovedRecords: options.includeRemovedRecords) else {
                report.skippedRecordCount += 1
                report.messages.append("Skipped \(record.displayName): not eligible for sync.")
                continue
            }

            if isAlreadyConfirmedOnSD(record, manifest: manifest, scannedFiles: scannedFiles) {
                report.skippedRecordCount += 1
                report.messages.append("Skipped \(record.displayName): already confirmed on SD.")
                continue
            }

            guard let aviPath = record.aviPath else {
                report.skippedRecordCount += 1
                report.messages.append("Skipped \(record.displayName): missing aviPath.")
                continue
            }

            let aviURL = URL(fileURLWithPath: aviPath)
            guard fileManager.fileExists(atPath: aviURL.path) else {
                report.skippedRecordCount += 1
                report.messages.append("Skipped \(record.displayName): AVI missing on disk.")
                continue
            }

            let targetName = nextFreeHNIName(
                startingAt: nextIndex,
                existingFiles: scannedFiles,
                manifest: manifest,
                includeManifestEntries: !paths.is3DSSDMounted
            )
            nextIndex = (hniNumber(in: targetName) ?? nextIndex) + 1

            let sdTargetURL = paths.sdVideoRoot.appendingPathComponent(targetName)

            if fileManager.fileExists(atPath: sdTargetURL.path) {
                throw SDCardSyncError.targetAlreadyExists(sdTargetURL.path)
            }

            try fileManager.copyItem(at: aviURL, to: sdTargetURL)

            if let uploadDate = record.uploadDate,
               let timestamp = AVIDatePatcher.timestamp(from: uploadDate) {
                try AVIDatePatcher.patch(aviURL: sdTargetURL, timestamp: timestamp)
            }

            let fingerprint = try fingerprint(for: sdTargetURL)

            if options.mirrorToLocalCache {
                try mirrorToLocalDCIM(source: sdTargetURL, fileName: targetName)
            }

            let entry = SDSyncManifestEntry(
                origin: .pocketSync,
                fileName: fingerprint.fileName,
                path: fingerprint.path,
                fileSize: fingerprint.fileSize,
                modifiedAt: fingerprint.modifiedAt,
                recordID: record.id,
                note: "Transferred by PocketSync."
            )
            manifest.entries.removeAll { $0.recordID == record.id && $0.origin == .pocketSync }
            manifest.entries.append(entry)

            let syncedLocations = [
                SyncedLocation(
                    kind: paths.is3DSSDMounted ? .threeDSSDCard : .localFallback,
                    fileName: targetName,
                    path: sdTargetURL.path,
                    syncedAt: Date()
                ),
                SyncedLocation(
                    kind: .localFallback,
                    fileName: aviURL.lastPathComponent,
                    path: aviURL.path,
                    syncedAt: Date()
                )
            ]

            record.threeDSFileName = targetName
            record.threeDSPath = sdTargetURL.path
            record.syncedLocations = syncedLocations
            record.lastSyncedAt = Date()
            record.status = .completed
            try db.upsert(record)

            report.syncedRecordCount += 1
            report.messages.append("Synced \(record.displayName) as \(targetName).")
        }

        manifest.highestKnownHNIIndex = max(highestHNIIndex(in: try scanDCIMFolder(paths.sdVideoRoot)), nextIndex - 1)
        try manifestStore.save(manifest)
        let nextDatabaseIndex = paths.is3DSSDMounted
            ? manifest.highestKnownHNIIndex + 1
            : max(db.next3DSIndex, manifest.highestKnownHNIIndex + 1)
        try db.setNext3DSIndex(nextDatabaseIndex)

        let finalManifest = try manifestStore.load()
        report.systemFileCount = finalManifest.entries.filter { $0.origin == .system }.count
        report.pocketSyncFileCount = finalManifest.entries.filter { $0.origin == .pocketSync }.count
        report.highestHNIIndex = finalManifest.highestKnownHNIIndex

        return report
    }

    func reconcileOnly(options: SDCardSyncOptions = .standard) throws -> SDSyncReport {
        try db.prepareStorage()
        let paths = try mounts.resolvePaths()

        if options.requireMountedSDCard && !paths.is3DSSDMounted {
            throw SDCardSyncError.sdCardNotMounted(paths.sdVideoRoot.path)
        }

        let scannedFiles = try scanDCIMFolder(paths.sdVideoRoot)
        let firstSync = options.firstTimeSync || !manifestStore.exists
        var manifest = firstSync ? SDSyncManifest(sdVideoRootPath: paths.sdVideoRoot.path) : try manifestStore.load()

        var report = SDSyncReport(
            isFirstSync: firstSync,
            scannedFileCount: scannedFiles.count,
            systemFileCount: 0,
            pocketSyncFileCount: 0,
            newSystemFileCount: 0,
            missingPocketSyncFileCount: 0,
            changedPocketSyncFileCount: 0,
            syncedRecordCount: 0,
            skippedRecordCount: 0,
            highestHNIIndex: highestHNIIndex(in: scannedFiles),
            messages: []
        )

        if firstSync {
            manifest.entries = scannedFiles.map { fingerprint in
                SDSyncManifestEntry(
                    origin: .system,
                    fileName: fingerprint.fileName,
                    path: fingerprint.path,
                    fileSize: fingerprint.fileSize,
                    modifiedAt: fingerprint.modifiedAt,
                    note: "Found on SD during first sync. Treated as 3DS/system-owned."
                )
            }
            report.newSystemFileCount = scannedFiles.count
            report.messages.append("First sync: marked \(scannedFiles.count) existing SD files as system-owned.")
        } else {
            try reconcileManifest(
                manifest: &manifest,
                scannedFiles: scannedFiles,
                report: &report,
                paths: paths,
                options: options
            )
        }

        manifest.sdVideoRootPath = paths.sdVideoRoot.path
        manifest.highestKnownHNIIndex = highestHNIIndex(in: scannedFiles)
        try manifestStore.save(manifest)
        let nextDatabaseIndex = paths.is3DSSDMounted
            ? manifest.highestKnownHNIIndex + 1
            : max(db.next3DSIndex, manifest.highestKnownHNIIndex + 1)
        try db.setNext3DSIndex(nextDatabaseIndex)

        let saved = try manifestStore.load()
        report.systemFileCount = saved.entries.filter { $0.origin == .system }.count
        report.pocketSyncFileCount = saved.entries.filter { $0.origin == .pocketSync }.count
        report.highestHNIIndex = saved.highestKnownHNIIndex

        return report
    }

    // MARK: Reconciliation

    private func reconcileManifest(
        manifest: inout SDSyncManifest,
        scannedFiles: [SDFileFingerprint],
        report: inout SDSyncReport,
        paths: ResolvedPaths,
        options: SDCardSyncOptions
    ) throws {
        let scannedByName = Dictionary(uniqueKeysWithValues: scannedFiles.map { ($0.fileName.uppercased(), $0) })
        var updatedEntries: [SDSyncManifestEntry] = []
        var knownNames = Set<String>()

        for var entry in manifest.entries {
            let key = entry.fileName.uppercased()
            knownNames.insert(key)

            guard let current = scannedByName[key] else {
                if entry.origin == .pocketSync {
                    report.missingPocketSyncFileCount += 1
                    try unlinkPocketSyncEntry(entry, reason: "Missing from SD card", paths: paths)
                    report.messages.append("PocketSync file removed from SD: \(entry.fileName). Marked record as removed from 3DS.")
                } else {
                    report.messages.append("System file removed from SD: \(entry.fileName). Removed from manifest.")
                }
                continue
            }

            if entry.origin == .pocketSync && !entry.hasSameIdentity(as: current) {
                report.changedPocketSyncFileCount += 1
                try unlinkPocketSyncEntry(entry, reason: "Changed on SD card", paths: paths)

                entry.origin = .system
                entry.recordID = nil
                entry.fileSize = current.fileSize
                entry.modifiedAt = current.modifiedAt
                entry.path = current.path
                entry.lastSeenAt = Date()
                entry.note = "Previously PocketSync-owned, but changed on SD. Converted to system-owned."
                updatedEntries.append(entry)
                report.messages.append("PocketSync file changed on SD: \(entry.fileName). Converted manifest entry to system-owned.")
                continue
            }

            entry.path = current.path
            entry.fileSize = current.fileSize
            entry.modifiedAt = current.modifiedAt
            entry.lastSeenAt = Date()
            updatedEntries.append(entry)
        }

        for fingerprint in scannedFiles where !knownNames.contains(fingerprint.fileName.uppercased()) {
            updatedEntries.append(
                SDSyncManifestEntry(
                    origin: .system,
                    fileName: fingerprint.fileName,
                    path: fingerprint.path,
                    fileSize: fingerprint.fileSize,
                    modifiedAt: fingerprint.modifiedAt,
                    note: "Detected after first sync. Treated as 3DS/system-owned."
                )
            )
            report.newSystemFileCount += 1
            report.messages.append("New system file detected on SD: \(fingerprint.fileName).")
        }

        manifest.entries = updatedEntries
    }

    private func unlinkPocketSyncEntry(_ entry: SDSyncManifestEntry, reason: String, paths: ResolvedPaths) throws {
        if let recordID = entry.recordID,
           var record = db.record(recordID: recordID) {
            record.threeDSPath = nil
            record.threeDSFileName = nil
            record.syncedLocations = record.syncedLocations?.filter { location in
                location.fileName.caseInsensitiveCompare(entry.fileName) != .orderedSame
            }
            record.lastSyncedAt = nil
            record.status = .removedFrom3DS
            record.errorMessage = reason
            try db.upsert(record)
        }

        let localCacheURL = URL(fileURLWithPath: mounts.appPaths.localSDVideoFolder, isDirectory: true)
            .appendingPathComponent(entry.fileName)
        if fileManager.fileExists(atPath: localCacheURL.path) {
            try? fileManager.removeItem(at: localCacheURL)
        }
    }

    // MARK: Scanning + naming

    private func scanDCIMFolder(_ folder: URL) throws -> [SDFileFingerprint] {
        guard fileManager.fileExists(atPath: folder.path) else {
            throw SDCardSyncError.sdVideoFolderMissing(folder.path)
        }

        let files = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return try files.compactMap { url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            guard hniNumber(in: url.lastPathComponent) != nil else { return nil }

            return SDFileFingerprint(
                fileName: url.lastPathComponent,
                path: url.path,
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate
            )
        }
        .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    private func highestHNIIndex(in files: [SDFileFingerprint]) -> Int {
        files.compactMap { hniNumber(in: $0.fileName) }.max() ?? 0
    }

    private func hniNumber(in fileName: String) -> Int? {
        let uppercased = fileName.uppercased()
        guard uppercased.hasPrefix("HNI_") else { return nil }

        let nameWithoutExtension = URL(fileURLWithPath: uppercased).deletingPathExtension().lastPathComponent
        let numberText = String(nameWithoutExtension.dropFirst(4))

        guard numberText.count == 4 else { return nil }
        return Int(numberText)
    }

    private func nextFreeHNIName(
        startingAt start: Int,
        existingFiles: [SDFileFingerprint],
        manifest: SDSyncManifest,
        includeManifestEntries: Bool
    ) -> String {
        var taken = Set(existingFiles.map { $0.fileName.uppercased() })
        if includeManifestEntries {
            taken.formUnion(manifest.entries.map { $0.fileName.uppercased() })
        }

        var index = max(start, 1)
        while true {
            let name = String(format: "HNI_%04d.AVI", index)
            if !taken.contains(name.uppercased()) {
                return name
            }
            index += 1
        }
    }

    private func fingerprint(for file: URL) throws -> SDFileFingerprint {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return SDFileFingerprint(
            fileName: file.lastPathComponent,
            path: file.path,
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate
        )
    }

    private func mirrorToLocalDCIM(source: URL, fileName: String) throws {
        let localFolder = URL(fileURLWithPath: mounts.appPaths.localSDVideoFolder, isDirectory: true)
        try fileManager.createDirectory(at: localFolder, withIntermediateDirectories: true)

        let destination = localFolder.appendingPathComponent(fileName)
        if source.standardizedFileURL == destination.standardizedFileURL { return }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: source, to: destination)
    }

    // MARK: Eligibility

    private func shouldAutoSync(_ record: VideoRecord, includeRemovedRecords: Bool) -> Bool {
        shouldSyncExplicitly(record, includeRemovedRecords: includeRemovedRecords)
    }

    private func shouldSyncExplicitly(_ record: VideoRecord, includeRemovedRecords: Bool) -> Bool {
        guard record.aviPath != nil else { return false }
        guard record.isIgnoredForSync != true else { return false }

        return true
    }

    private func isAlreadyConfirmedOnSD(
        _ record: VideoRecord,
        manifest: SDSyncManifest,
        scannedFiles: [SDFileFingerprint]
    ) -> Bool {
        guard let entry = manifest.entries.first(where: { $0.origin == .pocketSync && $0.recordID == record.id }) else {
            return false
        }

        guard let current = scannedFiles.first(where: { $0.fileName.caseInsensitiveCompare(entry.fileName) == .orderedSame }) else {
            return false
        }

        return entry.hasSameIdentity(as: current)
    }
}

enum SDCardSyncError: Error, LocalizedError {
    case sdCardNotMounted(String)
    case sdVideoFolderMissing(String)
    case targetAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .sdCardNotMounted(let path):
            return "3DS SD card is not mounted. Expected video folder: \(path)"
        case .sdVideoFolderMissing(let path):
            return "3DS video folder is missing: \(path)"
        case .targetAlreadyExists(let path):
            return "Refusing to overwrite existing SD file: \(path)"
        }
    }
}
