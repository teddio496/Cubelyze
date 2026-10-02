import SwiftUI

enum AnnotationCategory: Int, CaseIterable, Codable {
    case pause = 1, rotation, regrip, other

    var isInterval: Bool { self == .pause }
    var title: String {
        switch self {
        case .pause: return "Pause"
        case .rotation: return "Rotation"
        case .regrip: return "Regrip"
        case .other: return "Other"
        }
    }
    var color: Color {
        switch self {
        case .pause: return .orange
        case .rotation: return .blue
        case .regrip: return .purple
        case .other: return .green
        }
    }
}

enum AnnotationTiming: Codable {
    case point(Double)
    case interval(start: Double, end: Double)
    var start: Double {
        switch self { case .point(let time): return time; case .interval(let start, _): return start }
    }
    var end: Double? { if case .interval(_, let end) = self { return end }; return nil }
    var duration: Double? { end.map { $0 - start } }
}

struct VideoAnnotation: Identifiable, Codable {
    let id: UUID
    var timing: AnnotationTiming
    let category: AnnotationCategory
    var note: String
    var tagIDs: [String]
    init(id: UUID = UUID(), timing: AnnotationTiming, category: AnnotationCategory, note: String = "", tagIDs: [String] = []) {
        self.id = id; self.timing = timing; self.category = category; self.note = note
        self.tagIDs = tagIDs
    }

    private enum CodingKeys: String, CodingKey { case id, timing, category, note, tagIDs }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timing = try container.decode(AnnotationTiming.self, forKey: .timing)
        category = try container.decode(AnnotationCategory.self, forKey: .category)
        note = try container.decode(String.self, forKey: .note)
        tagIDs = try container.decodeIfPresent([String].self, forKey: .tagIDs) ?? []
    }
}

// Persist phase identities and labels independently of the preset catalog.
struct SolveSegmentType: Hashable, Codable {
    let id: String
    let title: String

    var groupTitle: String {
        if id == "cross" || id == "xcross" { return "Cross" }
        if id.hasPrefix("f2l") { return "F2L" }
        if id.hasPrefix("oll") { return "OLL" }
        if id.hasPrefix("pll") { return "PLL" }
        return title
    }
    var color: Color {
        switch groupTitle { case "Cross": return .cyan; case "F2L": return .blue; case "OLL": return .purple; case "PLL": return .green; default: return .teal }
    }
    var overlayTitle: String {
        if id.hasPrefix("f2l."), let pair = id.split(separator: ".").last { return "F2L · Pair \(pair)" }
        return title
    }

    static let cross = Self(id: "cross", title: "Cross")
    static let f2l1 = Self(id: "f2l.1", title: "F2L #1")
    static let f2l2 = Self(id: "f2l.2", title: "F2L #2")
    static let f2l3 = Self(id: "f2l.3", title: "F2L #3")
    static let f2l4 = Self(id: "f2l.4", title: "F2L #4")
    static let oll = Self(id: "oll", title: "OLL")
    static let pll = Self(id: "pll", title: "PLL")
    static let xcross = Self(id: "xcross", title: "XCross")
    static let oll1 = Self(id: "oll.1", title: "OLL Step 1")
    static let oll2 = Self(id: "oll.2", title: "OLL Step 2")
    static let pll1 = Self(id: "pll.1", title: "PLL Step 1")
    static let pll2 = Self(id: "pll.2", title: "PLL Step 2")

    init(id: String, title: String) { self.id = id; self.title = title }

    private enum CodingKeys: String, CodingKey { case id, title }
    init(from decoder: Decoder) throws {
        // Versions before phase templates stored CFOP phases as integers 1–7.
        if let value = try? decoder.singleValueContainer().decode(Int.self) {
            let legacy: [Self] = [.cross, .f2l1, .f2l2, .f2l3, .f2l4, .oll, .pll]
            guard (1...legacy.count).contains(value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                       debugDescription: "Unknown legacy phase"))
            }
            self = legacy[value - 1]
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
        }
    }
}

struct SolveMethodTemplate: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let phases: [SolveSegmentType]

    static let standard = Self(id: "cfop", title: "Standard CFOP",
                              phases: [.cross, .f2l1, .f2l2, .f2l3, .f2l4, .oll, .pll])
    static let presets: [Self] = [standard] + [false, true].flatMap { xcross in
        [false, true].flatMap { twoLookOLL in
            [false, true].compactMap { twoLookPLL -> Self? in
                guard xcross || twoLookOLL || twoLookPLL else { return nil }
                let base = xcross ? "XCross" : "CFOP"
                let variants = [twoLookOLL ? "2-look OLL" : nil,
                                twoLookPLL ? "2-look PLL" : nil].compactMap { $0 }
                return Self(id: "cfop.x\(xcross ? 1 : 0).o\(twoLookOLL ? 2 : 1).p\(twoLookPLL ? 2 : 1)",
                            title: ([base] + variants).joined(separator: " + "),
                            phases: (xcross ? [.xcross] : [.cross, .f2l1]) + [.f2l2, .f2l3, .f2l4]
                                + (twoLookOLL ? [.oll1, .oll2] : [.oll])
                                + (twoLookPLL ? [.pll1, .pll2] : [.pll]))
            }
        }
    }

    func nextPhase(after phase: SolveSegmentType?) -> SolveSegmentType? {
        guard let phase else { return phases.first }
        guard let index = phases.firstIndex(where: { $0.id == phase.id }),
              index + 1 < phases.count else { return nil }
        return phases[index + 1]
    }

    func isComplete(_ segments: [SolveSegment]) -> Bool {
        !phases.isEmpty && segments.map { $0.type.id } == phases.map(\.id)
    }
}

struct SolveSegment: Identifiable, Codable {
    let id: UUID
    let type: SolveSegmentType
    var start: Double
    var end: Double
    var caseLabel: String
    var duration: Double { end - start }
    init(id: UUID = UUID(), type: SolveSegmentType, start: Double, end: Double, caseLabel: String) {
        self.id = id; self.type = type; self.start = start; self.end = end; self.caseLabel = caseLabel
    }
}

struct PendingSegment: Codable { let type: SolveSegmentType; let start: Double }
struct PendingAnnotation: Codable { let category: AnnotationCategory; let start: Double }

struct Solve: Identifiable, Codable {
    let id: UUID
    var videoPath: String
    var videoBookmark: Data?
    var recordedAt: Date
    let importedAt: Date
    var scramble: String?
    var lastPosition: Double?
    var trimmedAt: Date?
    var methodTemplate: SolveMethodTemplate?
    var phaseTemplate: SolveMethodTemplate { methodTemplate ?? .standard }
    var segments: [SolveSegment]
    var pendingSegment: PendingSegment?
    var annotations: [VideoAnnotation]

    init(id: UUID = UUID(), videoPath: String, videoBookmark: Data?,
         recordedAt: Date, importedAt: Date = Date(), scramble: String? = nil,
         trimmedAt: Date? = nil, methodTemplate: SolveMethodTemplate? = nil,
         segments: [SolveSegment] = [], pendingSegment: PendingSegment? = nil,
         annotations: [VideoAnnotation] = []) {
        self.id = id
        self.videoPath = videoPath
        self.videoBookmark = videoBookmark
        self.recordedAt = recordedAt
        self.importedAt = importedAt
        self.scramble = scramble
        self.trimmedAt = trimmedAt
        self.methodTemplate = methodTemplate
        self.segments = segments
        self.pendingSegment = pendingSegment
        self.annotations = annotations
    }

    var filename: String { URL(fileURLWithPath: videoPath).lastPathComponent }
    var displayName: String {
        let name = URL(fileURLWithPath: videoPath).deletingPathExtension().lastPathComponent
        if let range = name.range(of: "-trimmed-") { return String(name[..<range.lowerBound]) + " (trimmed)" }
        return name
    }
    var completedDuration: Double? {
        guard pendingSegment == nil, phaseTemplate.isComplete(segments),
              let first = segments.first, let last = segments.last else { return nil }
        return max(0, last.end - first.start)
    }
}
