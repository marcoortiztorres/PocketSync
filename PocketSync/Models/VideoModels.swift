//
//  VideoModels.swift
//  PocketSync
//
//  Created by Marco Ortiz Torres on 3/8/26.
//

import Foundation

nonisolated enum VideoStatus: String, Codable, CaseIterable {
    case discovered
    case downloading
    case downloaded
    case convertingQuickTime
    case convertedQuickTime
    case convertingAVI
    case convertedAVI
    case copiedTo3DS
    case completed
    case removedFrom3DS
    case failed
}

// MARK: - Source-neutral library model

nonisolated enum MediaSourceKind: String, Codable, CaseIterable {
    case localFile
    case webLink
    case removableMedia
    case plugin
    case legacy
}

nonisolated struct MediaSource: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: MediaSourceKind
    var locator: String
    var providerIdentifier: String?
    var externalIdentifier: String?
    var displayName: String?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        kind: MediaSourceKind,
        locator: String,
        providerIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        displayName: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.locator = locator
        self.providerIdentifier = providerIdentifier
        self.externalIdentifier = externalIdentifier
        self.displayName = displayName
        self.addedAt = addedAt
    }
}

nonisolated enum MediaAssetRole: String, Codable, CaseIterable {
    case master
    case playback
    case converted
    case deviceCopy
}

nonisolated enum MediaAssetStorageKind: String, Codable, CaseIterable {
    case referenced
    case managed
}

nonisolated struct MediaAsset: Identifiable, Codable, Hashable {
    var id: UUID
    var role: MediaAssetRole
    var path: String
    var formatIdentifier: String?
    var deviceIdentifier: String?
    /// Missing on schema-v2 records means managed for backward compatibility.
    var storageKind: MediaAssetStorageKind?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: MediaAssetRole,
        path: String,
        formatIdentifier: String? = nil,
        deviceIdentifier: String? = nil,
        storageKind: MediaAssetStorageKind = .managed,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.path = path
        self.formatIdentifier = formatIdentifier
        self.deviceIdentifier = deviceIdentifier
        self.storageKind = storageKind
        self.createdAt = createdAt
    }

    var isManagedByPocketSync: Bool { storageKind != .referenced }
}

nonisolated enum MetadataOrigin: String, Codable, CaseIterable {
    case user
    case localFile
    case externalProvider
    case plugin
    case legacy
}

nonisolated struct MediaMetadata: Codable, Hashable {
    var title: String
    var uploader: String?
    var channel: String?
    var publishedDate: String?
    var durationSeconds: Int?
    var summary: String?
    var tags: [String]?
    var thumbnailURL: String?
    var origin: MetadataOrigin
    var providerIdentifier: String?
    var resolvedAt: Date?

    init(
        title: String,
        uploader: String? = nil,
        channel: String? = nil,
        publishedDate: String? = nil,
        durationSeconds: Int? = nil,
        summary: String? = nil,
        tags: [String]? = nil,
        thumbnailURL: String? = nil,
        origin: MetadataOrigin = .user,
        providerIdentifier: String? = nil,
        resolvedAt: Date? = nil
    ) {
        self.title = title
        self.uploader = uploader
        self.channel = channel
        self.publishedDate = publishedDate
        self.durationSeconds = durationSeconds
        self.summary = summary
        self.tags = tags
        self.thumbnailURL = thumbnailURL
        self.origin = origin
        self.providerIdentifier = providerIdentifier
        self.resolvedAt = resolvedAt
    }
}

nonisolated struct MediaSyncState: Codable, Hashable {
    var syncedLocations: [SyncedLocation]
    var lastSyncedAt: Date?
    var isIgnored: Bool
    var threeDSFileName: String?

    init(
        syncedLocations: [SyncedLocation] = [],
        lastSyncedAt: Date? = nil,
        isIgnored: Bool = false,
        threeDSFileName: String? = nil
    ) {
        self.syncedLocations = syncedLocations
        self.lastSyncedAt = lastSyncedAt
        self.isIgnored = isIgnored
        self.threeDSFileName = threeDSFileName
    }
}

nonisolated struct MediaProcessingState: Codable, Hashable {
    var status: VideoStatus
    var errorMessage: String?

    init(status: VideoStatus = .discovered, errorMessage: String? = nil) {
        self.status = status
        self.errorMessage = errorMessage
    }
}

/// A library entry is independent from any one website, file format, or device.
///
/// Compatibility properties at the bottom of this type keep the original player,
/// converter, and 3DS sync services working while they are migrated incrementally.
nonisolated struct MediaLibraryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var sources: [MediaSource]
    var metadata: MediaMetadata
    var assets: [MediaAsset]
    var syncState: MediaSyncState
    var processingState: MediaProcessingState
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sources: [MediaSource],
        metadata: MediaMetadata,
        assets: [MediaAsset] = [],
        syncState: MediaSyncState = MediaSyncState(),
        processingState: MediaProcessingState = MediaProcessingState(),
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sources = sources
        self.metadata = metadata
        self.assets = assets
        self.syncState = syncState
        self.processingState = processingState
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Legacy initializer retained until the old URL pipeline is replaced.
    init(
        id: UUID = UUID(),
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
        thumbnailURL: String? = nil,
        highResPath: String? = nil,
        quickTimePath: String? = nil,
        aviPath: String? = nil,
        threeDSPath: String? = nil,
        syncedLocations: [SyncedLocation]? = nil,
        lastSyncedAt: Date? = nil,
        isIgnoredForSync: Bool? = nil,
        threeDSFileName: String? = nil,
        status: VideoStatus = .discovered,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        var migratedSources = [
            MediaSource(
                kind: sourceURL.hasPrefix("http") ? .webLink : .legacy,
                locator: sourceURL,
                providerIdentifier: extractor,
                externalIdentifier: extractorVideoID,
                addedAt: createdAt
            )
        ]

        if let webpageURL, webpageURL != sourceURL {
            migratedSources.append(
                MediaSource(
                    kind: .webLink,
                    locator: webpageURL,
                    providerIdentifier: extractor,
                    externalIdentifier: extractorVideoID,
                    addedAt: createdAt
                )
            )
        }

        var migratedAssets: [MediaAsset] = []
        if let highResPath {
            migratedAssets.append(MediaAsset(role: .master, path: highResPath, createdAt: createdAt))
        }
        if let quickTimePath {
            migratedAssets.append(MediaAsset(role: .playback, path: quickTimePath, formatIdentifier: "mp4", createdAt: createdAt))
        }
        if let aviPath {
            migratedAssets.append(MediaAsset(role: .converted, path: aviPath, formatIdentifier: "avi", deviceIdentifier: "nintendo.3ds", createdAt: createdAt))
        }
        if let threeDSPath {
            migratedAssets.append(MediaAsset(role: .deviceCopy, path: threeDSPath, formatIdentifier: "avi", deviceIdentifier: "nintendo.3ds", createdAt: createdAt))
        }

        self.init(
            id: id,
            sources: migratedSources,
            metadata: MediaMetadata(
                title: title,
                uploader: uploader,
                channel: channel,
                publishedDate: uploadDate,
                durationSeconds: durationSeconds,
                summary: description,
                tags: tags,
                thumbnailURL: thumbnailURL,
                origin: .legacy,
                providerIdentifier: extractor
            ),
            assets: migratedAssets,
            syncState: MediaSyncState(
                syncedLocations: syncedLocations ?? [],
                lastSyncedAt: lastSyncedAt,
                isIgnored: isIgnoredForSync ?? false,
                threeDSFileName: threeDSFileName
            ),
            processingState: MediaProcessingState(status: status, errorMessage: errorMessage),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        // Version 2
        case id, sources, metadata, assets, syncState, processingState, isFavorite, createdAt, updatedAt

        // Version 1
        case sourceURL, extractor, extractorVideoID, webpageURL
        case title, uploader, channel, uploadDate, durationSeconds, description, tags, thumbnailURL
        case highResPath, quickTimePath, aviPath, threeDSPath
        case syncedLocations, lastSyncedAt, isIgnoredForSync, threeDSFileName
        case status, errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.sources), container.contains(.metadata) {
            let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
            self.init(
                id: try container.decode(UUID.self, forKey: .id),
                sources: try container.decode([MediaSource].self, forKey: .sources),
                metadata: try container.decode(MediaMetadata.self, forKey: .metadata),
                assets: try container.decodeIfPresent([MediaAsset].self, forKey: .assets) ?? [],
                syncState: try container.decodeIfPresent(MediaSyncState.self, forKey: .syncState) ?? MediaSyncState(),
                processingState: try container.decodeIfPresent(MediaProcessingState.self, forKey: .processingState) ?? MediaProcessingState(),
                isFavorite: try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false,
                createdAt: createdAt,
                updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
            )
            return
        }

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            sourceURL: try container.decode(String.self, forKey: .sourceURL),
            extractor: try container.decodeIfPresent(String.self, forKey: .extractor),
            extractorVideoID: try container.decodeIfPresent(String.self, forKey: .extractorVideoID),
            webpageURL: try container.decodeIfPresent(String.self, forKey: .webpageURL),
            title: try container.decode(String.self, forKey: .title),
            uploader: try container.decodeIfPresent(String.self, forKey: .uploader),
            channel: try container.decodeIfPresent(String.self, forKey: .channel),
            uploadDate: try container.decodeIfPresent(String.self, forKey: .uploadDate),
            durationSeconds: try container.decodeIfPresent(Int.self, forKey: .durationSeconds),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            tags: try container.decodeIfPresent([String].self, forKey: .tags),
            thumbnailURL: try container.decodeIfPresent(String.self, forKey: .thumbnailURL),
            highResPath: try container.decodeIfPresent(String.self, forKey: .highResPath),
            quickTimePath: try container.decodeIfPresent(String.self, forKey: .quickTimePath),
            aviPath: try container.decodeIfPresent(String.self, forKey: .aviPath),
            threeDSPath: try container.decodeIfPresent(String.self, forKey: .threeDSPath),
            syncedLocations: try container.decodeIfPresent([SyncedLocation].self, forKey: .syncedLocations),
            lastSyncedAt: try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt),
            isIgnoredForSync: try container.decodeIfPresent(Bool.self, forKey: .isIgnoredForSync),
            threeDSFileName: try container.decodeIfPresent(String.self, forKey: .threeDSFileName),
            status: try container.decodeIfPresent(VideoStatus.self, forKey: .status) ?? .discovered,
            errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sources, forKey: .sources)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(assets, forKey: .assets)
        try container.encode(syncState, forKey: .syncState)
        try container.encode(processingState, forKey: .processingState)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Temporary compatibility name used by the existing views and services.
typealias VideoRecord = MediaLibraryItem

nonisolated struct SyncedLocation: Codable, Hashable {
    nonisolated enum Kind: String, Codable {
        case threeDSSDCard
        case backupStorage
        case localFallback
    }

    var kind: Kind
    var fileName: String
    var path: String
    var syncedAt: Date
}

/// Schema 3 stores owned media paths relative to mediaRootPath on disk.
/// In-memory paths remain absolute for the existing playback/conversion services.
nonisolated struct VideoLibrary: Codable {
    static let currentSchemaVersion = 3
    var schemaVersion = currentSchemaVersion
    var libraryID: UUID
    var mediaRootPath: String
    var storageInitialized: Bool
    var records: [MediaLibraryItem]
    var next3DSIndex: Int
    var sdSyncManifest: SDSyncManifest?

    init(records: [MediaLibraryItem] = [], next3DSIndex: Int = 1,
         mediaRootPath: String = PocketSyncPaths.defaultMediaRoot.path) {
        self.libraryID = UUID()
        self.mediaRootPath = mediaRootPath
        self.storageInitialized = false
        self.records = records
        self.next3DSIndex = next3DSIndex
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, libraryID, mediaRootPath, storageInitialized, records, next3DSIndex, sdSyncManifest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= Self.currentSchemaVersion else {
            throw StorageError("This library was created by a newer PocketSync version.")
        }
        libraryID = try c.decodeIfPresent(UUID.self, forKey: .libraryID) ?? UUID()
        mediaRootPath = try c.decodeIfPresent(String.self, forKey: .mediaRootPath) ?? PocketSyncPaths.defaultMediaRoot.path
        guard mediaRootPath.hasPrefix("/") else { throw StorageError("The media folder must be an absolute path.") }
        storageInitialized = try c.decodeIfPresent(Bool.self, forKey: .storageInitialized) ?? false
        records = try c.decodeIfPresent([MediaLibraryItem].self, forKey: .records) ?? []
        next3DSIndex = try c.decodeIfPresent(Int.self, forKey: .next3DSIndex) ?? 1
        sdSyncManifest = try c.decodeIfPresent(SDSyncManifest.self, forKey: .sdSyncManifest)
        let decodedRoot = mediaRootPath
        try transformPaths { path in
            if path.hasPrefix("/") { return path }
            guard !path.isEmpty, !path.split(separator: "/").contains("..") else {
                throw StorageError("Invalid relative media path in the library.")
            }
            return URL(fileURLWithPath: decodedRoot).appendingPathComponent(path).path
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(libraryID, forKey: .libraryID)
        try c.encode(mediaRootPath, forKey: .mediaRootPath)
        try c.encode(storageInitialized, forKey: .storageInitialized)
        var portable = self
        let prefix = URL(fileURLWithPath: mediaRootPath).standardizedFileURL.path + "/"
        portable.transformPaths { path in
            path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        }
        try c.encode(portable.records, forKey: .records)
        try c.encode(next3DSIndex, forKey: .next3DSIndex)
        try c.encodeIfPresent(portable.sdSyncManifest, forKey: .sdSyncManifest)
    }

    mutating func rebaseManagedPaths(to root: URL) {
        let oldRoot = URL(fileURLWithPath: mediaRootPath)
        transformPaths { path in
            guard let relative = MediaStorage.relativePath(URL(fileURLWithPath: path), under: oldRoot) else { return path }
            return root.appendingPathComponent(relative).path
        }
        mediaRootPath = root.path
    }

    private mutating func transformPaths(_ transform: (String) throws -> String) rethrows {
        for r in records.indices {
            for a in records[r].assets.indices where records[r].assets[a].isManagedByPocketSync {
                records[r].assets[a].path = try transform(records[r].assets[a].path)
            }
            for i in records[r].syncState.syncedLocations.indices where records[r].syncState.syncedLocations[i].kind != .threeDSSDCard {
                records[r].syncState.syncedLocations[i].path = try transform(records[r].syncState.syncedLocations[i].path)
            }
        }
        if var manifest = sdSyncManifest {
            if let path = manifest.sdVideoRootPath { manifest.sdVideoRootPath = try transform(path) }
            for i in manifest.entries.indices { manifest.entries[i].path = try transform(manifest.entries[i].path) }
            sdSyncManifest = manifest
        }
    }
}

nonisolated struct AppPaths: Codable, Hashable {
    var toshibaMusicVideos: String
    var toshibaAVI: String
    var sdCardVideoFolder: String
    var sdCardMusicFolder: String

    var localMusicVideos: String
    var localAVI: String
    var localQuickTime: String
    var localSDVideoFolder: String
    var localMusicFolder: String

    static var `default`: AppPaths { forMediaRoot(PocketSyncPaths.defaultMediaRoot) }

    static func forMediaRoot(_ root: URL) -> AppPaths {
        AppPaths(
            toshibaMusicVideos: "", toshibaAVI: "",
            sdCardVideoFolder: "/Volumes/NO NAME/DCIM/100NIN03",
            sdCardMusicFolder: "/Volumes/NO NAME/Music",
            localMusicVideos: root.appendingPathComponent("Media").path,
            localAVI: root.appendingPathComponent("Media").path,
            localQuickTime: root.appendingPathComponent("Media").path,
            localSDVideoFolder: root.appendingPathComponent("DeviceCache/3DS/DCIM/100NIN03").path,
            localMusicFolder: root.appendingPathComponent("Music").path
        )
    }

}

// MARK: - Compatibility accessors

nonisolated extension MediaLibraryItem {
    var sourceURL: String {
        get { sources.first?.locator ?? "" }
        set {
            if sources.isEmpty {
                sources.append(MediaSource(kind: newValue.hasPrefix("http") ? .webLink : .localFile, locator: newValue))
            } else {
                sources[0].locator = newValue
            }
        }
    }

    var extractor: String? {
        get { sources.first?.providerIdentifier ?? metadata.providerIdentifier }
        set {
            ensurePrimarySource()
            sources[0].providerIdentifier = newValue
            metadata.providerIdentifier = newValue
        }
    }

    var extractorVideoID: String? {
        get { sources.first?.externalIdentifier }
        set {
            ensurePrimarySource()
            sources[0].externalIdentifier = newValue
        }
    }

    var webpageURL: String? {
        get { sources.first(where: { $0.kind == .webLink })?.locator }
        set {
            guard let newValue else { return }
            if let index = sources.firstIndex(where: { $0.kind == .webLink }) {
                sources[index].locator = newValue
            } else {
                sources.append(MediaSource(kind: .webLink, locator: newValue))
            }
        }
    }

    var title: String {
        get { metadata.title }
        set { metadata.title = newValue }
    }

    var uploader: String? {
        get { metadata.uploader }
        set { metadata.uploader = newValue }
    }

    var channel: String? {
        get { metadata.channel }
        set { metadata.channel = newValue }
    }

    var uploadDate: String? {
        get { metadata.publishedDate }
        set { metadata.publishedDate = newValue }
    }

    var durationSeconds: Int? {
        get { metadata.durationSeconds }
        set { metadata.durationSeconds = newValue }
    }

    var description: String? {
        get { metadata.summary }
        set { metadata.summary = newValue }
    }

    var tags: [String]? {
        get { metadata.tags }
        set { metadata.tags = newValue }
    }

    var thumbnailURL: String? {
        get { metadata.thumbnailURL }
        set { metadata.thumbnailURL = newValue }
    }

    var highResPath: String? {
        get { assetPath(role: .master) }
        set { setAssetPath(newValue, role: .master) }
    }

    var quickTimePath: String? {
        get { assetPath(role: .playback) }
        set { setAssetPath(newValue, role: .playback, formatIdentifier: "mp4") }
    }

    var aviPath: String? {
        get { assetPath(role: .converted, deviceIdentifier: "nintendo.3ds") }
        set { setAssetPath(newValue, role: .converted, formatIdentifier: "avi", deviceIdentifier: "nintendo.3ds") }
    }

    var threeDSPath: String? {
        get { assetPath(role: .deviceCopy, deviceIdentifier: "nintendo.3ds") }
        set { setAssetPath(newValue, role: .deviceCopy, formatIdentifier: "avi", deviceIdentifier: "nintendo.3ds") }
    }

    var syncedLocations: [SyncedLocation]? {
        get { syncState.syncedLocations.isEmpty ? nil : syncState.syncedLocations }
        set { syncState.syncedLocations = newValue ?? [] }
    }

    var lastSyncedAt: Date? {
        get { syncState.lastSyncedAt }
        set { syncState.lastSyncedAt = newValue }
    }

    var isIgnoredForSync: Bool? {
        get { syncState.isIgnored }
        set { syncState.isIgnored = newValue ?? false }
    }

    var threeDSFileName: String? {
        get { syncState.threeDSFileName }
        set { syncState.threeDSFileName = newValue }
    }

    var status: VideoStatus {
        get { processingState.status }
        set { processingState.status = newValue }
    }

    var errorMessage: String? {
        get { processingState.errorMessage }
        set { processingState.errorMessage = newValue }
    }

    var displayName: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return extractorVideoID ?? sourceURL
    }

    var isDownloaded: Bool { highResPath != nil }
    var isAVIConverted: Bool { aviPath != nil }
    var isAssigned3DSName: Bool { threeDSFileName != nil }

    private mutating func ensurePrimarySource() {
        if sources.isEmpty {
            sources.append(MediaSource(kind: .legacy, locator: ""))
        }
    }

    private func assetPath(role: MediaAssetRole, deviceIdentifier: String? = nil) -> String? {
        assets.first {
            $0.role == role && (deviceIdentifier == nil || $0.deviceIdentifier == deviceIdentifier)
        }?.path
    }

    private mutating func setAssetPath(
        _ path: String?,
        role: MediaAssetRole,
        formatIdentifier: String? = nil,
        deviceIdentifier: String? = nil
    ) {
        let index = assets.firstIndex {
            $0.role == role && (deviceIdentifier == nil || $0.deviceIdentifier == deviceIdentifier)
        }

        guard let path else {
            if let index { assets.remove(at: index) }
            return
        }

        if let index {
            assets[index].path = path
            assets[index].formatIdentifier = formatIdentifier ?? assets[index].formatIdentifier
            assets[index].deviceIdentifier = deviceIdentifier ?? assets[index].deviceIdentifier
        } else {
            assets.append(
                MediaAsset(
                    role: role,
                    path: path,
                    formatIdentifier: formatIdentifier,
                    deviceIdentifier: deviceIdentifier
                )
            )
        }
    }
}

nonisolated extension VideoLibrary {
    func record(forVideoID videoID: String) -> MediaLibraryItem? {
        records.first { $0.extractorVideoID == videoID }
    }

    func record(forSourceURL url: String) -> MediaLibraryItem? {
        records.first { record in record.sources.contains(where: { $0.locator == url }) }
    }

    mutating func upsert(_ record: MediaLibraryItem) {
        if let videoID = record.extractorVideoID,
           let index = records.firstIndex(where: { $0.extractorVideoID == videoID && $0.extractor == record.extractor }) {
            records[index] = record
            return
        }

        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
    }

    mutating func next3DSFileName() -> String {
        let filename = String(format: "HNI_%04d.AVI", next3DSIndex)
        next3DSIndex += 1
        return filename
    }
}
