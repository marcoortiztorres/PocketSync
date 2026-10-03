import SwiftUI

/// Filters presentation only; the caller retains selection and playback order.
struct SearchableVideoList<Row: View>: View {
    let records: [VideoRecord]
    @Binding var isSearchVisible: Bool
    let height: CGFloat
    let spacing: CGFloat
    @ViewBuilder var row: (VideoRecord, Int) -> Row

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let terms = VideoSearch.terms(in: isSearchVisible ? query : "")
        let matches = records.enumerated().filter { VideoSearch.matches($0.element, terms: terms) }

        VStack(spacing: 8) {
            if isSearchVisible {
                HStack(spacing: 8) {
                    TextField("Search videos…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .focused($searchFocused)
                        .onExitCommand(perform: closeSearch)
                        .accessibilityLabel("Search videos")
                    Button(action: closeSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(PocketStyle.mutedText)
                    }
                    .buttonStyle(.plain)
                    .help("Clear and close search")
                    .accessibilityLabel("Clear and close search")
                }
                .padding(8)
                .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
                .task { searchFocused = true }
            }

            if matches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: records.isEmpty ? "music.note.list" : "magnifyingglass")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(PocketStyle.bubblePink)
                    Text(records.isEmpty ? "Queue is empty" : "No matching videos")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(PocketStyle.text)
                    Text(records.isEmpty ? "Imported videos will line up here." : "Try another title, channel, tag, or filename.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(PocketStyle.mutedText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: spacing) {
                        ForEach(matches, id: \.element.id) { entry in
                            row(entry.element, entry.offset + 1)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(height: height)
        .onChange(of: isSearchVisible) { _, visible in
            if !visible { query = "" }
        }
    }

    private func closeSearch() {
        query = ""
        searchFocused = false
        isSearchVisible = false
    }
}
