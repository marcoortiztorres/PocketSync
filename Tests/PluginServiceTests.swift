import Foundation

@main
struct PluginServiceTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw PluginError(message: "TEST FAILED: " + message) }
    }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("plugin-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let pluginsRoot = root.appendingPathComponent("plugins")
        let pluginFolder = pluginsRoot.appendingPathComponent("fixture")
        try fm.createDirectory(at: pluginFolder, withIntermediateDirectories: true)
        let executable = pluginFolder.appendingPathComponent("run.py")
        try fm.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), to: executable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let manifestURL = pluginFolder.appendingPathComponent("manifest.json")
        var manifest = PluginManifest(identifier: "test.import", name: "Test import", version: "1", executable: "run.py", capabilities: [.importMedia], permissions: [.writeImportOutput])
        func writeManifest() throws { try JSONEncoder().encode(manifest).write(to: manifestURL) }
        try writeManifest()
        let outputRoot = root.appendingPathComponent("output")
        let service = PluginService(outputRoot: outputRoot)
        let discovery = service.discover(in: pluginsRoot)
        try require(discovery.plugins.count == 1 && discovery.messages.isEmpty, "valid plugin discovery")
        let plugin = discovery.plugins[0]
        let candidate = try service.importMedia(using: plugin, locator: "success")
        try require(candidate.metadata.uploader == "Fixture creator" && candidate.metadata.durationSeconds == 2, "metadata mapping")
        try require(candidate.assets[0].storageKind == .managed && candidate.metadata.providerIdentifier == plugin.id, "host assigns ownership")
        try require(fm.fileExists(atPath: candidate.assets[0].path), "successful output preserved")
        let db = VideoDatabase(databaseURL: root.appendingPathComponent("library.json"))
        let record = try db.createItem(sources: candidate.sources, metadata: candidate.metadata, assets: candidate.assets)
        db.reload()
        try require(db.record(recordID: record.id)?.metadata.uploader == "Fixture creator", "metadata survives reload")
        let failedDBURL = root.appendingPathComponent("unwritable-library")
        try fm.createDirectory(at: failedDBURL, withIntermediateDirectories: true)
        let failedDB = VideoDatabase(databaseURL: failedDBURL)
        do {
            _ = try failedDB.createItem(sources: candidate.sources, metadata: candidate.metadata, assets: candidate.assets)
            throw PluginError(message: "Expected persistence failure")
        } catch {
            try require(failedDB.allRecords().isEmpty, "failed save does not mutate in-memory library")
        }
        service.discard(candidate)
        try require(!fm.fileExists(atPath: candidate.assets[0].path), "rollback removes successful output")

        for mode in ["wrong-id", "failure", "multiple", "escape", "empty-file", "empty-title", "malformed", "oversized", "crash", "slow"] {
            var rejected = false
            do { _ = try service.importMedia(using: plugin, locator: mode, timeout: mode == "slow" ? 0.2 : 5) }
            catch { rejected = true }
            try require(rejected, "reject \(mode)")
            let remaining = try fm.contentsOfDirectory(at: outputRoot, includingPropertiesForKeys: [.isDirectoryKey])
            try require(!remaining.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }, "clean failed output for \(mode)")
        }
        let outside = outputRoot.appendingPathComponent("outside.mp4")
        let outsideContents = try String(contentsOf: outside, encoding: .utf8)
        try require(outsideContents == "keep me", "escape validation preserves external file")
        let started = Date()
        do {
            _ = try service.importMedia(using: plugin, locator: "slow", isCancelled: { Date().timeIntervalSince(started) > 0.2 })
            throw PluginError(message: "Cancellation did not stop execution")
        } catch is CancellationError {}
        try require(Date().timeIntervalSince(started) < 5, "cancellation returns promptly")
        manifest.protocolVersion = 99
        try writeManifest()
        try require(service.discover(in: pluginsRoot).plugins.isEmpty, "unsupported protocol")
        manifest.protocolVersion = 1
        manifest.executable = "../outside"
        try writeManifest()
        try require(service.discover(in: pluginsRoot).plugins.isEmpty, "executable traversal")
        manifest.executable = "run.py"
        manifest.version = "2"
        try writeManifest()
        var changedRejected = false
        do { _ = try service.importMedia(using: plugin, locator: "success") } catch { changedRejected = true }
        try require(changedRejected, "reject manifest changed since selection")
        let second = pluginsRoot.appendingPathComponent("duplicate")
        try fm.copyItem(at: pluginFolder, to: second)
        try require(service.discover(in: pluginsRoot).plugins.isEmpty, "duplicate identifiers rejected")
        try require(service.discover(in: root.appendingPathComponent("missing")).plugins.isEmpty, "no plugins installed")

        var library = VideoLibrary()
        let first = MediaLibraryItem(sourceURL: "a", extractor: "provider.a", extractorVideoID: "123", title: "A")
        let secondItem = MediaLibraryItem(sourceURL: "b", extractor: "provider.b", extractorVideoID: "123", title: "B")
        library.upsert(first)
        library.upsert(secondItem)
        try require(library.records.count == 2, "external IDs scoped by provider")
        print("PASS: discovery, metadata, ownership, rollback, invalid responses, traversal, cancellation, timeout, duplicates, and provider identity")
    }
}
