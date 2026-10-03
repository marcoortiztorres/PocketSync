//
//  ContentView.swift
//  PocketSync
//

import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

private struct MetadataEditorTarget: Identifiable {
    let id: UUID
}

struct ContentView: View {
    @StateObject private var videoManager = VideoManager()

    @State private var currentPage: PocketPage = .player

    @State private var folderPath: String = "No folder selected"
    @State private var outputLog: String = ""
    @State private var selectedRecordID: UUID?
    @State private var showVideoLog: Bool = true
    @State private var showMusicLog: Bool = false

    @State private var player = AVPlayer()
    @State private var isPlaying: Bool = false

    @State private var isShuffleEnabled: Bool = false
    @State private var shuffledRecordIDs: [UUID] = []

    @State private var playbackProgress: Double = 0
    @State private var playbackDuration: Double = 1
    @State private var timeObserver: Any?
    @State private var isDropTargeted = false
    @State private var pendingImportURLs: [URL] = []
    @State private var showImportModeChoice = false
    @State private var metadataEditorTarget: MetadataEditorTarget?
    @State private var pendingEditorRecordID: UUID?

    private var selectedRecord: VideoRecord? {
        videoManager.records.first(where: { $0.id == selectedRecordID }) ?? videoManager.records.first
    }

    private var playbackRecords: [VideoRecord] {
        guard isShuffleEnabled else { return videoManager.records }

        let lookup = Dictionary(uniqueKeysWithValues: videoManager.records.map { ($0.id, $0) })
        let ordered = shuffledRecordIDs.compactMap { lookup[$0] }
        let missing = videoManager.records.filter { !shuffledRecordIDs.contains($0.id) }

        return ordered + missing
    }

    private var selectedVideoURL: URL? {
        if let quickTimePath = selectedRecord?.quickTimePath,
           FileManager.default.fileExists(atPath: quickTimePath) {
            return URL(fileURLWithPath: quickTimePath)
        }

        if let highResPath = selectedRecord?.highResPath,
           FileManager.default.fileExists(atPath: highResPath) {
            return URL(fileURLWithPath: highResPath)
        }

        if let aviPath = selectedRecord?.aviPath,
           FileManager.default.fileExists(atPath: aviPath) {
            return URL(fileURLWithPath: aviPath)
        }

        return nil
    }

    var body: some View {
        ZStack {
            Group {
                switch currentPage {
                case .player:
                    playerPage
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))

                case .station:
                    stationPage
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: currentPage)
            .padding(PocketStyle.pagePadding)
        }
        .frame(minWidth: 850, idealWidth: 870, minHeight: 860, idealHeight: 860)
        .background { background }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: PocketStyle.panelCorner, style: .continuous)
                    .fill(PocketStyle.mint.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: PocketStyle.panelCorner, style: .continuous)
                            .stroke(PocketStyle.bubblePink, style: StrokeStyle(lineWidth: 4, dash: [10, 7]))
                    )
                    .overlay {
                        Label("Drop videos or folders to import", systemImage: "square.and.arrow.down.fill")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(PocketStyle.text)
                            .padding(24)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(PocketStyle.pagePadding)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            requestImport(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .onAppear {
            selectedRecordID = selectedRecordID ?? videoManager.records.first?.id
            loadSelectedVideo(autoplay: false)
        }
        .onChange(of: videoManager.isMovingStorage) { _, moving in
            if moving { player.pause(); isPlaying = false }
        }
        .onChange(of: videoManager.records) { _, newValue in
            handleRecordsChange(newValue)
        }
        .onChange(of: selectedRecordID) { previousID, _ in
            // The initial library selection should load a preview without playing.
            loadSelectedVideo(autoplay: previousID != nil)
        }
        .onChange(of: videoManager.pendingMetadataRecordIDs) { _, _ in
            presentNextPendingMetadata()
        }
        .confirmationDialog(
            "How should PocketSync import these videos?",
            isPresented: $showImportModeChoice,
            titleVisibility: .visible
        ) {
            Button("Reference original files") {
                beginImport(mode: .referenceOriginals)
            }
            Button("Copy into PocketSync library") {
                beginImport(mode: .copyIntoLibrary)
            }
            Button("Cancel", role: .cancel) {
                pendingImportURLs = []
            }
        } message: {
            Text("Referencing uses no extra disk space. Copying creates PocketSync-managed copies in your selected library storage folder.")
        }
        .sheet(item: $metadataEditorTarget, onDismiss: metadataEditorDidDismiss) { target in
            let recordID = target.id
            if let record = videoManager.records.first(where: { $0.id == recordID }) {
                MetadataEditorView(
                    record: record,
                    onSave: { metadata, linkedURL in
                        try videoManager.saveMetadata(
                            recordID: recordID,
                            metadata: metadata,
                            linkedWebURL: linkedURL
                        )
                    },
                    onClose: { closeMetadataEditor(recordID: recordID) }
                )
            } else {
                Text("This library item is no longer available.")
                    .padding()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            selectNextVideo(autoplay: true)
        }
    }

    private var playerPage: some View {
        PlayerPageView(
            records: playbackRecords,
            selectedRecord: selectedRecord,
            selectedVideoURL: selectedVideoURL,
            selectedRecordID: $selectedRecordID,
            isPlaying: $isPlaying,
            playbackProgress: $playbackProgress,
            playbackDuration: $playbackDuration,
            player: player,
            isShuffleEnabled: isShuffleEnabled,
            toggleShuffle: toggleShuffle,
            togglePlayPause: togglePlayPause,
            selectNextVideo: { selectNextVideo(autoplay: true) },
            selectPreviousVideo: { selectPreviousVideo(autoplay: true) },
            restartVideo: restartVideo,
            openMenu: { currentPage = .station },
            seek: seek
        )
    }

    private var stationPage: some View {
        StationPageView(
            videoManager: videoManager,
            records: videoManager.records,
            selectedRecordID: $selectedRecordID,
            folderPath: $folderPath,
            outputLog: $outputLog,
            showVideoLog: $showVideoLog,
            showMusicLog: $showMusicLog,
            selectedRecord: selectedRecord,
            goBack: { currentPage = .player },
            chooseVideos: chooseVideos,
            importDroppedURLs: requestImport,
            editMetadata: {
                if let id = selectedRecord?.id {
                    metadataEditorTarget = MetadataEditorTarget(id: id)
                }
            },
            selectFolder: selectFolder,
            runConversion: runConversion,
            cleanAppleDouble: cleanAppleDouble
        )
    }

    private var background: some View {
        ZStack {
            Image("halftone_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .opacity(0.85)

            LinearGradient(
                colors: [
                    PocketStyle.softPink.opacity(0.25),
                    PocketStyle.sky.opacity(0.30),
                    Color.white.opacity(0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    sticker("sparkle")
                    Spacer()
                    sticker("heart.fill")
                    Spacer()
                    sticker("sparkles")
                }
                Spacer()
                HStack {
                    sticker("heart.fill")
                    Spacer()
                    sticker("sparkle")
                    Spacer()
                    sticker("heart.fill")
                }
            }
            .padding(32)
        }
    }

    private func chooseVideos() {
        let panel = NSOpenPanel()
        panel.title = "Import Videos"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie]

        if panel.runModal() == .OK {
            requestImport(panel.urls)
        }
    }

    private func requestImport(_ urls: [URL]) {
        guard !urls.isEmpty, !videoManager.isProcessing else { return }
        pendingImportURLs = urls
        showImportModeChoice = true
    }

    private func handleRecordsChange(_ newValue: [VideoRecord]) {
        if let currentID = selectedRecordID {
            let selectionStillExists = newValue.contains { record in
                record.id == currentID
            }
            if !selectionStillExists {
                selectedRecordID = newValue.first?.id
            }
        } else {
            selectedRecordID = newValue.first?.id
        }

        if isShuffleEnabled {
            rebuildShuffleKeepingCurrent()
        }
        let loadedURL = (player.currentItem?.asset as? AVURLAsset)?.url
        if loadedURL != selectedVideoURL { loadSelectedVideo(autoplay: isPlaying) }
    }

    private func beginImport(mode: LocalMediaImportMode) {
        let urls = pendingImportURLs
        pendingImportURLs = []
        videoManager.importLocalMedia(urls: urls, mode: mode)
    }

    private func presentNextPendingMetadata() {
        guard metadataEditorTarget == nil,
              let nextID = videoManager.pendingMetadataRecordIDs.first else { return }
        selectedRecordID = nextID
        pendingEditorRecordID = nextID
        metadataEditorTarget = MetadataEditorTarget(id: nextID)
    }

    private func closeMetadataEditor(recordID: UUID) {
        videoManager.finishPendingMetadata(recordID: recordID)
        pendingEditorRecordID = nil
        metadataEditorTarget = nil
        DispatchQueue.main.async {
            presentNextPendingMetadata()
        }
    }

    private func metadataEditorDidDismiss() {
        if let pendingEditorRecordID {
            videoManager.finishPendingMetadata(recordID: pendingEditorRecordID)
            self.pendingEditorRecordID = nil
        }
        DispatchQueue.main.async {
            presentNextPendingMetadata()
        }
    }

    private func sticker(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(PocketStyle.bubblePink.opacity(0.75))
    }

    private func loadSelectedVideo(autoplay: Bool) {
        guard let url = selectedVideoURL else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            return
        }

        player.replaceCurrentItem(with: AVPlayerItem(url: url))

        playbackProgress = 0
        playbackDuration = 1
        setupPlaybackObserver()

        if autoplay {
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    private func togglePlayPause() {
        guard selectedVideoURL != nil else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func restartVideo() {
        player.seek(to: .zero)
        player.play()
        isPlaying = true
    }

    private func seek(_ seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
    }

    private func toggleShuffle() {
        isShuffleEnabled.toggle()

        if isShuffleEnabled {
            rebuildShuffleKeepingCurrent()
        } else {
            shuffledRecordIDs = []
        }
    }

    private func rebuildShuffleKeepingCurrent() {
        let currentID = selectedRecordID
        var shuffled = videoManager.records.map(\.id).shuffled()

        if let currentID,
           let index = shuffled.firstIndex(of: currentID) {
            shuffled.remove(at: index)
            shuffled.insert(currentID, at: 0)
        }

        shuffledRecordIDs = shuffled
    }

    private func selectNextVideo(autoplay: Bool) {
        let records = playbackRecords
        guard !records.isEmpty else { return }

        let currentID = selectedRecord?.id
        let currentIndex = records.firstIndex { $0.id == currentID } ?? -1
        let nextIndex = (currentIndex + 1) % records.count

        selectedRecordID = records[nextIndex].id

        if autoplay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                player.play()
                isPlaying = true
            }
        }
    }

    private func selectPreviousVideo(autoplay: Bool) {
        let records = playbackRecords
        guard !records.isEmpty else { return }

        let currentID = selectedRecord?.id
        let currentIndex = records.firstIndex { $0.id == currentID } ?? 0
        let previousIndex = currentIndex == 0 ? records.count - 1 : currentIndex - 1

        selectedRecordID = records[previousIndex].id

        if autoplay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                player.play()
                isPlaying = true
            }
        }
    }

    private func setupPlaybackObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)

        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            playbackProgress = time.seconds.isFinite ? time.seconds : 0

            if let duration = player.currentItem?.duration.seconds,
               duration.isFinite,
               duration > 0 {
                playbackDuration = duration
            }
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            folderPath = panel.url?.path ?? ""
        }
    }

    private func runConversion(mirror: Bool) {
        guard folderPath != "No folder selected" else { return }

        let script: String

        if mirror {
            script = """
            find "\(folderPath)" -type f ! -name "._*" \\( -iname "*.aif" -o -iname "*.aiff" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.m4a" \\) -exec sh -c '
            src="\\$1"
            root="\(folderPath)"
            rel="\\${src#\\$root/}"
            dir="\\$(dirname "\\$rel")"
            base="\\$(basename "\\${src%.*}")"
            outdir="\\$root/mp3/\\$dir"
            mkdir -p "\\$outdir"
            ffmpeg -y -i "\\$src" -map 0:a:0 -codec:a libmp3lame -qscale:a 2 "\\$outdir/\\$base.mp3"
            ' sh {} \\;
            """
        } else {
            script = """
            find "\(folderPath)" -type f ! -name "._*" \\( -iname "*.aif" -o -iname "*.aiff" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.m4a" \\) -exec sh -c '
            src="\\$1"
            out="\\${src%.*}.mp3"
            ffmpeg -y -i "\\$src" -map 0:a:0 -codec:a libmp3lame -qscale:a 2 "\\$out"
            ' sh {} \\;
            """
        }

        runShell(script)
    }

    private func cleanAppleDouble() {
        guard folderPath != "No folder selected" else { return }

        let script = """
        find "\(folderPath)" -name "._*" -type f -delete
        """

        runShell(script)
    }

    private func runShell(_ command: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let output = String(data: data, encoding: .utf8),
                  !output.isEmpty else { return }

            DispatchQueue.main.async {
                outputLog += output
            }
        }

        do {
            try process.run()
        } catch {
            outputLog += "\nFailed to run shell command: \(error.localizedDescription)\n"
        }
    }
}
