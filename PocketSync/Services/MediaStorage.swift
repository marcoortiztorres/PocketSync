import Foundation
import CryptoKit

nonisolated struct StorageError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

nonisolated struct StorageMoveReport {
    var movedFiles: Int
    var backupURL: URL
    var retainedSources: [String]
}

nonisolated struct MediaStorage {
    let root: URL
    let libraryID: UUID
    private var marker: URL { root.appendingPathComponent(".pocketsync-library-id") }
    var stagingRoot: URL { root.appendingPathComponent(".Imports", isDirectory: true) }

    func prepare(allowCreate: Bool) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: marker.path) {
            guard try String(contentsOf: marker, encoding: .utf8) == libraryID.uuidString else {
                throw StorageError("This folder belongs to a different PocketSync library.")
            }
            guard fm.isWritableFile(atPath: root.path) else { throw StorageError("The media folder is not writable.") }
            return
        }
        guard allowCreate else {
            throw StorageError("The media folder is unavailable or its library marker is missing. Reconnect the drive or choose the library folder again.")
        }
        if !fm.fileExists(atPath: root.path) {
            // Never recreate an absent mount or missing parent hierarchy.
            guard fm.fileExists(atPath: root.deletingLastPathComponent().path) else {
                throw StorageError("The media folder's parent is unavailable. Reconnect the drive first.")
            }
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
        }
        let contents = try fm.contentsOfDirectory(atPath: root.path).filter { $0 != ".DS_Store" }
        guard contents.isEmpty else { throw StorageError("Choose an empty PocketSync folder; this folder already contains other files.") }
        try Data(libraryID.uuidString.utf8).write(to: marker, options: [.atomic])
    }

    static func safeName(_ name: String) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        // Bound UTF-8 bytes as well as characters, leaving room for suffixes/extensions.
        var result = ""
        for character in cleaned {
            if (result + String(character)).utf8.count > 140 { break }
            result.append(character)
        }
        return result.isEmpty ? "Untitled video" : result
    }

    func itemDirectory(_ id: UUID) -> URL { root.appendingPathComponent("Media/\(id.uuidString)", isDirectory: true) }
    func originalURL(id: UUID, title: String, fileExtension: String) -> URL {
        let ext = String(fileExtension.filter { $0.isLetter || $0.isNumber }.prefix(12))
        return itemDirectory(id).appendingPathComponent("Original")
            .appendingPathComponent(Self.safeName(title) + (ext.isEmpty ? "" : "." + ext))
    }
    func conversionDirectory(id: UUID, quickTime: Bool) -> URL {
        itemDirectory(id).appendingPathComponent(quickTime ? "QuickTime" : "Converted", isDirectory: true)
    }

    static func relativePath(_ url: URL, under root: URL) -> String? {
        let path = url.standardizedFileURL.path
        let prefix = root.standardizedFileURL.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }

    /// Incoming plugin files are temporary until the host adopts and records them.
    func adopt(_ candidate: PluginMediaCandidate, id: UUID) throws -> PluginMediaCandidate {
        var result = candidate
        let source = URL(fileURLWithPath: candidate.assets[0].path)
        let target = originalURL(id: id, title: candidate.metadata.title, fileExtension: source.pathExtension)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: source, to: target)
            result.assets[0].path = target.path
            result.assets[0].storageKind = .managed
            return result
        } catch {
            try? FileManager.default.removeItem(at: itemDirectory(id))
            throw error
        }
    }

    static func hash(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize()
    }
}

/// Copies and verifies all owned files, then commits paths/root/sync state in one
/// atomic JSON write. Source deletion only starts after that commit. A crash before
/// commit leaves the source library usable; after commit, at worst extra copies remain.
nonisolated final class StorageMover {
    private let fm = FileManager.default

    func move(db: VideoDatabase, to target: URL) throws -> StorageMoveReport {
        if let error = db.loadError { throw error }
        let oldRoot = db.mediaRootURL.standardizedFileURL.resolvingSymlinksInPath()
        let newRoot = target.standardizedFileURL.resolvingSymlinksInPath()
        if oldRoot != newRoot && (MediaStorage.relativePath(newRoot, under: oldRoot) != nil || MediaStorage.relativePath(oldRoot, under: newRoot) != nil) {
            throw StorageError("Choose a folder outside the current library, not a parent or child of it.")
        }
        let storage = MediaStorage(root: newRoot, libraryID: db.library.libraryID)
        let backup = try db.backup()
        let rootExisted = fm.fileExists(atPath: newRoot.path)
        try storage.prepare(allowCreate: true)
        var updated = db.library
        var copies: [(source: URL, destination: URL)] = []
        var mapping: [String: String] = [:]
        var destinations = Set<String>()
        var copied: [URL] = []
        var committed = false
        defer {
            if !committed {
                for url in copied { try? fm.removeItem(at: url) }
                // Only remove the root we just created, and only our own empty folders.
                if !rootExisted { removeEmptyFolders(in: newRoot) }
            }
        }

        func plan(_ path: String, relative: String) throws -> String {
            let source = URL(fileURLWithPath: path).standardizedFileURL
            if let previous = mapping[source.path] { return previous }
            let destination = newRoot.appendingPathComponent(relative).standardizedFileURL
            guard MediaStorage.relativePath(destination, under: newRoot) != nil else { throw StorageError("Invalid destination path.") }
            if source == destination { return source.path }
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw StorageError("A managed file is missing or is a symbolic link: \(source.lastPathComponent). No files were moved.")
            }
            guard !fm.fileExists(atPath: destination.path), destinations.insert(destination.path).inserted else {
                throw StorageError("Destination already contains \(destination.lastPathComponent). No existing file will be overwritten.")
            }
            // Reject a pre-existing symlink in any destination parent.
            guard PluginService.isInside(destination, root: newRoot) else { throw StorageError("Destination contains a symbolic-link escape.") }
            copies.append((source, destination))
            mapping[source.path] = destination.path
            return destination.path
        }

        for r in updated.records.indices {
            let record = updated.records[r]
            for a in record.assets.indices {
                let asset = record.assets[a]
                guard asset.isManagedByPocketSync else { continue }
                let url = URL(fileURLWithPath: asset.path)
                // Physical SD card contents are not part of the computer's media library.
                if asset.role == .deviceCopy && record.syncState.syncedLocations.contains(where: { $0.kind == .threeDSSDCard && $0.path == asset.path }) { continue }
                if asset.role == .deviceCopy && asset.path.hasPrefix("/Volumes/") { continue }
                let relative: String
                if let existing = MediaStorage.relativePath(url, under: oldRoot) {
                    relative = existing
                } else {
                    switch asset.role {
                    case .master:
                        relative = MediaStorage.relativePath(storage.originalURL(id: record.id, title: record.metadata.title, fileExtension: url.pathExtension), under: newRoot)!
                    case .playback:
                        relative = "Media/\(record.id)/QuickTime/\(MediaStorage.safeName(record.metadata.title))_quicktime.\(url.pathExtension)"
                    case .converted:
                        relative = "Media/\(record.id)/Converted/\(MediaStorage.safeName(record.metadata.title)).\(url.pathExtension)"
                    case .deviceCopy:
                        relative = "DeviceCache/3DS/DCIM/100NIN03/\(url.lastPathComponent)"
                    }
                }
                updated.records[r].assets[a].path = try plan(asset.path, relative: relative)
            }
            for i in record.syncState.syncedLocations.indices {
                let location = record.syncState.syncedLocations[i]
                guard location.kind != .threeDSSDCard else { continue }
                let relative = MediaStorage.relativePath(URL(fileURLWithPath: location.path), under: oldRoot)
                    ?? "Media/\(record.id)/Copies/\(URL(fileURLWithPath: location.path).lastPathComponent)"
                updated.records[r].syncState.syncedLocations[i].path = try plan(location.path, relative: relative)
            }
        }
        // The SD service has historically kept an extra local mirror outside assets.
        // Move only files named by PocketSync records, never system/untracked SD files.
        for record in updated.records {
            guard let filename = record.threeDSFileName, filename == URL(fileURLWithPath: filename).lastPathComponent else { continue }
            let roots = [oldRoot.appendingPathComponent("DeviceCache/3DS/DCIM/100NIN03"), PocketSyncPaths.projectRoot.appendingPathComponent("3DS/DCIM/100NIN03")]
            for root in roots {
                let file = root.appendingPathComponent(filename)
                if fm.fileExists(atPath: file.path), mapping[file.path] == nil {
                    _ = try plan(file.path, relative: "DeviceCache/3DS/DCIM/100NIN03/\(filename)")
                }
            }
        }
        if var manifest = updated.sdSyncManifest {
            for i in manifest.entries.indices {
                if let path = mapping[manifest.entries[i].path] { manifest.entries[i].path = path }
            }
            if let path = manifest.sdVideoRootPath {
                if let relative = MediaStorage.relativePath(URL(fileURLWithPath: path), under: oldRoot) {
                    manifest.sdVideoRootPath = newRoot.appendingPathComponent(relative).path
                } else if path == PocketSyncPaths.projectRoot.appendingPathComponent("3DS/DCIM/100NIN03").path {
                    manifest.sdVideoRootPath = newRoot.appendingPathComponent("DeviceCache/3DS/DCIM/100NIN03").path
                }
            }
            updated.sdSyncManifest = manifest
        }
        var hashes: [String: SHA256.Digest] = [:]
        for copy in copies {
            let before = try MediaStorage.hash(copy.source)
            try fm.createDirectory(at: copy.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            copied.append(copy.destination)
            try fm.copyItem(at: copy.source, to: copy.destination)
            let destinationHash = try MediaStorage.hash(copy.destination)
            let sourceHash = try MediaStorage.hash(copy.source)

            guard destinationHash == before, sourceHash == before else {
                throw StorageError(
                    "Verification failed for \(copy.source.lastPathComponent). The original library is unchanged."
                )
            }

            hashes[copy.source.path] = before
        }
        updated.mediaRootPath = newRoot.path
        updated.storageInitialized = true
        try db.relocateLibrary(updated, to: newRoot.appendingPathComponent("video_index.json"))
        committed = true
        // If an original is also explicitly referenced, it must remain in place.
        let referenced = Set(updated.records.flatMap(\.assets).filter { !$0.isManagedByPocketSync }.map(\.path))
        var retained: [String] = []
        for path in Set(copies.map { $0.source.path }) {
            guard !referenced.contains(path) else { retained.append(path); continue }
            do {
                guard try MediaStorage.hash(URL(fileURLWithPath: path)) == hashes[path] else {
                    retained.append(path); continue
                }
                try fm.removeItem(atPath: path)
            } catch { retained.append(path) }
        }
        return StorageMoveReport(movedFiles: copies.count, backupURL: newRoot.appendingPathComponent("Backups").appendingPathComponent(backup.lastPathComponent), retainedSources: retained)
    }

    private func removeEmptyFolders(in root: URL) {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let folders = enumerator.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        for folder in folders.sorted(by: { $0.path.count > $1.path.count }) {
            if (try? fm.contentsOfDirectory(atPath: folder.path).isEmpty) == true { try? fm.removeItem(at: folder) }
        }
        let contents = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        if contents == [".pocketsync-library-id"] {
            try? fm.removeItem(at: root.appendingPathComponent(".pocketsync-library-id"))
            try? fm.removeItem(at: root)
        }
    }
}
