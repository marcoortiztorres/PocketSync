//
//  PocketSyncApp.swift
//  PocketSync
//
//  Created by Marco Ortiz Torres on 3/7/26.
//

import SwiftUI
import AppKit

@main
struct PocketSyncApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Plugins") {
                Button("Open Plugins Folder…") {
                    openPluginsFolder()
                }
                Button("Refresh Plugins") {
                    NotificationCenter.default.post(name: .pocketSyncRefreshPlugins, object: nil)
                }
            }
        }
    }

    private func openPluginsFolder() {
        do {
            let directory = PluginService.localPluginDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(directory) else {
                throw PluginError(message: "Could not open the plugins folder in Finder.")
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not open plugins folder"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
