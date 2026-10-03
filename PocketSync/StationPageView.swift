//
//  StationPageView.swift
//  PocketSync
//

import SwiftUI
import AppKit

struct StationPageView: View {
    @ObservedObject var videoManager: VideoManager

    let records: [VideoRecord]
    @Binding var selectedRecordID: UUID?

    @Binding var folderPath: String
    @Binding var outputLog: String
    @Binding var showVideoLog: Bool
    @Binding var showMusicLog: Bool

    let selectedRecord: VideoRecord?
    let goBack: () -> Void
    let chooseVideos: () -> Void
    let importDroppedURLs: ([URL]) -> Void
    let editMetadata: () -> Void
    let selectFolder: () -> Void
    let runConversion: (Bool) -> Void
    let cleanAppleDouble: () -> Void

    @State private var isSearchVisible = false

    @State private var showDeleteConfirmation = false
    @State private var isImportDropTargeted = false

    private let streamWidth: CGFloat = 300
    private let streamHeight: CGFloat = 180
    private let leftColumnWidth: CGFloat = 390

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: PocketStyle.gap) {
                stationHeader

                HStack(alignment: .top, spacing: PocketStyle.gap) {
                    VStack(spacing: PocketStyle.gap) {
                        importPanel
                        PluginImportPanel(videoManager: videoManager)
                        selectedVideoPanel
                    }
                    .frame(width: leftColumnWidth)

                    VStack(spacing: PocketStyle.gap) {
                        StorageLocationPanel(videoManager: videoManager)
                        actionPanel
                        musicPanel
                        logPanel
                    }
                }
            }
            .padding(.bottom, PocketStyle.pagePadding)
        }
        .alert("Delete selected video?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                videoManager.deleteVideo(recordID: selectedRecord?.id)
            }
        } message: {
            Text("PocketSync will remove this item and its generated or managed copies. Referenced original files will not be deleted.")
        }
    }

    private var stationHeader: some View {
        Y2KPanel(title: "livestream", tint: PocketStyle.bubblePink) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(videoManager.isProcessing ? "PocketSync is working..." : "PocketSync is idle")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(PocketStyle.text)
                        .lineLimit(1)

                    Text(videoManager.isProcessing ? "Importing, converting, or syncing. Don’t close the app yet." : "Drop local videos or folders into the import panel to start.")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PocketStyle.mutedText)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Pill(title: videoManager.isProcessing ? "live" : "standby", fill: videoManager.isProcessing ? PocketStyle.bubblePink : PocketStyle.lavender)
                        Pill(title: "\(videoManager.records.count) queued", fill: PocketStyle.mint)
                        MiniButton(title: "player", icon: "play.rectangle.fill", action: goBack)
                    }

                    HStack(spacing: 8) {
                        MiniButton(
                            title: videoManager.needsFirstTimeSDSync ? "first sync" : "sync",
                            icon: videoManager.needsFirstTimeSDSync ? "externaldrive.fill" : "arrow.triangle.2.circlepath.circle.fill"
                        ) {
                            videoManager.syncSDCard()
                        }
                        .disabled(videoManager.isProcessing)

                        MiniButton(title: "scan", icon: "magnifyingglass") {
                            videoManager.reconcileSDCardOnly()
                        }
                        .disabled(videoManager.isProcessing)
                    }
                }

                Spacer(minLength: 10)

                livestreamWindow
            }
        }
    }

    private var livestreamWindow: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: PocketStyle.screenCorner, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: PocketStyle.screenCorner, style: .continuous)
                        .stroke(PocketStyle.bubblePink.opacity(0.65), lineWidth: 2)
                )

            AnimatedGIFView(
                name: videoManager.isProcessing
                    ? "idol_working_gif_placeholder"
                    : "idol_idle_gif_placeholder"
            )
            .frame(width: streamWidth - 16, height: streamHeight - 16)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: PocketStyle.screenCorner - 2,
                    style: .continuous
                )
            )
            .padding(8)
            .opacity(0.92)

            HStack(spacing: 6) {
                Circle()
                    .fill(videoManager.isProcessing ? PocketStyle.bubblePink : PocketStyle.mint)
                    .frame(width: 8, height: 8)

                Text(videoManager.isProcessing ? "LIVE · PROCESSING" : "LIVE · IDLE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .padding(12)
        }
        .frame(width: streamWidth, height: streamHeight)
    }

    private var importPanel: some View {
        Y2KPanel(title: "import videos", tint: isImportDropTargeted ? PocketStyle.bubblePink : PocketStyle.lavender) {
            Button(action: chooseVideos) {
                VStack(spacing: 10) {
                    Image(systemName: isImportDropTargeted ? "arrow.down.circle.fill" : "plus.rectangle.on.folder.fill")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(PocketStyle.bubblePink)

                    Text(isImportDropTargeted ? "DROP TO IMPORT" : "DROP VIDEOS OR FOLDERS HERE")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(PocketStyle.text)

                    Text("or click to choose files")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(PocketStyle.mutedText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: PocketStyle.cardCorner, style: .continuous)
                        .fill(isImportDropTargeted ? PocketStyle.mint.opacity(0.70) : Color.white.opacity(0.58))
                        .overlay(
                            RoundedRectangle(cornerRadius: PocketStyle.cardCorner, style: .continuous)
                                .stroke(
                                    isImportDropTargeted ? PocketStyle.bubblePink : PocketStyle.border.opacity(0.45),
                                    style: StrokeStyle(lineWidth: isImportDropTargeted ? 3 : 1.25, dash: [8, 6])
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(videoManager.isProcessing)
            .dropDestination(for: URL.self) { urls, _ in
                guard !videoManager.isProcessing, !urls.isEmpty else { return false }
                importDroppedURLs(urls)
                return true
            } isTargeted: { targeted in
                isImportDropTargeted = targeted
            }
        }
    }

    private var selectedVideoPanel: some View {
        Y2KPanel(title: "selected video", tint: PocketStyle.lavender,
                 searchAction: { isSearchVisible = true }) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedRecord?.displayName ?? "No video selected")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(PocketStyle.text)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let selectedRecord {
                            Text(statusLabel(selectedRecord.status))
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(PocketStyle.mutedText)
                                .lineLimit(1)

                            if let fileName = selectedRecord.threeDSFileName {
                                Text(fileName)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(PocketStyle.mutedText)
                                    .lineLimit(1)
                            }

                            if selectedRecord.isIgnoredForSync == true {
                                Text("NO SYNC")
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundStyle(PocketStyle.bubblePink)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    MiniButton(title: "edit", icon: "pencil.circle.fill", action: editMetadata)
                        .disabled(videoManager.isProcessing || selectedRecord == nil)

                    MiniButton(
                        title: selectedRecord?.isFavorite == true ? "favorite" : "add favorite",
                        icon: selectedRecord?.isFavorite == true ? "heart.fill" : "heart"
                    ) {
                        videoManager.toggleFavorite(recordID: selectedRecord?.id)
                    }
                    .disabled(videoManager.isProcessing || selectedRecord == nil)

                    MiniButton(
                        title: selectedRecord?.isIgnoredForSync == true ? "allow sync" : "ignore sync",
                        icon: selectedRecord?.isIgnoredForSync == true ? "sdcard.fill" : "xmark.circle.fill"
                    ) {
                        videoManager.toggleSyncIgnored(recordID: selectedRecord?.id)
                    }
                    .disabled(videoManager.isProcessing || selectedRecord == nil)

                    MiniButton(title: "delete", icon: "trash.fill") {
                        showDeleteConfirmation = true
                    }
                    .disabled(videoManager.isProcessing || selectedRecord == nil)
                }

                SearchableVideoList(records: records, isSearchVisible: $isSearchVisible,
                                    height: 200, spacing: 6) { record, number in
                    stationQueueRow(record, number: number)
                }
            }
        }
    }

    private func statusLabel(_ status: VideoStatus) -> String {
        switch status {
        case .removedFrom3DS:
            return "removed"
        case .convertingQuickTime:
            return "converting mac"
        case .convertedQuickTime:
            return "mac ready"
        case .convertingAVI:
            return "converting avi"
        case .convertedAVI:
            return "avi ready"
        case .copiedTo3DS:
            return "on 3ds"
        default:
            return status.rawValue
        }
    }

    private func stationQueueRow(_ record: VideoRecord, number: Int) -> some View {
        let isSelected = selectedRecordID == record.id

        return Button {
            selectedRecordID = record.id
        } label: {
            HStack(spacing: 8) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(isSelected ? PocketStyle.text : PocketStyle.mutedText)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.displayName)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(PocketStyle.text)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(record.status.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(PocketStyle.mutedText)
                            .lineLimit(1)

                        if let fileName = record.threeDSFileName {
                            Text(fileName)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(PocketStyle.mutedText)
                                .lineLimit(1)
                        }

                        if record.isIgnoredForSync == true {
                            Text("NO SYNC")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(PocketStyle.bubblePink)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 6)

                if record.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PocketStyle.bubblePink)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PocketStyle.bubblePink)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: PocketStyle.cardCorner, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.86 : 0.50))
                    .overlay(
                        RoundedRectangle(cornerRadius: PocketStyle.cardCorner, style: .continuous)
                            .stroke(isSelected ? PocketStyle.border.opacity(0.72) : Color.white.opacity(0.45), lineWidth: PocketStyle.thinLine)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var actionPanel: some View {
        Y2KPanel(title: "controls", tint: PocketStyle.softPink) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    StationIconButton(title: "import", icon: "plus.rectangle.on.folder.fill", fill: PocketStyle.mint) {
                        chooseVideos()
                    }
                    .disabled(videoManager.isProcessing)

                    StationIconButton(title: "refresh", icon: "arrow.clockwise.circle.fill", fill: PocketStyle.lavender) {
                        videoManager.refresh()
                    }

                    StationIconButton(title: "clear", icon: "trash.circle.fill", fill: PocketStyle.sky) {
                        videoManager.clearLog()
                    }
                }

                HStack(spacing: 8) {
                    StationIconButton(title: "re qt", icon: "film.fill", fill: PocketStyle.lavender) {
                        videoManager.convertSelectedToMac(recordID: selectedRecord?.id)
                    }
                    .disabled(videoManager.isProcessing || selectedRecord == nil)

                    StationIconButton(title: "avi", icon: "opticaldiscdrive.fill", fill: PocketStyle.softPink) {
                        if let id = selectedRecord?.id {
                            videoManager.convertSelectedToAVI(recordID: id)
                        }
                    }
                    .disabled(videoManager.isProcessing || selectedRecord == nil)

                    StationIconButton(title: "sd", icon: "sdcard.fill", fill: PocketStyle.mint) {
                        videoManager.syncSelectedToSDCard(recordID: selectedRecord?.id)
                    }
                    .disabled(videoManager.isProcessing || selectedRecord == nil)

                    StationIconButton(title: "sync all", icon: "sparkles", fill: PocketStyle.sky) {
                        videoManager.syncAllPendingToSDCard()
                    }
                    .disabled(videoManager.isProcessing)
                }
            }
        }
    }

    private var musicPanel: some View {
        Y2KPanel(title: "music station", tint: PocketStyle.mint) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(folderPath)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PocketStyle.mutedText)
                        .lineLimit(1)

                    Spacer()

                    MiniButton(title: "choose", icon: "folder.fill", action: selectFolder)
                }

                HStack(spacing: 8) {
                    StationIconButton(title: "mirror", icon: "music.note.list", fill: PocketStyle.lavender) {
                        runConversion(true)
                    }

                    StationIconButton(title: "in place", icon: "waveform", fill: PocketStyle.softPink) {
                        runConversion(false)
                    }

                    StationIconButton(title: "clean", icon: "trash.fill", fill: PocketStyle.sky) {
                        cleanAppleDouble()
                    }
                }
            }
        }
    }

    private var logPanel: some View {
        Y2KPanel(title: "mini log", tint: PocketStyle.sky) {
            VStack(spacing: 8) {
                logSection(
                    title: "video",
                    isExpanded: $showVideoLog,
                    text: videoManager.logOutput.isEmpty ? "No video messages yet." : videoManager.logOutput
                )

                logSection(
                    title: "music",
                    isExpanded: $showMusicLog,
                    text: outputLog.isEmpty ? "No music messages yet." : outputLog
                )
            }
        }
    }

    private func logSection(title: String, isExpanded: Binding<Bool>, text: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(PocketStyle.text)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .buttonStyle(.plain)
                .help("Copy the entire \(title) log")
                .accessibilityLabel("Copy \(title) log")

                Button {
                    isExpanded.wrappedValue.toggle()
                } label: {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .foregroundStyle(PocketStyle.border)
                        .frame(width: 30, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isExpanded.wrappedValue {
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(PocketStyle.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 70)
                .background(
                    RoundedRectangle(cornerRadius: PocketStyle.cardCorner, style: .continuous)
                        .fill(Color.white.opacity(0.62))
                )
            }
        }
    }
}

private struct StationIconButton: View {
    let title: String
    let icon: String
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .black))

                Text(title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(PocketStyle.text)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: PocketStyle.buttonCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.62), fill.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PocketStyle.buttonCorner, style: .continuous)
                            .stroke(Color.white.opacity(0.76), lineWidth: PocketStyle.thinLine)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
