//
//  PluginModels.swift
//  PocketSync
//

import Foundation

// Experimental protocol v1: the host currently implements importMedia only.
// The other operations/capabilities are intentional roadmap scaffolding; see
// docs/Plugins.md before removing or extending them. Permissions describe what
// trusted executables do; they are not macOS sandbox enforcement.

nonisolated enum PluginCapability: String, Codable, CaseIterable {
    case importMedia = "import"
    case resolveMetadata = "metadata"
    case convertMedia = "convert"
    case exportMedia = "export"
    case providePlayback = "playback"
    case libraryAction = "library-action"
}

nonisolated enum PluginPermission: String, Codable, CaseIterable {
    case readSelectedFiles = "read-selected-files"
    case writeImportOutput = "write-import-output"
    case accessNetwork = "access-network"
    case accessRemovableMedia = "access-removable-media"
    case launchExternalProcess = "launch-external-process"
    case accessBrowserSession = "access-browser-session"
}

nonisolated struct PluginManifest: Codable, Hashable {
    static let currentProtocolVersion = 1

    var identifier: String
    var name: String
    var version: String
    var protocolVersion: Int
    var executable: String
    var capabilities: Set<PluginCapability>
    var permissions: Set<PluginPermission>
    var website: String?

    init(
        identifier: String,
        name: String,
        version: String,
        protocolVersion: Int = Self.currentProtocolVersion,
        executable: String,
        capabilities: Set<PluginCapability>,
        permissions: Set<PluginPermission> = [],
        website: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.protocolVersion = protocolVersion
        self.executable = executable
        self.capabilities = capabilities
        self.permissions = permissions
        self.website = website
    }
}

nonisolated enum PluginOperation: String, Codable {
    case inspect
    case importMedia
    case resolveMetadata
    case convertMedia
    case exportMedia
    case play
    case performLibraryAction
}

nonisolated struct PluginRequest: Codable, Hashable {
    var protocolVersion: Int
    var requestID: UUID
    var operation: PluginOperation
    var inputLocators: [String]
    var options: [String: String]
    var outputDirectory: String?

    init(
        protocolVersion: Int = PluginManifest.currentProtocolVersion,
        requestID: UUID = UUID(),
        operation: PluginOperation,
        inputLocators: [String] = [],
        options: [String: String] = [:],
        outputDirectory: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.operation = operation
        self.inputLocators = inputLocators
        self.options = options
        self.outputDirectory = outputDirectory
    }
}

nonisolated struct PluginMediaCandidate: Codable, Hashable {
    var sources: [MediaSource]
    var metadata: MediaMetadata
    var assets: [MediaAsset]
}

nonisolated struct PluginResponse: Codable, Hashable {
    var protocolVersion: Int
    var requestID: UUID
    var succeeded: Bool
    var candidates: [PluginMediaCandidate]
    var messages: [String]
    var errorMessage: String?
}
