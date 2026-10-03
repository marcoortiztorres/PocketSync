//
//  VideoPipeline.swift
//  PocketSync
//
//  Created by Marco Ortiz Torres on 3/8/26.
//

import Foundation

nonisolated final class VideoPipeline {

    private let db: VideoDatabase
    private let mounts: MountResolver
    private let shell: ShellRunner

    init(
        db: VideoDatabase,
        mounts: MountResolver? = nil,
        shell: ShellRunner = ShellRunner()
    ) {
        self.db = db
        self.mounts = mounts ?? MountResolver(appPaths: .forMediaRoot(db.mediaRootURL))
        self.shell = shell
    }

    func convertQuickTimeStep(recordID: UUID, force: Bool = true) throws {
        guard let record = db.record(recordID: recordID) else {
            throw VideoPipelineError.recordNotFound(recordID)
        }

        guard let highResPath = record.highResPath,
              FileManager.default.fileExists(atPath: highResPath) else {
            throw VideoPipelineError.missingPath("highResPath")
        }

        if !force, let quickTimePath = record.quickTimePath, FileManager.default.fileExists(atPath: quickTimePath) {
            try db.updateStatus(recordID: recordID, status: .convertedQuickTime)
            return
        }

        try db.updateStatus(recordID: recordID, status: .convertingQuickTime)

        try db.prepareStorage()
        let inputURL = URL(fileURLWithPath: highResPath)
        let quickTimeFile: URL
        do {
            quickTimeFile = try convertToQuickTime(input: inputURL, outputFolder: db.storage.conversionDirectory(id: recordID, quickTime: true))
        } catch {
            try? db.updateStatus(recordID: recordID, status: .failed, errorMessage: error.localizedDescription)
            throw error
        }

        try db.updatePaths(
            recordID: recordID,
            quickTimePath: quickTimeFile.path
        )

        try db.updateStatus(recordID: recordID, status: .convertedQuickTime)
    }

    func convertAVIStep(recordID: UUID, force: Bool = true) throws {
        guard let record = db.record(recordID: recordID) else {
            throw VideoPipelineError.recordNotFound(recordID)
        }

        guard let highResPath = record.highResPath else {
            throw VideoPipelineError.missingPath("highResPath")
        }

        if !force, let aviPath = record.aviPath, FileManager.default.fileExists(atPath: aviPath) {
            try db.updateStatus(recordID: recordID, status: .convertedAVI)
            return
        }

        try db.updateStatus(recordID: recordID, status: .convertingAVI)

        try db.prepareStorage()
        let inputURL = URL(fileURLWithPath: highResPath)

        let aviFile = try convertToAVI(
            input: inputURL,
            outputFolder: db.storage.conversionDirectory(id: recordID, quickTime: false)
        )

        if let uploadDate = record.uploadDate,
           let timestamp = AVIDatePatcher.timestamp(from: uploadDate) {
            try AVIDatePatcher.patch(aviURL: aviFile, timestamp: timestamp)
            print("PIPELINE: patched 3DS AVI timestamp -> \(timestamp)")
        }

        try db.updatePaths(
            recordID: recordID,
            aviPath: aviFile.path
        )

        try db.updateStatus(
            recordID: recordID,
            status: .convertedAVI
        )
    }

    func syncStep(recordID: UUID, force: Bool = true) throws {
        let syncService = SDCardSyncService(db: db, mounts: mounts)
        let report = try syncService.sync(
            recordID: recordID,
            options: SDCardSyncOptions(
                firstTimeSync: false,
                includeRemovedRecords: true,
                requireMountedSDCard: false,
                mirrorToLocalCache: true
            )
        )

        for message in report.messages {
            print("SYNC: \(message)")
        }
    }

    // MARK: QuickTime Conversion

    func convertToQuickTime(
        input: URL,
        outputFolder: URL
    ) throws -> URL {

        guard FileManager.default.fileExists(atPath: input.path) else {
            throw ShellRunnerError.commandFailed("QuickTime conversion input does not exist: \(input.path)")
        }

        let base = input.deletingPathExtension().lastPathComponent

        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let output = outputFolder
            .appendingPathComponent("\(base)_quicktime")
            .appendingPathExtension("mp4")

        let tempOutput = outputFolder
            .appendingPathComponent("\(base)_quicktime.normalizing")
            .appendingPathExtension("mp4")

        let ffmpeg = try ffmpegPath()

        if FileManager.default.fileExists(atPath: tempOutput.path) {
            try? FileManager.default.removeItem(at: tempOutput)
        }

        _ = try runProcess(
            executable: ffmpeg,
            arguments: [
                "-hide_banner",
                "-nostdin",
                "-y",
                "-i", input.path,
                "-map", "0:v:0",
                "-map", "0:a:0?",
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "18",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-b:a", "192k",
                "-movflags", "+faststart",
                tempOutput.path
            ],
            context: "QuickTime conversion failed",
            timeoutSeconds: 1800
        )

        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }

        try FileManager.default.moveItem(at: tempOutput, to: output)

        return output
    }

    // MARK: AVI Conversion

    func convertToAVI(
        input: URL,
        outputFolder: URL
    ) throws -> URL {

        guard FileManager.default.fileExists(atPath: input.path) else {
            throw ShellRunnerError.commandFailed("AVI conversion input does not exist: \(input.path)")
        }

        let base = input.deletingPathExtension().lastPathComponent

        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let output = outputFolder
            .appendingPathComponent(base)
            .appendingPathExtension("AVI")

        let tempOutput = outputFolder
            .appendingPathComponent("\(base).converting")
            .appendingPathExtension("AVI")

        let ffmpeg = try ffmpegPath()

        if FileManager.default.fileExists(atPath: tempOutput.path) {
            try? FileManager.default.removeItem(at: tempOutput)
        }

        _ = try runProcess(
            executable: ffmpeg,
            arguments: [
                "-hide_banner",
                "-nostdin",
                "-y",
                "-i", input.path,
                "-vf", "scale=400:240:force_original_aspect_ratio=decrease,pad=400:240:(ow-iw)/2:(oh-ih)/2",
                "-r", "20",
                "-vcodec", "mjpeg",
                "-q:v", "5",
                "-ac", "2",
                "-ar", "32000",
                "-acodec", "pcm_s16le",
                tempOutput.path
            ],
            context: "AVI conversion failed",
            timeoutSeconds: 1800
        )

        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }

        try FileManager.default.moveItem(at: tempOutput, to: output)

        return output
    }

    // MARK: Process Runner

    private struct ProcessResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private final class ProcessOutputBuffer {
        private let lock = NSLock()
        private var stdout = ""
        private var stderr = ""

        func appendStdout(_ text: String) {
            lock.lock()
            stdout += text
            lock.unlock()
        }

        func appendStderr(_ text: String) {
            lock.lock()
            stderr += text
            lock.unlock()
        }

        func snapshot() -> (stdout: String, stderr: String) {
            lock.lock()
            let output = (stdout, stderr)
            lock.unlock()
            return output
        }
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        context: String,
        timeoutSeconds: TimeInterval
    ) throws -> ProcessResult {

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let outputBuffer = ProcessOutputBuffer()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ]

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            let text = String(data: data, encoding: .utf8) ?? ""
            outputBuffer.appendStdout(text)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            let text = String(data: data, encoding: .utf8) ?? ""
            outputBuffer.appendStderr(text)

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print(text, terminator: "")
            }
        }

        print("PIPELINE: running command -> \(executable) \(arguments.joined(separator: " "))")

        let didTerminate = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            didTerminate.signal()
        }

        try process.run()

        if didTerminate.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()

            _ = didTerminate.wait(timeout: .now() + 2)

            if process.isRunning {
                process.interrupt()
                _ = didTerminate.wait(timeout: .now() + 1)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let capturedOutput = outputBuffer.snapshot()

            throw ShellRunnerError.commandFailed("""
            \(context)
            Process timed out after \(Int(timeoutSeconds)) seconds.

            Command:
            \(executable) \(arguments.joined(separator: " "))

            STDOUT:
            \(capturedOutput.stdout)

            STDERR:
            \(capturedOutput.stderr)
            """)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout = stdoutPipe.fileHandleForReading.availableData
        let remainingStderr = stderrPipe.fileHandleForReading.availableData

        if !remainingStdout.isEmpty {
            outputBuffer.appendStdout(String(data: remainingStdout, encoding: .utf8) ?? "")
        }
        if !remainingStderr.isEmpty {
            outputBuffer.appendStderr(String(data: remainingStderr, encoding: .utf8) ?? "")
        }

        let finalOutput = outputBuffer.snapshot()

        let result = ProcessResult(
            stdout: finalOutput.stdout,
            stderr: finalOutput.stderr,
            exitCode: process.terminationStatus
        )

        if result.exitCode != 0 {
            throw ShellRunnerError.commandFailed("""
            \(context)
            Exit code: \(result.exitCode)

            Command:
            \(executable) \(arguments.joined(separator: " "))

            STDOUT:
            \(result.stdout)

            STDERR:
            \(result.stderr)
            """)
        }

        return result
    }

    // MARK: Helpers

    private func ffmpegPath() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        throw VideoPipelineError.toolMissing("ffmpeg")
    }

}

// MARK: Errors

nonisolated enum VideoPipelineError: Error, LocalizedError {

    case toolMissing(String)
    case recordNotFound(UUID)
    case missingPath(String)

    var errorDescription: String? {
        switch self {
        case .toolMissing(let tool):
            return "Required tool is missing: \(tool). Install it with Homebrew, for example: brew install \(tool)"
        case .recordNotFound(let id):
            return "Video record was not found: \(id.uuidString)"
        case .missingPath(let pathName):
            return "Missing required file path: \(pathName)"
        }
    }
}
