//
//  ShellRunner.swift
//  PocketSync
//
//  Created by Marco Ortiz Torres on 3/8/26.
//

import Foundation

nonisolated struct ShellResult {
    let output: String
    let errorOutput: String
    let exitCode: Int32

    var succeeded: Bool {
        exitCode == 0
    }
}

nonisolated enum ShellRunnerError: Error, LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}

nonisolated final class ShellRunner {
    @discardableResult
    func run(
        launchPath: String = "/bin/zsh",
        arguments: [String]
    ) throws -> ShellResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: stdoutData, encoding: .utf8) ?? ""
        let errorOutput = String(data: stderrData, encoding: .utf8) ?? ""

        return ShellResult(
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            errorOutput: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: process.terminationStatus
        )
    }

    func runShellCommand(_ command: String) throws -> ShellResult {
        try run(arguments: ["-lc", command])
    }

    func requireSuccess(_ result: ShellResult, context: String) throws {
        guard result.succeeded else {
            let message = """
            \(context)
            Exit code: \(result.exitCode)

            STDOUT:
            \(result.output)

            STDERR:
            \(result.errorOutput)
            """
            throw ShellRunnerError.commandFailed(message)
        }
    }

    func resolvedCommandPath(_ command: String) -> String? {
        let fm = FileManager.default

        let commonPaths = [
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)"
        ]

        for path in commonPaths {
            print("Checking path: \(path)")
            if fm.fileExists(atPath: path) {
                print("Exists at: \(path)")
            }
            if fm.isExecutableFile(atPath: path) {
                print("Executable at: \(path)")
                return path
            }
        }

        do {
            let result = try run(arguments: ["-lc", "which \(command)"])
            print("which \(command) -> \(result.output)")
            if result.succeeded, !result.output.isEmpty {
                return result.output
            }
        } catch {
            print("which \(command) failed: \(error)")
        }

        return nil
    }

    func commandExists(_ command: String) -> Bool {
        resolvedCommandPath(command) != nil
    }
}
