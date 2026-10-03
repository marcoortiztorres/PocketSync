import Foundation

@main
struct VideoSearchTests {
    static func main() {
        let record = VideoRecord(
            sourceURL: "/music/original.mp4", title: "Beyoncé — Live in Paris",
            uploader: "Concert Channel", tags: ["Acoustic"],
            highResPath: "/music/master-performance.mp4", threeDSFileName: "HNI_0042.AVI"
        )
        func matches(_ query: String) -> Bool {
            VideoSearch.matches(record, terms: VideoSearch.terms(in: query))
        }
        precondition(matches(""))
        precondition(matches("  \n  "))
        precondition(matches("BEYONCE"))
        precondition(matches("par bey"))
        precondition(matches("acoustic concert paris"))
        precondition(matches("hni_0042"))
        precondition(matches("master-performance"))
        precondition(!matches("paris missing"))
        precondition(!matches("unrelated"))
        let empty = VideoRecord(sourceURL: "", title: "")
        precondition(!VideoSearch.matches(empty, terms: VideoSearch.terms(in: "song")))
        print("Video search tests passed")
    }
}
