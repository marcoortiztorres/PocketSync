//
//  PlayerPageView.swift
//  PocketSync
//

import SwiftUI
import AVKit

struct PlayerPageView: View {
    let records: [VideoRecord]
    let selectedRecord: VideoRecord?
    let selectedVideoURL: URL?

    @Binding var selectedRecordID: UUID?
    @Binding var isPlaying: Bool
    @Binding var playbackProgress: Double
    @Binding var playbackDuration: Double

    let player: AVPlayer

    let isShuffleEnabled: Bool
    let toggleShuffle: () -> Void

    let togglePlayPause: () -> Void
    let selectNextVideo: () -> Void
    let selectPreviousVideo: () -> Void
    let restartVideo: () -> Void
    let openMenu: () -> Void
    let seek: (Double) -> Void

    @State private var isSearchVisible = false

    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0
    @State private var isShowingFullScreenPlayer = false

    private var timelineProgress: Binding<Double> {
        Binding {
            isScrubbing ? scrubProgress : playbackProgress
        } set: { newValue in
            scrubProgress = clampedProgress(newValue)
            playbackProgress = scrubProgress
        }
    }

    var body: some View {
        VStack(spacing: PocketStyle.gap) {
            playerPanel
            queuePanel
        }
        .background(
            FullScreenPlayerPresenter(
                player: player,
                title: selectedRecord?.displayName ?? "PocketSync",
                isPresented: $isShowingFullScreenPlayer
            )
            .frame(width: 0, height: 0)
        )
    }

    private var playerPanel: some View {
        Y2KPanel(title: "top screen", tint: PocketStyle.bubblePink) {
            HStack(spacing: 18) {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: PocketStyle.screenCorner, style: .continuous)
                            .fill(Color.black.opacity(0.88))
                            .overlay(
                                RoundedRectangle(cornerRadius: PocketStyle.screenCorner, style: .continuous)
                                    .stroke(Color.black.opacity(0.85), lineWidth: 4)
                            )

                        if selectedVideoURL != nil {
                            VideoPreviewPlayer(player: player)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(8)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(PocketStyle.softPink)

                                Text("No playable video selected")
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.86))
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Slider(value: timelineProgress, in: 0...max(playbackDuration, 1)) { editing in
                            if editing {
                                if !isScrubbing {
                                    isScrubbing = true
                                    scrubProgress = playbackProgress
                                }
                            } else {
                                let target = scrubProgress
                                isScrubbing = false
                                playbackProgress = target
                                seek(target)
                            }
                        }

                        Button {
                            isShowingFullScreenPlayer = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(PocketStyle.bubblePink)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedVideoURL == nil)
                        .help("Full screen")
                    }

                    HStack {
                        Text(formatTime(isScrubbing ? scrubProgress : playbackProgress))
                        Spacer()
                        Text(formatTime(playbackDuration))
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(PocketStyle.mutedText)
                }
                .frame(height: PocketStyle.playerHeight)

                VStack(spacing: 12) {
                    playerWheel

                    Text(selectedRecord?.displayName ?? "No video")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(PocketStyle.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    Text(selectedRecord?.status.rawValue ?? "waiting")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PocketStyle.mutedText)
                        .tracking(1.0)

                    HStack(spacing: 8) {
                        MediaChip(label: "M", active: selectedRecord?.highResPath != nil)
                        MediaChip(label: "A", active: selectedRecord?.aviPath != nil)
                        MediaChip(label: "S", active: selectedRecord?.threeDSPath != nil)
                    }

                    MiniButton(
                        title: isShuffleEnabled ? "shuffle on" : "shuffle off",
                        icon: "shuffle",
                        action: toggleShuffle
                    )
                }
                .frame(width: 230)
            }
        }
    }

    private var playerWheel: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .stroke(PocketStyle.border.opacity(0.35), lineWidth: PocketStyle.borderWidth)
                )
                .frame(width: 190, height: 190)

            Circle()
                .fill(PocketStyle.softPink.opacity(0.42))
                .background(.thinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(PocketStyle.border.opacity(0.25), lineWidth: PocketStyle.thinLine)
                )
                .frame(width: 72, height: 72)

            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(PocketStyle.bubblePink)
                    .frame(width: 72, height: 72)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: selectPreviousVideo) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(PocketStyle.bubblePink)
                    .frame(width: 54, height: 72)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: -63)

            Button(action: selectNextVideo) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(PocketStyle.bubblePink)
                    .frame(width: 54, height: 72)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 63)

            Button(action: openMenu) {
                Text("MENU")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(PocketStyle.bubblePink.opacity(0.8))
                    .frame(width: 90, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(y: -64)

            Button(action: restartVideo) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(PocketStyle.bubblePink.opacity(0.75))
                    .frame(width: 80, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(y: 64)
        }
    }

    private var queuePanel: some View {
        Y2KPanel(
            title: isShuffleEnabled ? "shuffled queue" : "song queue",
            tint: PocketStyle.lavender,
            searchAction: { isSearchVisible = true }
        ) {
            SearchableVideoList(records: records, isSearchVisible: $isSearchVisible,
                                height: PocketStyle.queueHeight, spacing: 8) { record, number in
                queueRow(record, number: number)
            }
        }
    }

    private func queueRow(_ record: VideoRecord, number: Int) -> some View {
        let isSelected = selectedRecordID == record.id

        return Button {
            selectedRecordID = record.id
        } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(isSelected ? PocketStyle.text : PocketStyle.mutedText)
                    .frame(width: 34)

                RoundedRectangle(cornerRadius: PocketStyle.cardCorner, style: .continuous)
                    .fill(isSelected ? PocketStyle.bubblePink.opacity(0.55) : PocketStyle.softPink.opacity(0.75))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: isSelected ? "speaker.wave.2.fill" : "video.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(PocketStyle.text)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(record.displayName)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(PocketStyle.text)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(record.status.rawValue)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(PocketStyle.mutedText)

                        if let fileName = record.threeDSFileName {
                            Text(fileName)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(PocketStyle.mutedText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    MediaChip(label: "M", active: record.quickTimePath != nil)
                    MediaChip(label: "A", active: record.aviPath != nil)
                    MediaChip(label: "S", active: record.threeDSPath != nil)
                }

                Image(systemName: isSelected ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PocketStyle.bubblePink)
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: PocketStyle.cardCorner, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.88 : 0.56))
                    .overlay(
                        RoundedRectangle(cornerRadius: PocketStyle.cardCorner, style: .continuous)
                            .stroke(isSelected ? PocketStyle.border.opacity(0.85) : Color.white.opacity(0.65), lineWidth: PocketStyle.borderWidth)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }

        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60

        return String(format: "%d:%02d", minutes, secs)
    }

    private func clampedProgress(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return min(max(seconds, 0), max(playbackDuration, 1))
    }
}

struct VideoPreviewPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.showsSharingServiceButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player = nil
    }
}

struct FullScreenPlayerSheet: View {
    let player: AVPlayer
    let title: String
    @Binding var isPresented: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VideoFullScreenPlayer(player: player)
                .ignoresSafeArea()

            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .lineLimit(1)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Exit full screen")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .padding(18)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct VideoFullScreenPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsSharingServiceButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

struct FullScreenPlayerPresenter: NSViewRepresentable {
    let player: AVPlayer
    let title: String
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            context.coordinator.presentOrUpdate(player: player, title: title)
        } else {
            context.coordinator.dismiss()
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        @Binding private var isPresented: Bool
        var title: String = "PocketSync"
        private var window: NSWindow?
        private var hostingController: NSHostingController<FullScreenPlayerSheet>?
        private var escapeMonitor: Any?

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func presentOrUpdate(player: AVPlayer, title: String) {
            self.title = title

            guard window == nil else {
                updateContent(player: player, title: title)
                return
            }

            let content = FullScreenPlayerSheet(
                player: player,
                title: title,
                isPresented: $isPresented
            )

            let hostingController = NSHostingController(rootView: content)
            let fullScreenWindow = EscapeClosingWindow(
                contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            fullScreenWindow.onEscape = { [weak self] in
                self?.closeFromEscape()
            }
            fullScreenWindow.title = title
            fullScreenWindow.contentViewController = hostingController
            fullScreenWindow.delegate = self
            fullScreenWindow.isReleasedWhenClosed = false
            fullScreenWindow.makeKeyAndOrderFront(nil)
            fullScreenWindow.toggleFullScreen(nil)

            self.hostingController = hostingController
            window = fullScreenWindow
            installEscapeMonitor()
        }

        func dismiss() {
            guard let window else { return }
            self.window = nil
            hostingController = nil
            removeEscapeMonitor()
            window.delegate = nil
            window.close()
        }

        func windowDidExitFullScreen(_ notification: Notification) {
            closeFromEscape()
        }

        func windowWillClose(_ notification: Notification) {
            window = nil
            hostingController = nil
            removeEscapeMonitor()
            isPresented = false
        }

        private func updateContent(player: AVPlayer, title: String) {
            window?.title = title
            hostingController?.rootView = FullScreenPlayerSheet(
                player: player,
                title: title,
                isPresented: $isPresented
            )
        }

        private func closeFromEscape() {
            DispatchQueue.main.async {
                self.isPresented = false
                self.dismiss()
            }
        }

        private func installEscapeMonitor() {
            removeEscapeMonitor()

            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.window != nil,
                      event.keyCode == 53 else {
                    return event
                }

                self.closeFromEscape()
                return nil
            }
        }

        private func removeEscapeMonitor() {
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
                self.escapeMonitor = nil
            }
        }
    }
}

private final class EscapeClosingWindow: NSWindow {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}
