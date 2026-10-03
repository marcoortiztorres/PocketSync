//
//  LocalMediaImporter.swift
//  PocketSync
//

import Foundation
import UniformTypeIdentifiers

nonisolated struct LocalMediaImportReport {
    var importedRecordIDs: [UUID] = []
    var skippedPaths: [String] = []
    var failures: [(path: String, message: String)] = []

    var importedCount: Int { importedRecordIDs.count }
    var skippedCount: Int { skippedPaths.count }
}

nonisolated enum LocalMediaImportMode {
    case referenceOriginals
    case copyIntoLibrary
}

/// Imports local videos either by reference or into PocketSync-owned storage.
nonisolated final class LocalMediaImporter {
    private let db: VideoDatabase
    private let fileManager: FileManager
    private let importDirectory: URL?

    init(
        db: VideoDatabase,
        fileManager: FileManager = .default,
        importDirectory: URL? = nil
    ) {
        self.db = db
        self.fileManager = fileManager
        self.importDirectory = importDirectory
    }

    func importURLs(_ inputURLs: [URL], mode: LocalMediaImportMode) -> LocalMediaImportReport {
        var report = LocalMediaImportReport()
        let roots = uniqueURLs(inputURLs)

        for root in roots {
            let didAccess = root.startAccessingSecurityScopedResource()
            defer {
                if didAccess { root.stopAccessingSecurityScopedResource() }
            }

            do {
                let candidates = try videoFiles(at: root)
                if candidates.isEmpty {
                    report.skippedPaths.append(root.path)
                }

                for candidate in candidates {
                    importFile(candidate, mode: mode, into: &report)
                }
            } catch {
                report.failures.append((root.path, error.localizedDescription))
            }
        }

        return report
    }

    private func importFile(
        _ fileURL: URL,
        mode: LocalMediaImportMode,
        into report: inout LocalMediaImportReport
    ) {
        let canonicalURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let sourcePath = canonicalURL.path

        if db.hasRecord(sourceURL: sourcePath) {
            report.skippedPaths.append(sourcePath)
            return
        }

        do {
            let recordID = UUID()
            let destination: URL
            let storageKind: MediaAssetStorageKind
            if mode == .copyIntoLibrary {
                try db.prepareStorage()
                let storage = importDirectory.map { MediaStorage(root: $0, libraryID: db.library.libraryID) } ?? db.storage
                destination = storage.originalURL(id: recordID, title: canonicalURL.deletingPathExtension().lastPathComponent, fileExtension: canonicalURL.pathExtension)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: canonicalURL, to: destination)
                storageKind = .managed
            } else {
                destination = canonicalURL
                storageKind = .referenced
            }

            do {
                let record = try db.createItem(
                    id: recordID,
                    sources: [
                        MediaSource(
                            kind: .localFile,
                            locator: sourcePath,
                            displayName: canonicalURL.lastPathComponent
                        )
                    ],
                    metadata: MediaMetadata(
                        title: canonicalURL.deletingPathExtension().lastPathComponent,
                        origin: .localFile,
                        resolvedAt: Date()
                    ),
                    assets: [
                        MediaAsset(
                            role: .master,
                            path: destination.path,
                            formatIdentifier: canonicalURL.pathExtension.lowercased(),
                            storageKind: storageKind
                        )
                    ]
                )
                report.importedRecordIDs.append(record.id)
            } catch {
                if storageKind == .managed {
                    try? fileManager.removeItem(at: destination)
                }
                throw error
            }
        } catch {
            report.failures.append((sourcePath, error.localizedDescription))
        }
    }

    private func videoFiles(at url: URL) throws -> [URL] {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .contentTypeKey]
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }

            return enumerator.compactMap { element in
                guard let candidate = element as? URL else { return nil }
                return isVideoFile(candidate) ? candidate : nil
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }

        return values.isRegularFile == true && isVideoFile(url) ? [url] : []
    }

    private func isVideoFile(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.conforms(to: .movie)
        }

        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie)
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
