//
//  MountResolver.swift
//  PocketSync
//
//  Created by Marco Ortiz Torres on 3/8/26.
//

import Foundation

nonisolated struct ResolvedPaths: Hashable {
    let musicVideosRoot: URL
    let aviRoot: URL
    let quickTimeRoot: URL
    let sdVideoRoot: URL
    let sdMusicRoot: URL

    let isToshibaMounted: Bool
    let is3DSSDMounted: Bool
}

nonisolated final class MountResolver {
    let appPaths: AppPaths
    private let fileManager = FileManager.default

    init(appPaths: AppPaths = .default) {
        self.appPaths = appPaths
    }

    func resolvePaths() throws -> ResolvedPaths {
        let toshibaMounted = directoryExists(appPaths.toshibaMusicVideos)
        let aviMounted = directoryExists(appPaths.toshibaAVI)

        let sdVideoMounted = directoryExists(appPaths.sdCardVideoFolder)
        let sdMusicMounted = directoryExists(appPaths.sdCardMusicFolder)

        let musicVideosRoot = toshibaMounted
            ? URL(fileURLWithPath: appPaths.toshibaMusicVideos, isDirectory: true)
            : URL(fileURLWithPath: appPaths.localMusicVideos, isDirectory: true)

        let aviRoot = aviMounted
            ? URL(fileURLWithPath: appPaths.toshibaAVI, isDirectory: true)
            : URL(fileURLWithPath: appPaths.localAVI, isDirectory: true)

        let quickTimeRoot = URL(fileURLWithPath: appPaths.localQuickTime, isDirectory: true)

        let sdVideoRoot = sdVideoMounted
            ? URL(fileURLWithPath: appPaths.sdCardVideoFolder, isDirectory: true)
            : URL(fileURLWithPath: appPaths.localSDVideoFolder, isDirectory: true)

        let sdMusicRoot = sdMusicMounted
            ? URL(fileURLWithPath: appPaths.sdCardMusicFolder, isDirectory: true)
            : URL(fileURLWithPath: appPaths.localMusicFolder, isDirectory: true)

        try ensureDirectoryExists(musicVideosRoot)
        try ensureDirectoryExists(aviRoot)
        try ensureDirectoryExists(quickTimeRoot)
        try ensureDirectoryExists(sdVideoRoot)
        try ensureDirectoryExists(sdMusicRoot)

        return ResolvedPaths(
            musicVideosRoot: musicVideosRoot,
            aviRoot: aviRoot,
            quickTimeRoot: quickTimeRoot,
            sdVideoRoot: sdVideoRoot,
            sdMusicRoot: sdMusicRoot,
            isToshibaMounted: toshibaMounted && aviMounted,
            is3DSSDMounted: sdVideoMounted && sdMusicMounted
        )
    }

    func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func ensureDirectoryExists(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
