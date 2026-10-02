import Foundation

enum IssueTagPhase: String, Codable {
    case cross, f2l, oll, pll

    init?(phase: SolveSegmentType) {
        switch phase.id {
        case "cross", "xcross": self = .cross
        case "f2l.1", "f2l.2", "f2l.3", "f2l.4": self = .f2l
        case "oll", "oll.1", "oll.2": self = .oll
        case "pll", "pll.1", "pll.2": self = .pll
        default: return nil
        }
    }
}

// The catalog is independent of annotations, which store stable IDs only.
// Future user-defined catalogs can use this same metadata model.
struct IssueTag: Identifiable, Codable {
    let id: String
    let name: String
    let category: String
    let description: String
    let eventTypes: [AnnotationCategory]
    let phases: [IssueTagPhase]

    func relevance(event: AnnotationCategory, phase: SolveSegmentType?) -> Int {
        let eventScore = eventTypes.contains(event) ? 2 : 0
        let phaseScore = phase.flatMap { IssueTagPhase(phase: $0) }.map { phases.contains($0) ? 1 : 0 } ?? 0
        return eventScore + phaseScore
    }

    static func matching(_ query: String, event: AnnotationCategory, phase: SolveSegmentType?) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return builtIn.filter {
            query.isEmpty || [$0.name, $0.category, $0.description].contains {
                $0.localizedStandardContains(query)
            }
        }.sorted {
            let leftName = !query.isEmpty && $0.name.localizedStandardContains(query)
            let rightName = !query.isEmpty && $1.name.localizedStandardContains(query)
            if leftName != rightName { return leftName }
            let left = $0.relevance(event: event, phase: phase)
            let right = $1.relevance(event: event, phase: phase)
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left > right
        }
    }

    static func displayName(for id: String) -> String {
        builtIn.first { $0.id == id }?.name ?? "Unavailable tag"
    }

    static let builtIn: [Self] = {
        func tag(_ id: String, _ name: String, _ category: String,
                 _ events: [AnnotationCategory], _ phases: [IssueTagPhase], _ description: String = "") -> Self {
            Self(id: id, name: name, category: category, description: description, eventTypes: events, phases: phases)
        }
        let lookahead = "Pause / lookahead"
        let planning = "Recognition / planning"
        let efficiency = "F2L efficiency"
        let orientation = "Rotation / orientation"
        let execution = "Execution"
        return [
            tag("pause.long_after_cross", "Long pause after cross", lookahead, [.pause], [.f2l], "Finished Cross, then searched from scratch for the first F2L pair."),
            tag("pause.after_insertion", "Pause after pair insertion", lookahead, [.pause], [.f2l], "Stopped after completing a pair before finding the next one."),
            tag("lookahead.lost_piece", "Couldn’t find a piece", lookahead, [.pause], [.f2l], "The intended pair was known, but its corner or edge was lost."),
            tag("lookahead.whole_cube_scanning", "Whole-cube scanning", lookahead, [.pause, .rotation], [.f2l], "Searched many faces instead of tracking specific pieces."),
            tag("lookahead.watching_current_pair", "Watching current pair", lookahead, [.pause, .other], [.f2l], "Watched the pair being solved instead of looking ahead."),
            tag("lookahead.lost_during_rotation", "Lost tracking during rotation", lookahead, [.pause, .rotation], [.f2l], "Needed to rediscover pieces after a rotation."),
            tag("lookahead.missed_revealed_pieces", "Missed revealed pieces", lookahead, [.pause, .other], [.f2l], "Failed to track useful pieces revealed during insertion."),
            tag("lookahead.cross_no_tracking", "Cross left no F2L tracking", lookahead, [.pause, .other], [.cross, .f2l], "No useful F2L piece was tracked through Cross."),
            tag("recognition.familiar_case", "Hesitated on familiar case", planning, [.pause], [.f2l, .oll, .pll]),
            tag("planning.incomplete_solution", "Started before full solution was known", planning, [.pause, .other], [.cross, .f2l], "Began executing, then stopped to plan the rest."),
            tag("recognition.acted_too_soon", "Acted before recognition", planning, [.pause, .other], [.f2l, .oll, .pll], "Made moves and then undid or revised them."),
            tag("planning.missed_free_pair", "Missed free pair", planning, [.other], [.f2l]),
            tag("planning.pair_choice", "Missed better pair choice", planning, [.other], [.f2l], "Chose the first noticed pair despite a substantially easier option."),
            tag("planning.improvising", "Repeatedly improvising known case", planning, [.pause, .other], [.f2l, .oll, .pll], "No consistent solution for a recurring case."),
            tag("f2l.awkward_solution", "Long / awkward solution", efficiency, [.other], [.f2l]),
            tag("f2l.unnecessary_extraction", "Unnecessary extraction", efficiency, [.other], [.f2l]),
            tag("f2l.separated_pair", "Separated an already paired pair", efficiency, [.other], [.f2l]),
            tag("f2l.destroyed_pair", "Destroyed another useful pair", efficiency, [.other], [.f2l]),
            tag("f2l.slot_choice", "Poor slot choice", efficiency, [.other], [.f2l]),
            tag("f2l.back_slot", "Slow back-slot insertion", efficiency, [.pause, .other], [.f2l]),
            tag("f2l.front_right_dependence", "Front-right slot dependence", efficiency, [.rotation, .other], [.f2l]),
            tag("f2l.last_slot", "Weak last-slot solution", efficiency, [.other], [.f2l]),
            tag("f2l.finish_orientation", "Unhelpful F2L finish orientation", efficiency, [.rotation, .other], [.f2l]),
            tag("rotation.unnecessary", "Unnecessary rotation", orientation, [.rotation], [.cross, .f2l, .oll, .pll]),
            tag("rotation.searching", "Rotation used to search", orientation, [.rotation, .pause], [.f2l]),
            tag("orientation.u_searching", "Excessive U-layer searching", orientation, [.pause, .other], [.f2l, .oll, .pll]),
            tag("orientation.slot_awareness", "Weak unsolved-slot awareness", orientation, [.rotation, .other], [.f2l]),
            tag("execution.regrip", "Unnecessary regrip", execution, [.regrip], [.cross, .f2l, .oll, .pll]),
            tag("execution.lockup", "Lockup / inaccurate turning", execution, [.pause, .other], [.cross, .f2l, .oll, .pll]),
            tag("execution.case_slowdown", "Case-specific execution slowdown", execution, [.pause, .regrip, .other], [.f2l, .oll, .pll])
        ]
    }()
}
