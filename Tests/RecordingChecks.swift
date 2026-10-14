import AVFoundation
import Foundation

@main
struct RecordingChecks {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AnalysisStore(directory: folder.appendingPathComponent("Solves"))
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let originalBytes = try Data(contentsOf: sourceURL)
        var source = Solve(videoPath: sourceURL.path, videoBookmark: nil, recordedAt: Date())
        source.isRecording = true
        source.pendingExtractionStart = 1.8
        var first = Solve(videoPath: source.videoPath, videoBookmark: nil, recordedAt: source.recordedAt)
        first.sourceRecordingID = source.id
        first.sourceRange = RecordingRange(start: 0.2, end: 0.8)
        first.scramble = "R U R'"
        first.annotations = [VideoAnnotation(timing: .point(0.2), category: .rotation)]
        var second = Solve(videoPath: source.videoPath, videoBookmark: nil, recordedAt: source.recordedAt)
        second.sourceRecordingID = source.id
        second.sourceRange = RecordingRange(start: 1, end: 1.7)
        precondition(first.id != second.id)
        precondition(first.sourceRange!.isValid(duration: 2, excluding: [second.sourceRange!]))
        precondition(RecordingRange(start: 0.8, end: 1).isValid(duration: 2, excluding: [first.sourceRange!, second.sourceRange!]))
        for range in [RecordingRange(start: .nan, end: 1), RecordingRange(start: -1, end: 0.1),
                      RecordingRange(start: 1, end: 0.5), RecordingRange(start: 1, end: 3),
                      RecordingRange(start: 0.5, end: 1.1)] {
            precondition(!range.isValid(duration: 2, excluding: [first.sourceRange!, second.sourceRange!]))
        }
        for solve in [source, first, second] { try store.save(solve) }
        let restored = try store.allSolves()
        precondition(restored.count == 3)
        precondition(restored.first { $0.id == first.id }!.annotations.count == 1)
        precondition(restored.first { $0.id == second.id }!.annotations.isEmpty)
        precondition(restored.first { $0.id == source.id }!.pendingExtractionStart == 1.8)
        precondition(restored.first { $0.id == first.id }!.sourceRange == first.sourceRange)
        precondition(restored.first { $0.id == first.id }!.scramble == "R U R'")
        try store.remove(second)
        let afterDelete = try store.allSolves()
        precondition(afterDelete.count == 2)
        try store.save(second)
        let afterUndo = try store.allSolves()
        precondition(afterUndo.count == 3)
        let clip = try await PlaybackModel.clipAsset(source: sourceURL, range: first.sourceRange!)
        let clipDuration = try await clip.load(.duration).seconds
        precondition(abs(clipDuration - 0.6) < 0.00001)
        let tracks = try await clip.loadTracks(withMediaType: .video)
        let timeRange = try await tracks[0].load(.timeRange)
        precondition(timeRange.start == .zero && abs(timeRange.duration.seconds - 0.6) < 0.00001)
        do {
            _ = try await PlaybackModel.clipAsset(source: sourceURL, range: RecordingRange(start: 1, end: 3))
            preconditionFailure("Out-of-bounds source accepted")
        } catch {}
        let finalBytes = try Data(contentsOf: sourceURL)
        precondition(finalBytes == originalBytes)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as! [String: Any]
        for key in ["sourceRange", "sourceRecordingID", "isRecording", "pendingExtractionStart"] { legacy.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(Solve.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(old.sourceRange == nil && old.isRecording == nil && old.annotations.count == 1)
        print("Recording checks passed: range validation, independent analysis persistence, delete/restore storage, zero-based composition, legacy compatibility, and source preservation.")
    }
}
