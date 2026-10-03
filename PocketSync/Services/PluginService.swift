import Foundation

nonisolated struct InstalledPlugin: Identifiable, Hashable {
    var manifest: PluginManifest
    var directory: URL
    var id: String { manifest.identifier }
}

nonisolated struct PluginDiscovery {
    var plugins: [InstalledPlugin] = []
    var messages: [String] = []
}

nonisolated struct PluginError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Executes explicitly selected, trusted local programs. This is not a sandbox.
/// A plugin receives one JSON request on stdin and returns one response on stdout.
nonisolated final class PluginService {
    static var localPluginDirectory: URL {
        #if DEBUG
        return PocketSyncPaths.projectRoot.appendingPathComponent("Plugins.local", isDirectory: true)
        #else
        return PocketSyncPaths.applicationSupportURL.appendingPathComponent("Plugins", isDirectory: true)
        #endif
    }

    private let fileManager = FileManager.default
    private let outputRoot: URL

    init(outputRoot: URL? = nil) {
        self.outputRoot = outputRoot ?? PocketSyncPaths.defaultMediaRoot
            .appendingPathComponent(".Imports", isDirectory: true)
    }

    func discover(in root: URL = PluginService.localPluginDirectory) -> PluginDiscovery {
        var result = PluginDiscovery()
        guard fileManager.fileExists(atPath: root.path) else { return result }
        do {
            let folders = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                do {
                    guard Self.isInside(folder, root: root) else {
                        throw PluginError(message: "Plugin folder must stay inside the plugins directory.")
                    }
                    let manifest = try loadManifest(in: folder)
                    result.plugins.append(InstalledPlugin(manifest: manifest, directory: folder))
                } catch {
                    result.messages.append("\(folder.lastPathComponent): \(error.localizedDescription)")
                }
            }
            let counts = Dictionary(grouping: result.plugins, by: \.id)
            for (id, plugins) in counts where plugins.count > 1 {
                result.messages.append("Duplicate plugin identifier: \(id). Remove or rename the duplicate manifests.")
                result.plugins.removeAll { $0.id == id }
            }
        } catch {
            result.messages.append(error.localizedDescription)
        }
        return result
    }

    func loadManifest(in directory: URL) throws -> PluginManifest {
        let url = directory.appendingPathComponent("manifest.json")
        guard Self.isInside(url, root: directory) else {
            throw PluginError(message: "Manifest must stay inside its plugin folder.")
        }
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: boundedData(at: url, limit: 64 * 1024))
        guard manifest.protocolVersion == PluginManifest.currentProtocolVersion else {
            throw PluginError(message: "Unsupported plugin protocol version.")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        guard !manifest.identifier.isEmpty,
              manifest.identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.version.isEmpty else {
            throw PluginError(message: "Plugin identifier, name, or version is invalid.")
        }
        guard manifest.capabilities.contains(.importMedia), manifest.permissions.contains(.writeImportOutput) else {
            throw PluginError(message: "This host requires the import capability and write-import-output permission.")
        }
        _ = try executableURL(for: manifest, in: directory)
        return manifest
    }

    /// Returns a validated single-item import. The caller owns its output folder
    /// after success and must discard it if saving the library record fails.
    func importMedia(
        using plugin: InstalledPlugin,
        locator: String,
        timeout: TimeInterval = 1800,
        isCancelled: () -> Bool = { false }
    ) throws -> PluginMediaCandidate {
        let current = try loadManifest(in: plugin.directory)
        guard current == plugin.manifest else {
            throw PluginError(message: "The plugin changed. Reload plugins before running it.")
        }
        let cleaned = locator.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.utf8.count <= 8192 else {
            throw PluginError(message: "Enter an input of at most 8 KB.")
        }
        if isCancelled() { throw CancellationError() }
        let runDirectory = outputRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        var keepOutput = false
        defer { if !keepOutput { try? fileManager.removeItem(at: runDirectory) } }

        let request = PluginRequest(operation: .importMedia, inputLocators: [cleaned], outputDirectory: runDirectory.path)
        let response = try execute(plugin: plugin, request: request, timeout: timeout, isCancelled: isCancelled)
        guard response.protocolVersion == request.protocolVersion, response.requestID == request.requestID else {
            throw PluginError(message: "Plugin returned a mismatched request ID or protocol version.")
        }
        guard response.succeeded else {
            throw PluginError(message: response.errorMessage ?? "Plugin could not import this item.")
        }
        guard response.candidates.count == 1, var candidate = response.candidates.first else {
            throw PluginError(message: "Protocol v1 imports exactly one video per request.")
        }
        guard !candidate.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !candidate.sources.isEmpty,
              candidate.assets.count == 1, candidate.assets.first?.role == .master else {
            throw PluginError(message: "Plugin must return a title, source, and one master video file.")
        }
        let assetURL = URL(fileURLWithPath: candidate.assets[0].path)
        let values = try assetURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard candidate.assets[0].path.hasPrefix("/"), Self.isInside(assetURL, root: runDirectory),
              values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw PluginError(message: "Plugin output must be a nonempty file inside its assigned output folder.")
        }
        candidate.assets[0].path = assetURL.resolvingSymlinksInPath().path
        candidate.assets[0].storageKind = .managed
        candidate.metadata.origin = .plugin
        candidate.metadata.providerIdentifier = plugin.id
        candidate.metadata.resolvedAt = Date()
        // Provider IDs belong to the plugin, preventing collisions with other providers.
        candidate.sources = candidate.sources.map { source in
            var source = source
            source.providerIdentifier = plugin.id
            return source
        }
        if isCancelled() { throw CancellationError() }
        keepOutput = true
        return candidate
    }

    func discard(_ candidate: PluginMediaCandidate) {
        guard let path = candidate.assets.first?.path else { return }
        // Only remove a direct run directory owned by this service.
        let relative = URL(fileURLWithPath: path).standardizedFileURL.path
        let root = outputRoot.standardizedFileURL.path + "/"
        guard relative.hasPrefix(root),
              let run = relative.dropFirst(root.count).split(separator: "/").first,
              UUID(uuidString: String(run)) != nil else { return }
        try? fileManager.removeItem(at: outputRoot.appendingPathComponent(String(run)))
    }

    static func isInside(_ url: URL, root: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path
            .hasPrefix(root.standardizedFileURL.resolvingSymlinksInPath().path + "/")
    }

    private func executableURL(for manifest: PluginManifest, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(manifest.executable)
        guard !manifest.executable.isEmpty, !manifest.executable.hasPrefix("/"),
              Self.isInside(url, root: directory), fileManager.isExecutableFile(atPath: url.path),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw PluginError(message: "Plugin executable must be executable and inside its plugin folder.")
        }
        return url
    }

    private func boundedData(at url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw PluginError(message: "Plugin response exceeds its size limit.") }
        return data
    }

    private func execute(
        plugin: InstalledPlugin, request: PluginRequest, timeout: TimeInterval, isCancelled: () -> Bool
    ) throws -> PluginResponse {
        let temp = fileManager.temporaryDirectory.appendingPathComponent("pocketsync-plugin-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temp) }
        let input = temp.appendingPathComponent("request.json")
        let output = temp.appendingPathComponent("response.json")
        let errors = temp.appendingPathComponent("stderr.txt")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(request).write(to: input)
        fileManager.createFile(atPath: output.path, contents: nil)
        fileManager.createFile(atPath: errors.path, contents: nil)
        let stdin = try FileHandle(forReadingFrom: input)
        let stdout = try FileHandle(forWritingTo: output)
        let stderr = try FileHandle(forWritingTo: errors)
        defer { try? stdin.close(); try? stdout.close(); try? stderr.close() }
        let process = Process()
        process.executableURL = try executableURL(for: plugin.manifest, in: plugin.directory)
        process.currentDirectoryURL = plugin.directory
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        try process.run()
        let start = Date()
        var interruption: Error?
        while process.isRunning {
            if isCancelled() { interruption = CancellationError() }
            if Date().timeIntervalSince(start) > timeout { interruption = PluginError(message: "Plugin timed out.") }
            let outputSize = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let errorSize = (try? errors.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if outputSize > 8 * 1024 * 1024 || errorSize > 8 * 1024 * 1024 {
                interruption = PluginError(message: "Plugin output exceeds 8 MB.")
            }
            if interruption != nil {
                process.terminate()
                let deadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        process.waitUntilExit()
        if let interruption { throw interruption }
        if isCancelled() { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            let text = String(data: try boundedData(at: errors, limit: 8 * 1024 * 1024), encoding: .utf8) ?? ""
            throw PluginError(message: "Plugin exited with status \(process.terminationStatus). \(text.suffix(2000))")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var response = try decoder.decode(PluginResponse.self, from: boundedData(at: output, limit: 8 * 1024 * 1024))
        if !response.succeeded {
            let detail = String(data: try boundedData(at: errors, limit: 8 * 1024 * 1024), encoding: .utf8) ?? ""
            if !detail.isEmpty {
                response.errorMessage = (response.errorMessage ?? "Plugin import failed.") + "\n" + String(detail.suffix(2000))
            }
        }
        return response
    }
}
