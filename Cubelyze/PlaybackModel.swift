import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

enum AnnotationCategory: Int, CaseIterable {
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

enum AnnotationTiming {
    case point(Double)
    case interval(start: Double, end: Double)

    var start: Double {
        switch self {
        case .point(let time): return time
        case .interval(let start, _): return start
        }
    }

    var end: Double? {
        if case .interval(_, let end) = self { return end }
        return nil
    }

    var duration: Double? { end.map { $0 - start } }
}

struct VideoAnnotation: Identifiable {
    let id = UUID()
    let timing: AnnotationTiming
    let category: AnnotationCategory
}

enum SolveSegmentType: Int, CaseIterable {
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

struct SolveSegment: Identifiable {
    let id = UUID()
    let type: SolveSegmentType
    var start: Double
    var end: Double
    var caseLabel: String

    var duration: Double { end - start }
}

struct PendingSegment {
    let type: SolveSegmentType
    let start: Double
}

struct PendingAnnotation {
    let category: AnnotationCategory
    let start: Double
}

@MainActor
final class PlaybackModel: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var filename: String?
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var videoAspectRatio: CGFloat = 16.0 / 9.0
    @Published private(set) var isPlaying = false
    @Published private(set) var isReady = false
    @Published private(set) var speed: Float = 1
    @Published private(set) var scrubPosition: Double?
    @Published private(set) var annotations: [VideoAnnotation] = []
    @Published private(set) var pendingAnnotation: PendingAnnotation?
    @Published var annotationMessage: String?
    @Published private(set) var segments: [SolveSegment] = []
    @Published private(set) var pendingSegment: PendingSegment?
    @Published var segmentMessage: String?
    @Published var errorMessage: String?
    private var seekTarget: CMTime?
    private var isSeeking = false
    private var pendingSteps = 0
    private var isScrubbing = false
    private var playAfterSeek = false
    private var reachedEnd = false
    private var endObserver: NSObjectProtocol?

    init() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                self.reachedEnd = true
                self.refresh()
            }
        }
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Open Video"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url)
        }
    }

    func open(_ url: URL) {
        player.pause()
        filename = url.lastPathComponent
        annotations.removeAll()
        pendingAnnotation = nil
        annotationMessage = nil
        segments.removeAll()
        pendingSegment = nil
        segmentMessage = nil
        position = 0
        duration = 0
        videoAspectRatio = 16.0 / 9.0
        isReady = false
        isPlaying = false
        errorMessage = nil
        seekTarget = nil
        isSeeking = false
        pendingSteps = 0
        isScrubbing = false
        playAfterSeek = false
        scrubPosition = nil
        reachedEnd = false
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }

    func togglePlayback() {
        guard isReady else { return }
        if isSeeking || isScrubbing {
            playAfterSeek.toggle()
            refresh()
            return
        }
        if player.rate != 0 {
            player.pause()
        } else {
            if reachedEnd {
                reachedEnd = false
                playAfterSeek = true
                seekTarget = .zero
                seekToTarget()
                refresh()
                return
            }
            player.play()
        }
        refresh()
    }

    func setSpeed(_ value: Float) {
        speed = value
        player.defaultRate = value
        if player.rate != 0 { player.rate = value }
        refresh()
    }

    func addAnnotation(_ category: AnnotationCategory) {
        guard isReady else { return }
        let time = player.currentTime().seconds
        guard time.isFinite else { return }
        let timing: AnnotationTiming
        if category.isInterval {
            if let pending = pendingAnnotation {
                guard pending.category == category, time > pending.start else {
                    annotationMessage = "Finish \(pending.category.title) after its start, or cancel it."
                    return
                }
                timing = .interval(start: pending.start, end: time)
                pendingAnnotation = nil
            } else {
                pendingAnnotation = PendingAnnotation(category: category, start: max(0, time))
                annotationMessage = nil
                return
            }
        } else {
            timing = .point(max(0, time))
        }
        let annotation = VideoAnnotation(timing: timing, category: category)
        let index = annotations.firstIndex { $0.timing.start > timing.start } ?? annotations.endIndex
        annotations.insert(annotation, at: index)
        annotationMessage = nil
    }

    func cancelPendingAnnotation() {
        pendingAnnotation = nil
        annotationMessage = nil
    }

    func deleteAnnotation(_ annotation: VideoAnnotation) {
        annotations.removeAll { $0.id == annotation.id }
    }

    func markNextSegmentBoundary() {
        guard isReady else { return }
        let time = player.currentTime().seconds
        guard time.isFinite else { return }
        guard let pending = pendingSegment else {
            if segments.last?.type == .pll {
                segmentMessage = "The solve sequence is complete."
                return
            }
            let expected = segments.last.flatMap { SolveSegmentType(rawValue: $0.type.rawValue + 1) } ?? .cross
            pendingSegment = PendingSegment(type: expected, start: segments.last?.end ?? max(0, time))
            segmentMessage = nil
            return
        }
        let next = SolveSegmentType(rawValue: pending.type.rawValue + 1)
        guard time > pending.start else {
            segmentMessage = "End time must be later than start time."
            return
        }
        segments.append(SolveSegment(type: pending.type, start: pending.start, end: time, caseLabel: ""))
        pendingSegment = next.map { PendingSegment(type: $0, start: time) }
        segmentMessage = nil
    }

    func cancelPendingSegment() {
        pendingSegment = nil
        segmentMessage = nil
    }

    func updateSegment(_ segment: SolveSegment, start: Double, end: Double, caseLabel: String) -> Bool {
        guard start.isFinite, end.isFinite, start >= 0, end > start,
              end <= duration, let index = segments.firstIndex(where: { $0.id == segment.id }) else {
            return false
        }
        guard index == 0 || start > segments[index - 1].start else { return false }
        guard index + 1 == segments.count || end < segments[index + 1].end else { return false }
        if index > 0 {
            segments[index - 1].end = start
        }
        if index + 1 < segments.count {
            segments[index + 1].start = end
        } else if let pending = pendingSegment {
            pendingSegment = PendingSegment(type: pending.type, start: end)
        }
        segments[index].start = start
        segments[index].end = end
        segments[index].caseLabel = caseLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    func deleteSegment(_ segment: SolveSegment) {
        guard let index = segments.firstIndex(where: { $0.id == segment.id }) else { return }
        let restart = segments[index].start
        segments.removeSubrange(index...)
        pendingSegment = PendingSegment(type: segment.type, start: restart)
        segmentMessage = "Deleted \(segment.type.title) and later segments; mark \(segment.type.title) end again."
    }

    func stepFrame(by count: Int) {
        guard isReady, let item = player.currentItem else { return }
        player.pause()
        playAfterSeek = false
        reachedEnd = false
        guard count > 0 ? item.canStepForward : item.canStepBackward else {
            errorMessage = "This video does not support stepping in that direction."
            refresh()
            return
        }
        if isSeeking {
            pendingSteps += count
        } else {
            item.step(byCount: count)
        }
        refresh()
    }

    func seek(by seconds: Double) {
        guard isReady else { return }
        let base = seekTarget?.seconds ?? player.currentTime().seconds
        seek(to: base + seconds)
    }

    func scrub(to seconds: Double) {
        guard isReady, duration > 0 else { return }
        if !isScrubbing {
            playAfterSeek = isPlaying
            isScrubbing = true
        }
        scrubPosition = min(duration, max(0, seconds))
        seek(to: seconds)
    }

    func endScrubbing(at seconds: Double) {
        scrub(to: seconds)
        isScrubbing = false
    }

    func seek(to seconds: Double) {
        guard isReady else { return }
        reachedEnd = false
        if !isSeeking && !isScrubbing { playAfterSeek = player.rate != 0 }
        player.pause()
        seekTarget = CMTime(seconds: min(duration, max(0, seconds)), preferredTimescale: 60_000)
        if !isSeeking { seekToTarget() }
        refresh()
    }

    private func seekToTarget() {
        guard let target = seekTarget, let item = player.currentItem else { return }
        isSeeking = true
        // Coalesce drag/key-repeat requests without continually cancelling frame decoding.
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                if finished, self.seekTarget != target {
                    self.seekToTarget()
                    return
                }
                self.isSeeking = false
                self.seekTarget = nil
                if self.pendingSteps != 0 {
                    item.step(byCount: self.pendingSteps)
                    self.pendingSteps = 0
                }
                if !self.isScrubbing {
                    self.scrubPosition = nil
                    if self.playAfterSeek { self.player.play() }
                }
                self.refresh()
            }
        }
    }

    func refresh() {
        guard let item = player.currentItem else { return }
        isReady = item.status == .readyToPlay
        let size = item.presentationSize
        if size.width > 0, size.height > 0 {
            let ratio = size.width / size.height
            if abs(videoAspectRatio - ratio) > 0.001 { videoAspectRatio = ratio }
        }
        isPlaying = isSeeking || isScrubbing ? playAfterSeek : player.rate != 0
        let current = player.currentTime().seconds
        let total = item.duration.seconds
        position = current.isFinite ? max(0, current) : 0
        duration = total.isFinite ? max(0, total) : 0
        if item.status == .failed, errorMessage == nil {
            errorMessage = item.error?.localizedDescription ?? "This video could not be played."
        }
    }

    static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00.000" }
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        let value = milliseconds / 1000
        if value >= 3600 {
            return String(format: "%d:%02d:%02d.%03d", value / 3600, value / 60 % 60, value % 60, milliseconds % 1000)
        }
        return String(format: "%d:%02d.%03d", value / 60, value % 60, milliseconds % 1000)
    }
}
