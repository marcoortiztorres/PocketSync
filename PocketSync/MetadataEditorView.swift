//
//  MetadataEditorView.swift
//  PocketSync
//

import SwiftUI

struct MetadataEditorView: View {
    let record: MediaLibraryItem
    let onSave: (MediaMetadata, URL?) throws -> Void
    let onClose: () -> Void

    @State private var title: String
    @State private var uploader: String
    @State private var channel: String
    @State private var publishedDate: String
    @State private var duration: String
    @State private var summary: String
    @State private var tags: String
    @State private var thumbnailURL: String
    @State private var sourceLink: String
    @State private var statusMessage: String = ""

    init(
        record: MediaLibraryItem,
        onSave: @escaping (MediaMetadata, URL?) throws -> Void,
        onClose: @escaping () -> Void
    ) {
        self.record = record
        self.onSave = onSave
        self.onClose = onClose
        _title = State(initialValue: record.metadata.title)
        _uploader = State(initialValue: record.metadata.uploader ?? "")
        _channel = State(initialValue: record.metadata.channel ?? "")
        _publishedDate = State(initialValue: record.metadata.publishedDate ?? "")
        _duration = State(initialValue: record.metadata.durationSeconds.map(String.init) ?? "")
        _summary = State(initialValue: record.metadata.summary ?? "")
        _tags = State(initialValue: record.metadata.tags?.joined(separator: ", ") ?? "")
        _thumbnailURL = State(initialValue: record.metadata.thumbnailURL ?? "")
        _sourceLink = State(initialValue: record.sources.first(where: { $0.kind == .webLink })?.locator ?? "")
    }

    var body: some View {
        ZStack {
            PocketStyle.bgColor.ignoresSafeArea()

            ScrollView {
                VStack(spacing: PocketStyle.gap) {
                    Y2KPanel(title: "video metadata", tint: PocketStyle.bubblePink) {
                        VStack(alignment: .leading, spacing: 12) {
                            field("Title", text: $title)

                            HStack(spacing: 12) {
                                field("Uploader", text: $uploader)
                                field("Channel", text: $channel)
                            }

                            HStack(spacing: 12) {
                                field("Published date", text: $publishedDate, prompt: "YYYYMMDD")
                                field("Duration", text: $duration, prompt: "seconds")
                            }

                            field("Tags", text: $tags, prompt: "comma separated")
                            field("Thumbnail URL", text: $thumbnailURL, prompt: "https://...")

                            VStack(alignment: .leading, spacing: 5) {
                                Text("DESCRIPTION")
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundStyle(PocketStyle.mutedText)
                                TextEditor(text: $summary)
                                    .font(.system(size: 12, design: .rounded))
                                    .frame(minHeight: 90)
                                    .padding(6)
                                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    Y2KPanel(title: "source", tint: PocketStyle.lavender) {
                        VStack(alignment: .leading, spacing: 10) {
                            field("Source link", text: $sourceLink, prompt: "https://...")
                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .foregroundStyle(PocketStyle.text)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    HStack {
                        Button("Cancel", action: onClose)
                        Spacer()
                        Button("Save metadata") { save() }
                            .buttonStyle(.borderedProminent)
                            .tint(PocketStyle.bubblePink)
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(22)
            }
        }
        .frame(minWidth: 650, idealWidth: 700, minHeight: 700, idealHeight: 760)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String = "") -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(PocketStyle.mutedText)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        let cleanedTags = tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanedLink = sourceLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkedURL: URL?
        if cleanedLink.isEmpty {
            linkedURL = nil
        } else if let candidate = URL(string: cleanedLink),
                  ["http", "https"].contains(candidate.scheme?.lowercased() ?? ""),
                  candidate.host != nil {
            linkedURL = candidate
        } else {
            statusMessage = "Enter a complete web link beginning with https://, or leave the source link empty."
            return
        }

        let metadata = MediaMetadata(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            uploader: nilIfEmpty(uploader),
            channel: nilIfEmpty(channel),
            publishedDate: nilIfEmpty(publishedDate),
            durationSeconds: Int(duration),
            summary: nilIfEmpty(summary),
            tags: cleanedTags.isEmpty ? nil : cleanedTags,
            thumbnailURL: nilIfEmpty(thumbnailURL),
            origin: record.metadata.origin,
            providerIdentifier: record.metadata.providerIdentifier,
            resolvedAt: record.metadata.resolvedAt
        )

        do {
            try onSave(metadata, linkedURL)
            onClose()
        } catch {
            statusMessage = "Could not save metadata: \(error.localizedDescription)"
        }
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
