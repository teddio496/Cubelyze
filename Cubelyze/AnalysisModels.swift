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
    init(id: UUID = UUID(), timing: AnnotationTiming, category: AnnotationCategory, note: String = "") {
        self.id = id; self.timing = timing; self.category = category; self.note = note
    }
}

enum SolveSegmentType: Int, CaseIterable, Codable {
    case cross = 1, f2l1, f2l2, f2l3, f2l4, oll, pll
    var title: String {
        switch self {
        case .cross: return "Cross"
        case .f2l1: return "F2L #1"
        case .f2l2: return "F2L #2"
        case .f2l3: return "F2L #3"
        case .f2l4: return "F2L #4"
        case .oll: return "OLL"
        case .pll: return "PLL"
        }
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
    var trimmedAt: Date?
    var segments: [SolveSegment]
    var pendingSegment: PendingSegment?
    var annotations: [VideoAnnotation]

    init(id: UUID = UUID(), videoPath: String, videoBookmark: Data?,
         recordedAt: Date, importedAt: Date = Date(), scramble: String? = nil,
         trimmedAt: Date? = nil,
         segments: [SolveSegment] = [], pendingSegment: PendingSegment? = nil,
         annotations: [VideoAnnotation] = []) {
        self.id = id
        self.videoPath = videoPath
        self.videoBookmark = videoBookmark
        self.recordedAt = recordedAt
        self.importedAt = importedAt
        self.scramble = scramble
        self.trimmedAt = trimmedAt
        self.segments = segments
        self.pendingSegment = pendingSegment
        self.annotations = annotations
    }

    var filename: String { URL(fileURLWithPath: videoPath).lastPathComponent }
    var completedDuration: Double? {
        guard pendingSegment == nil, segments.last?.type == .pll,
              let first = segments.first, let last = segments.last else { return nil }
        return max(0, last.end - first.start)
    }
}
