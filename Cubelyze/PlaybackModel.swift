import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

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
    @Published var selectedAnnotationID: UUID?
    @Published private(set) var pendingAnnotation: PendingAnnotation?
    @Published var annotationMessage: String?
    @Published private(set) var segments: [SolveSegment] = []
    @Published var selectedSegmentID: UUID?
    @Published private(set) var pendingSegment: PendingSegment?
    @Published var segmentMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var saveMessage: String?
    @Published private(set) var solves: [Solve] = []
    @Published private(set) var selectedSolveID: UUID?
    @Published private(set) var importMessage: String?
    @Published private(set) var isTrimming = false
    @Published var showsAnalysisOverlay: Bool =
        UserDefaults.standard.object(forKey: "ShowsAnalysisOverlay") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsAnalysisOverlay, forKey: "ShowsAnalysisOverlay") }
    }
    private var seekTarget: CMTime?
    private var isSeeking = false
    private var pendingSteps = 0
    private var isScrubbing = false
    private var playAfterSeek = false
    private var reachedEnd = false
    private var endObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var saveTask: Task<Void, Never>?
    private var videoURL: URL?
    private var scopedVideoURL: URL?
    private let analysisStore = AnalysisStore()
    private let trimStore = VideoTrimStore()
    private var undoableTrims: [UUID: (original: Solve, receipt: PendingTrimReceipt)] = [:]

    func videoExists(for solve: Solve) -> Bool { analysisStore.videoExists(for: solve) }
    var selectedSolve: Solve? { solves.first { $0.id == selectedSolveID } }
    var canUndoTrim: Bool { selectedSolveID.flatMap { undoableTrims[$0] } != nil && !isTrimming }
    var trimRange: (start: Double, end: Double)? {
        guard !isTrimming, isReady, duration > 0, let solve = selectedSolve,
              solve.trimmedAt == nil, pendingSegment == nil,
              segments.map(\.type) == SolveSegmentType.allCases,
              let first = segments.first, let last = segments.last,
              first.start >= 0, last.end <= duration + 0.05,
              first.start > 0.05 || duration - last.end > 0.05,
              segments.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }),
              zip(segments, segments.dropFirst()).allSatisfy({ abs($0.end - $1.start) < 0.05 }),
              !solves.contains(where: {
                  $0.id != solve.id &&
                  analysisStore.resolveVideoURL(for: $0).standardizedFileURL ==
                  analysisStore.resolveVideoURL(for: solve).standardizedFileURL
              })
        else { return nil }
        return (first.start, min(last.end, duration))
    }

    var completedSolveDurations: [Double] { solves.compactMap(\.completedDuration) }

    func updateScramble(_ value: String) {
        guard let index = solves.firstIndex(where: { $0.id == selectedSolveID }) else { return }
        solves[index].scramble = value.isEmpty ? nil : value
        scheduleSave()
    }

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
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveNow()
                self?.finalizePendingTrims()
            }
        }
        do { solves = try analysisStore.allSolves() }
        catch { errorMessage = "Could not load solve library: \(error.localizedDescription)" }
        finalizePendingTrims()
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        saveTask?.cancel()
        scopedVideoURL?.stopAccessingSecurityScopedResource()
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor [weak self] in await self?.importVideos(panel.urls) }
        }
    }

    func importVideos(_ urls: [URL]) async {
        var added = 0
        var existing = 0
        var failed = 0
        var first: Solve?
        for url in urls where url.isFileURL {
            let file = url.standardizedFileURL
            if let match = solves.first(where: {
                analysisStore.resolveVideoURL(for: $0).standardizedFileURL == file
            }) {
                existing += 1
                if urls.count == 1 { first = match }
                continue
            }
            let accessed = file.startAccessingSecurityScopedResource()
            defer { if accessed { file.stopAccessingSecurityScopedResource() } }
            let recordedAt = await Self.recordingDate(for: file)
            let solve = Solve(videoPath: file.path,
                              videoBookmark: analysisStore.bookmark(for: file),
                              recordedAt: recordedAt)
            do {
                try analysisStore.save(solve)
                solves.append(solve)
                added += 1
                if first == nil { first = solve }
            } catch { failed += 1 }
        }
        solves.sort { $0.recordedAt > $1.recordedAt }
        if urls.count == 1, let first { openSolve(first) }
        else if added > 0, selectedSolveID != nil { showLibrary() }
        importMessage = "Imported \(added) video(s). \(existing) already in library. \(failed) failed."
    }

    private static func recordingDate(for url: URL) async -> Date {
        let asset = AVURLAsset(url: url)
        if let item = try? await asset.load(.creationDate),
           let date = try? await item.load(.dateValue) { return date }
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? Date()
    }

    func relinkVideo(for solve: Solve) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Relink"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.setVideo(url, for: solve.id)
        }
    }

    private func setVideo(_ url: URL, for id: UUID) {
        guard !isTrimming, undoableTrims[id] == nil else {
            importMessage = "Undo the trim before relinking this video."
            return
        }
        if selectedSolveID == id {
            saveTask?.cancel()
            saveNow()
        }
        guard let index = solves.firstIndex(where: { $0.id == id }) else { return }
        let file = url.standardizedFileURL
        let accessed = file.startAccessingSecurityScopedResource()
        defer { if accessed { file.stopAccessingSecurityScopedResource() } }
        var updated = solves[index]
        updated.videoPath = file.path
        updated.videoBookmark = analysisStore.bookmark(for: file)
        do {
            try analysisStore.save(updated)
            solves[index] = updated
            if selectedSolveID == id { openSolve(updated) }
            importMessage = "Video relinked."
        } catch { saveMessage = "Could not relink video: \(error.localizedDescription)" }
    }

    func openSolve(_ solve: Solve) {
        guard !isTrimming else { return }
        let url = analysisStore.resolveVideoURL(for: solve)
        saveTask?.cancel()
        saveNow()
        player.pause()
        scopedVideoURL?.stopAccessingSecurityScopedResource()
        selectedSolveID = solve.id
        if url.startAccessingSecurityScopedResource() { scopedVideoURL = url } else { scopedVideoURL = nil }
        videoURL = FileManager.default.fileExists(atPath: url.path) ? url : nil
        filename = solve.filename
        annotations = solve.annotations
        selectedAnnotationID = nil
        pendingAnnotation = nil
        annotationMessage = nil
        segments = solve.segments
        selectedSegmentID = nil
        pendingSegment = solve.pendingSegment
        segmentMessage = nil
        position = 0
        duration = 0
        videoAspectRatio = 16.0 / 9.0
        isReady = false
        isPlaying = false
        errorMessage = videoURL == nil ? "The video is missing or was moved." : nil
        seekTarget = nil
        isSeeking = false
        pendingSteps = 0
        isScrubbing = false
        playAfterSeek = false
        scrubPosition = nil
        reachedEnd = false
        player.replaceCurrentItem(with: videoURL.map(AVPlayerItem.init(url:)))
        if videoURL != nil { player.play() }
    }

    func showLibrary() {
        guard !isTrimming else { return }
        saveTask?.cancel()
        saveNow()
        player.pause()
        player.replaceCurrentItem(with: nil)
        scopedVideoURL?.stopAccessingSecurityScopedResource()
        scopedVideoURL = nil
        videoURL = nil
        selectedSolveID = nil
        filename = nil
        isReady = false
        isPlaying = false
    }

    func trimCompletedSolve() async {
        guard let range = trimRange, let original = selectedSolve, let source = videoURL else { return }
        saveTask?.cancel()
        saveNow()
        guard saveMessage == nil, let original = solves.first(where: { $0.id == original.id }) else { return }
        isTrimming = true
        player.pause()
        defer { isTrimming = false }
        var exportedURL: URL?
        var receiptSaved = false
        do {
            let before = try trimStore.fingerprint(for: source)
            let export = try await trimStore.export(source: source, start: range.start, end: range.end)
            exportedURL = export.url
            let after = try trimStore.fingerprint(for: source)
            guard before.size == after.size, before.modified == after.modified,
                  before.fileNumber == after.fileNumber else { throw VideoTrimError.changedOriginal }
            var updated = original
            updated.videoPath = export.url.path
            updated.videoBookmark = nil
            updated.trimmedAt = Date()
            updated.segments = segments.map { segment in
                var shifted = segment
                shifted.start = max(0, segment.start - range.start)
                shifted.end = min(export.duration, segment.end - range.start)
                return shifted
            }
            updated.annotations = annotations.compactMap { annotation -> VideoAnnotation? in
                let timing: AnnotationTiming
                switch annotation.timing {
                case .point(let time):
                    guard time >= range.start, time <= range.end else { return nil }
                    timing = .point(min(export.duration, time - range.start))
                case .interval(let start, let end):
                    let clippedStart = max(start, range.start)
                    let clippedEnd = min(end, range.end)
                    guard clippedEnd > clippedStart else { return nil }
                    let shiftedStart = max(0, clippedStart - range.start)
                    let shiftedEnd = min(export.duration, clippedEnd - range.start)
                    guard shiftedEnd > shiftedStart else { return nil }
                    timing = .interval(start: shiftedStart, end: shiftedEnd)
                }
                return VideoAnnotation(id: annotation.id, timing: timing,
                                       category: annotation.category, note: annotation.note)
            }
            let receipt = PendingTrimReceipt(solveID: original.id, originalPath: source.path,
                                             originalBookmark: original.videoBookmark,
                                             originalSize: before.size,
                                             originalModificationDate: before.modified,
                                             originalFileNumber: before.fileNumber,
                                             trimmedPath: export.url.path)
            try trimStore.saveReceipt(receipt)
            receiptSaved = true
            try analysisStore.save(updated)
            undoableTrims[original.id] = (original, receipt)
            if let index = solves.firstIndex(where: { $0.id == original.id }) { solves[index] = updated }
            selectedSolveID = nil
            isTrimming = false
            openSolve(updated)
            saveMessage = "Video trimmed. Undo is available until you quit the app."
        } catch {
            if receiptSaved { try? trimStore.removeReceipt(for: original.id) }
            if let exportedURL { try? trimStore.discardTrimmedFile(at: exportedURL) }
            saveMessage = "Could not trim video: \(error.localizedDescription)"
        }
    }

    func undoTrim() {
        guard let id = selectedSolveID, let undo = undoableTrims[id] else { return }
        guard FileManager.default.fileExists(atPath: undo.receipt.originalPath) else {
            saveMessage = "Could not undo trim: the original video is missing."
            return
        }
        saveTask?.cancel()
        saveNow()
        do {
            try analysisStore.save(undo.original)
            try trimStore.removeReceipt(for: id)
            if let index = solves.firstIndex(where: { $0.id == id }) { solves[index] = undo.original }
            undoableTrims.removeValue(forKey: id)
            selectedSolveID = nil
            openSolve(undo.original)
            try trimStore.discardTrimmedFile(at: URL(fileURLWithPath: undo.receipt.trimmedPath))
            saveMessage = "Trim undone. The original video is active again."
        } catch { saveMessage = "Could not undo trim: \(error.localizedDescription)" }
    }

    private func finalizePendingTrims() {
        do {
            for receipt in try trimStore.receipts() {
                guard let solve = solves.first(where: { $0.id == receipt.solveID }),
                      solve.videoPath == receipt.trimmedPath, solve.trimmedAt != nil,
                      FileManager.default.fileExists(atPath: receipt.trimmedPath),
                      !solves.contains(where: {
                          $0.id != receipt.solveID &&
                          analysisStore.resolveVideoURL(for: $0).standardizedFileURL.path == receipt.originalPath
                      })
                else { continue }
                var stale = false
                let originalURL = receipt.originalBookmark.flatMap {
                    try? URL(resolvingBookmarkData: $0, options: .withSecurityScope,
                             relativeTo: nil, bookmarkDataIsStale: &stale)
                } ?? URL(fileURLWithPath: receipt.originalPath)
                guard originalURL.standardizedFileURL.path == receipt.originalPath else { continue }
                guard FileManager.default.fileExists(atPath: receipt.originalPath) else {
                    try trimStore.removeReceipt(for: receipt.solveID)
                    continue
                }
                let current = try trimStore.fingerprint(for: originalURL)
                guard current.size == receipt.originalSize,
                      current.modified == receipt.originalModificationDate,
                      current.fileNumber == receipt.originalFileNumber else { continue }
                let accessed = originalURL.startAccessingSecurityScopedResource()
                defer { if accessed { originalURL.stopAccessingSecurityScopedResource() } }
                try FileManager.default.removeItem(at: originalURL)
                try trimStore.removeReceipt(for: receipt.solveID)
            }
        } catch { saveMessage = "Could not finish trim cleanup: \(error.localizedDescription)" }
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
                scheduleSave()
                return
            }
        } else {
            timing = .point(max(0, time))
        }
        let annotation = VideoAnnotation(timing: timing, category: category)
        let index = annotations.firstIndex { $0.timing.start > timing.start } ?? annotations.endIndex
        annotations.insert(annotation, at: index)
        annotationMessage = nil
        selectedAnnotationID = annotation.id
        scheduleSave()
    }

    func cancelPendingAnnotation() {
        pendingAnnotation = nil
        annotationMessage = nil
        scheduleSave()
    }

    func deleteAnnotation(_ annotation: VideoAnnotation) {
        annotations.removeAll { $0.id == annotation.id }
        if selectedAnnotationID == annotation.id { selectedAnnotationID = nil }
        scheduleSave()
    }

    func selectAnnotation(_ annotation: VideoAnnotation, seek: Bool = true) {
        selectedAnnotationID = annotation.id
        selectedSegmentID = nil
        if seek { self.seek(to: annotation.timing.start) }
    }

    func updateAnnotationNote(id: UUID, note: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].note = note
        scheduleSave()
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
            scheduleSave()
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
        scheduleSave()
    }

    func cancelPendingSegment() {
        pendingSegment = nil
        segmentMessage = nil
        scheduleSave()
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
        scheduleSave()
        return true
    }

    func deleteSegment(_ segment: SolveSegment) {
        guard let index = segments.firstIndex(where: { $0.id == segment.id }) else { return }
        let restart = segments[index].start
        segments.removeSubrange(index...)
        if selectedSegmentID == segment.id { selectedSegmentID = nil }
        pendingSegment = PendingSegment(type: segment.type, start: restart)
        segmentMessage = "Deleted \(segment.type.title) and later segments; mark \(segment.type.title) end again."
        scheduleSave()
    }

    var selectedAnnotation: VideoAnnotation? {
        annotations.first { $0.id == selectedAnnotationID }
    }

    var selectedSegment: SolveSegment? {
        segments.first { $0.id == selectedSegmentID }
    }

    func selectSegment(_ segment: SolveSegment) {
        selectedSegmentID = segment.id
        selectedAnnotationID = nil
        seek(to: segment.start)
    }

    func clearSelection() {
        selectedAnnotationID = nil
        selectedSegmentID = nil
    }

    var analyzedDuration: Double {
        guard let first = segments.first, let last = segments.last else { return 0 }
        return max(0, last.end - first.start)
    }

    var pauseAnnotations: [VideoAnnotation] { annotations.filter { $0.category == .pause } }
    var totalPauseTime: Double { pauseAnnotations.compactMap(\.timing.duration).reduce(0, +) }
    var longestPause: VideoAnnotation? { pauseAnnotations.max { ($0.timing.duration ?? 0) < ($1.timing.duration ?? 0) } }
    func eventCount(_ category: AnnotationCategory) -> Int { annotations.filter { $0.category == category }.count }

    var overlayTime: Double { scrubPosition ?? position }

    var overlaySegmentType: SolveSegmentType? {
        let time = overlayTime
        if let segment = segments.first(where: { $0.start <= time && time < $0.end }) {
            return segment.type
        }
        if let pendingSegment, pendingSegment.start <= time { return pendingSegment.type }
        return nil
    }

    var overlayIntervals: [VideoAnnotation] {
        let time = overlayTime
        return annotations.filter {
            guard let end = $0.timing.end else { return false }
            return $0.timing.start <= time && time < end
        }
    }

    var overlayPointEvents: [VideoAnnotation] {
        let time = overlayTime
        return annotations.filter {
            $0.timing.end == nil && abs($0.timing.start - time) <= 0.15
        }
    }

    private func scheduleSave() {
        guard selectedSolveID != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        guard let id = selectedSolveID,
              let index = solves.firstIndex(where: { $0.id == id }) else { return }
        do {
            var solve = solves[index]
            solve.segments = segments
            solve.pendingSegment = pendingSegment
            solve.annotations = annotations
            try analysisStore.save(solve)
            solves[index] = solve
            saveMessage = nil
        } catch {
            saveMessage = "Could not save analysis: \(error.localizedDescription)"
        }
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
