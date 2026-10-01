import Foundation

@main
struct PhaseTemplateChecks {
    static func main() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let presets = SolveMethodTemplate.presets
        precondition(presets.count == 8)
        precondition(Set(presets.map(\.id)).count == presets.count)
        let xcross = presets.first { $0.title == "XCross" }!
        precondition(xcross.phases.map(\.title) == ["XCross", "F2L #2", "F2L #3", "F2L #4", "OLL", "PLL"])
        let twoLook = presets.first { $0.title == "CFOP + 2-look OLL + 2-look PLL" }!
        precondition(twoLook.phases.map(\.title) == ["Cross", "F2L #1", "F2L #2", "F2L #3", "F2L #4",
                                                    "OLL Step 1", "OLL Step 2", "PLL Step 1", "PLL Step 2"])
        for template in presets {
            var segments: [SolveSegment] = []
            var next = template.nextPhase(after: nil)
            while let phase = next {
                let start = Double(segments.count)
                segments.append(SolveSegment(type: phase, start: start, end: start + 1, caseLabel: "case"))
                next = template.nextPhase(after: phase)
            }
            precondition(segments.map(\.type) == template.phases)
            precondition(template.isComplete(segments))
            precondition(!template.isComplete(Array(segments.dropLast())))
            precondition(!template.isComplete(Array(segments.reversed())))
            var solve = Solve(videoPath: "/demo.mov", videoBookmark: nil, recordedAt: Date(),
                              methodTemplate: template, segments: segments, annotations: [
                                VideoAnnotation(timing: .point(0.5), category: .rotation, note: "Keep this note")])
            precondition(solve.completedDuration == Double(template.phases.count))
            solve.pendingSegment = PendingSegment(type: template.phases.last!, start: 0)
            precondition(solve.completedDuration == nil)
            let restored = try decoder.decode(Solve.self, from: encoder.encode(solve))
            precondition(restored.annotations.first?.note == "Keep this note")
            precondition(restored.phaseTemplate == template)
            precondition(restored.pendingSegment?.type == solve.pendingSegment?.type)
            precondition(restored.segments.map(\.type) == template.phases)
        }

        // Use the pre-template on-disk schema, including integer phases and no template field.
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","videoPath":"/demo.mov",
         "recordedAt":0,"importedAt":0,"annotations":[],"segments":[
        \((1...7).map { "{\"id\":\"\(UUID().uuidString)\",\"type\":\($0),\"start\":\($0 - 1),\"end\":\($0),\"caseLabel\":\"\"}" }.joined(separator: ","))]}
        """
        let oldSolve = try decoder.decode(Solve.self, from: Data(legacy.utf8))
        precondition(oldSolve.phaseTemplate == .standard)
        precondition(oldSolve.segments.map(\.type) == SolveMethodTemplate.standard.phases)
        precondition(oldSolve.completedDuration == 7)
        var incomplete = oldSolve
        incomplete.segments.removeFirst()
        precondition(incomplete.completedDuration == nil)
        incomplete.segments = []
        precondition(incomplete.completedDuration == nil)
        let migrated = try decoder.decode(Solve.self, from: encoder.encode(oldSolve))
        precondition(migrated.completedDuration == 7)
        for value in 1...7 {
            let pending = try decoder.decode(PendingSegment.self,
                from: Data("{\"type\":\(value),\"start\":1}".utf8))
            precondition(pending.type == SolveMethodTemplate.standard.phases[value - 1])
        }

        // Future methods need no CFOP phase or preset registry entry to persist and complete.
        let custom = SolveMethodTemplate(id: "roux", title: "Roux", phases: [
            SolveSegmentType(id: "first-block", title: "First block"),
            SolveSegmentType(id: "last-six", title: "Last six edges")])
        let restored = try decoder.decode(SolveMethodTemplate.self, from: encoder.encode(custom))
        precondition(restored == custom)
        precondition(restored.nextPhase(after: custom.phases.first) == custom.phases.last)
        precondition(restored.nextPhase(after: .cross) == nil)
        let customSegments = custom.phases.enumerated().map {
            SolveSegment(type: $0.element, start: Double($0.offset), end: Double($0.offset + 1), caseLabel: "")
        }
        let customSolve = Solve(videoPath: "/demo.mov", videoBookmark: nil, recordedAt: Date(),
                                methodTemplate: custom, segments: customSegments)
        precondition(customSolve.completedDuration == 2)
        print("Phase template checks passed (8 presets, legacy migration, custom phases).")
    }
}
