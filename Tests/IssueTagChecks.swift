import Foundation

@main
struct IssueTagChecks {
    static func main() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let catalog = IssueTag.builtIn
        precondition(catalog.count == 30)
        precondition(Set(catalog.map(\.id)).count == catalog.count)
        precondition(Set(catalog.map(\.category)).count == 5)
        precondition(catalog.allSatisfy { !$0.eventTypes.isEmpty && !$0.phases.isEmpty })

        var annotation = VideoAnnotation(timing: .interval(start: 1, end: 2), category: .pause,
                                         note: "Preserve free text", tagIDs: ["pause.long_after_cross", "custom.my_tag", "retired.tag"])
        let encoded = try encoder.encode(annotation)
        let restored = try decoder.decode(VideoAnnotation.self, from: encoded)
        precondition(restored.tagIDs == annotation.tagIDs)
        precondition(restored.note == annotation.note)
        precondition(restored.id == annotation.id)
        precondition(restored.timing.duration == 1)
        precondition(!String(decoding: encoded, as: UTF8.self).contains("Long pause after cross"))
        precondition(IssueTag.displayName(for: "retired.tag") == "Unavailable tag")

        // Old annotations omitted tagIDs, and must still load with their notes and timing intact.
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "tagIDs")
        let old = try decoder.decode(VideoAnnotation.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(old.tagIDs.isEmpty)
        precondition(old.note == annotation.note && old.timing.duration == 1)
        annotation.tagIDs = []
        let empty = try decoder.decode(VideoAnnotation.self, from: encoder.encode(annotation))
        precondition(empty.tagIDs.isEmpty)

        let rotation = IssueTag.matching("", event: .rotation, phase: .f2l2)
        let unnecessary = rotation.firstIndex { $0.id == "rotation.unnecessary" }!
        let regrip = rotation.firstIndex { $0.id == "execution.regrip" }!
        precondition(unnecessary < regrip)
        let lookahead = catalog.first { $0.id == "pause.long_after_cross" }!
        precondition(lookahead.relevance(event: .pause, phase: .f2l2) > lookahead.relevance(event: .pause, phase: .pll))
        precondition(IssueTagPhase(phase: .xcross) == .cross)
        precondition(IssueTagPhase(phase: .oll2) == .oll)
        precondition(IssueTagPhase(phase: .pll1) == .pll)
        precondition(IssueTagPhase(phase: .init(id: "custom", title: "Custom")) == nil)
        precondition(IssueTag.matching("REGRIP", event: .other, phase: nil).map(\.id) == ["execution.regrip"])
        precondition(!IssueTag.matching("lookahead", event: .pause, phase: .f2l1).isEmpty)
        precondition(IssueTag.matching("zzzzzz", event: .pause, phase: nil).isEmpty)

        let solve = Solve(videoPath: "/demo.mov", videoBookmark: nil, recordedAt: Date(), annotations: [restored])
        let saved = try decoder.decode(Solve.self, from: encoder.encode(solve))
        precondition(saved.annotations.first?.tagIDs == restored.tagIDs)
        print("Issue tag checks passed (catalog, legacy annotations, unknown IDs, search, recommendations).")
    }
}
