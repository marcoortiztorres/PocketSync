import Foundation

nonisolated enum VideoSearch {
    static func terms(in query: String) -> [String] {
        normalize(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func matches(_ record: VideoRecord, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let fields = [record.displayName, record.uploader ?? "", record.channel ?? "",
                      record.threeDSFileName ?? ""]
            + (record.tags ?? [])
            + record.assets.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        let normalizedFields = fields.map(normalize)
        return terms.allSatisfy { term in
            normalizedFields.contains { $0.contains(term) }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
    }
}
