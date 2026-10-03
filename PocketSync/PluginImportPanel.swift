import SwiftUI
import AppKit

extension Notification.Name {
    static let pocketSyncRefreshPlugins = Notification.Name("PocketSync.refreshPlugins")
}

struct PluginImportPanel: View {
    @ObservedObject var videoManager: VideoManager
    @State private var plugins: [InstalledPlugin] = []
    @State private var selectedID = ""
    @State private var locator = ""
    @State private var previousDiscoveryMessages: [String] = []

    private var selected: InstalledPlugin? { plugins.first { $0.id == selectedID } }

    var body: some View {
        Group {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PLUGINS")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                        Spacer()
                        Button("Refresh") { reload() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .disabled(videoManager.isProcessing)
                    }
                    if !plugins.isEmpty {
                    Picker("Import with", selection: $selectedID) {
                        ForEach(plugins) { plugin in
                            Text(plugin.manifest.name).tag(plugin.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(videoManager.isProcessing)
                    .help(pluginDetails)
                    HStack(spacing: 8) {
                        TextField("Source URL or input", text: $locator)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Plugin source URL or input")
                            .disabled(videoManager.isProcessing)
                            .onSubmit { runSelectedPlugin() }
                        Button("Run") { runSelectedPlugin() }
                            .disabled(!canRun)
                            .help(pluginDetails)
                    }
                    if videoManager.isPluginImportRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Importing…").font(.caption)
                            Spacer()
                            Button("Cancel") { videoManager.cancelPluginImport() }
                        }
                    }
                    }
                }
                .foregroundStyle(PocketStyle.text)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: PocketStyle.panelCorner, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: PocketStyle.panelCorner, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: PocketStyle.thinLine)
                        )
                )
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .pocketSyncRefreshPlugins)) { _ in
            reload()
        }
    }

    private var canRun: Bool {
        !videoManager.isProcessing && selected != nil &&
        !locator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Keep access disclosures available without a permanent block of text.
    private var pluginDetails: String {
        guard let selected else { return "Select an import plugin." }
        let permissions = selected.manifest.permissions.map(\.rawValue).sorted().joined(separator: ", ")
        return "\(selected.manifest.name) runs with your user account’s access. Only run plugins you trust. Declared access: \(permissions)."
    }

    private func runSelectedPlugin() {
        guard canRun, let selected else { return }
        videoManager.importFromPlugin(selected, locator: locator)
    }

    private func reload() {
        guard !videoManager.isProcessing else { return }
        let result = PluginService().discover()
        plugins = result.plugins
        if !plugins.contains(where: { $0.id == selectedID }) { selectedID = plugins.first?.id ?? "" }
        for message in result.messages where !previousDiscoveryMessages.contains(message) {
            videoManager.appendLog("Plugin discovery: \(message)")
        }
        previousDiscoveryMessages = result.messages
    }
}
