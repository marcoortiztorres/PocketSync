//
//  SDSyncManifest.swift
//  PocketSync
//

import Foundation

nonisolated enum SDSyncOrigin: String, Codable, Hashable {
    case system
    case pocketSync
}

nonisolated struct SDFileFingerprint: Codable, Hashable {
    var fileName: String
    var path: String
    var fileSize: Int64
    var modifiedAt: Date?

    var stableKey: String {
        "\(fileName.uppercased())|\(fileSize)"
    }
}

nonisolated struct SDSyncManifestEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var origin: SDSyncOrigin
    var fileName: String
    var path: String
    var fileSize: Int64
    var modifiedAt: Date?
    var recordID: UUID?
    var firstSeenAt: Date
    var lastSeenAt: Date
    var note: String?

    init(
        id: UUID = UUID(),
        origin: SDSyncOrigin,
        fileName: String,
        path: String,
        fileSize: Int64,
        modifiedAt: Date?,
        recordID: UUID? = nil,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.origin = origin
        self.fileName = fileName
        self.path = path
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.recordID = recordID
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.note = note
    }

    var fingerprint: SDFileFingerprint {
        SDFileFingerprint(
            fileName: fileName,
            path: path,
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }

    func hasSameIdentity(as fingerprint: SDFileFingerprint) -> Bool {
        fileName.caseInsensitiveCompare(fingerprint.fileName) == .orderedSame &&
        fileSize == fingerprint.fileSize
    }
}

nonisolated struct SDSyncManifest: Codable, Hashable {
    var version: Int
    var createdAt: Date
    var updatedAt: Date
    var sdVideoRootPath: String?
    var highestKnownHNIIndex: Int
    var entries: [SDSyncManifestEntry]

    init(
        version: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sdVideoRootPath: String? = nil,
        highestKnownHNIIndex: Int = 0,
        entries: [SDSyncManifestEntry] = []
    ) {
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sdVideoRootPath = sdVideoRootPath
        self.highestKnownHNIIndex = highestKnownHNIIndex
        self.entries = entries
    }
}

nonisolated struct SDSyncReport: Hashable {
    var isFirstSync: Bool
    var scannedFileCount: Int
    var systemFileCount: Int
    var pocketSyncFileCount: Int
    var newSystemFileCount: Int
    var missingPocketSyncFileCount: Int
    var changedPocketSyncFileCount: Int
    var syncedRecordCount: Int
    var skippedRecordCount: Int
    var highestHNIIndex: Int
    var messages: [String]

    static let empty = SDSyncReport(
        isFirstSync: false,
        scannedFileCount: 0,
        systemFileCount: 0,
        pocketSyncFileCount: 0,
        newSystemFileCount: 0,
        missingPocketSyncFileCount: 0,
        changedPocketSyncFileCount: 0,
        syncedRecordCount: 0,
        skippedRecordCount: 0,
        highestHNIIndex: 0,
        messages: []
    )
}
