import SwiftUI
import AppKit

struct StorageLocationPanel: View {
    @ObservedObject var videoManager: VideoManager
    @State private var proposedRoot: URL?
    @State private var showMoveConfirmation = false

    var body: some View {
        Y2KPanel(title: "library storage", tint: PocketStyle.sky) {
            VStack(alignment: .leading, spacing: 10) {
                Text(videoManager.mediaStoragePath)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                Text("This folder contains your media, video_index.json, and Backups. Copy the whole folder to back up the library.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Change location…") { chooseLocation() }
                        .disabled(videoManager.isProcessing)
                    Button("Open folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: videoManager.mediaStoragePath))
                    }
                    .disabled(!FileManager.default.fileExists(atPath: videoManager.mediaStoragePath))
                }
                if videoManager.storageNeedsOrganization {
                    Text("Some managed files are still in the previous layout.")
                        .font(.caption)
                    Button("Organize existing media") {
                        proposedRoot = URL(fileURLWithPath: videoManager.mediaStoragePath)
                        showMoveConfirmation = true
                    }
                    .disabled(videoManager.isProcessing)
                }
                if videoManager.isMovingStorage {
                    HStack { ProgressView().controlSize(.small); Text("Copying and verifying files…").font(.caption) }
                }
                if let error = videoManager.storageError {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .confirmationDialog("Move PocketSync library?", isPresented: $showMoveConfirmation, titleVisibility: .visible) {
            Button("Move and update library") {
                if let proposedRoot { videoManager.moveStorage(to: proposedRoot) }
            }
            Button("Cancel", role: .cancel) { proposedRoot = nil }
        } message: {
            Text("Destination: \(proposedRoot?.path ?? "")\n\nPocketSync will copy and verify managed originals, conversions, and local device caches, and transfer video_index.json and its Backups folder. It will then switch to the new library and remove the old managed media copies. The previous catalog is retained for recovery. Referenced originals and physical SD-card files stay in place. Missing files stop the move; existing destination files are never overwritten.")
        }
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose PocketSync storage location"
        panel.message = "Choose a parent folder, such as Movies. PocketSync will use a dedicated PocketSync subfolder. You can also select an existing PocketSync folder."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: videoManager.mediaStoragePath).deletingLastPathComponent()
        if panel.runModal() == .OK, let folder = panel.url {
            proposedRoot = folder.lastPathComponent == "PocketSync" ? folder : folder.appendingPathComponent("PocketSync", isDirectory: true)
            showMoveConfirmation = true
        }
    }
}
