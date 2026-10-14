import AppKit
import AVFoundation
import Foundation

@main
struct RecordingPlaybackChecks {
    @MainActor
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("practice.mov")
        try FileManager.default.copyItem(atPath: CommandLine.arguments[1], toPath: source.path)
        let original = try Data(contentsOf: source)
        let store = AnalysisStore(directory: folder.appendingPathComponent("Solves"))
        let model = PlaybackModel(analysisStore: store, finalizeTrims: false)
        print("Importing generated recording")
        await model.importRecording(source)
        print("Waiting for playback")
        try await ready(model)
        print("Playback ready")
        let recordingID = model.selectedSolveID!
        precondition(model.isExtracting && model.librarySolves.isEmpty)
        await seek(model, 0.2)
        model.markExtractionStart()
        await seek(model, 0.8)
        model.markExtractionEnd()
        precondition(model.extractedSolves.count == 1)
        await seek(model, 1.0)
        model.markExtractionStart()
        await seek(model, 1.7)
        model.markExtractionEnd()
        precondition(model.extractedSolves.count == 2 && model.librarySolves.count == 2)
        let first = model.extractedSolves[0]
        let second = model.extractedSolves[1]
        precondition(first.id != second.id && first.videoPath == second.videoPath)
        precondition(first.sourceRecordingID == recordingID)
        precondition(abs(first.sourceRange!.duration - 0.6) < 0.01)
        // Overlap, NaN, invalid ordering, and out-of-bounds edits must be rejected.
        precondition(!RecordingRange(start: 0.5, end: 1.1).isValid(duration: 2, excluding: [first.sourceRange!]))
        precondition(!RecordingRange(start: .nan, end: 1).isValid(duration: 2))
        precondition(!RecordingRange(start: 1, end: 0.5).isValid(duration: 2))
        precondition(!RecordingRange(start: 1, end: 3).isValid(duration: 2))
        model.resizeExtraction(first, start: 0.1, end: 0.7)
        let resized = model.extractedSolves[0]
        precondition(resized.sourceRange!.start == 0.1)
        // Standalone playback uses a zero-based composition and never modifies the source.
        let clip = try await PlaybackModel.clipAsset(source: source, range: resized.sourceRange!)
        let clipDuration = try await clip.load(.duration).seconds
        precondition(abs(clipDuration - 0.6) < 0.01)
        let image = try await AVAssetImageGenerator(asset: clip).image(at: .zero)
        precondition(image.image.width == 64)
        do {
            _ = try await PlaybackModel.clipAsset(source: source, range: RecordingRange(start: 1, end: 3))
            preconditionFailure("Invalid source range accepted")
        } catch {}
        model.openSolve(resized)
        try await ready(model)
        precondition(!model.isExtracting && abs(model.duration - 0.6) < 0.01)
        await seek(model, 0.2)
        model.addAnnotation(.rotation)
        model.showLibrary() // flush local analysis synchronously
        let annotated = model.librarySolves.first { $0.id == resized.id }!
        precondition(annotated.annotations.count == 1)
        precondition(abs(annotated.annotations[0].timing.start - 0.2) < 0.01)
        precondition(model.librarySolves.first { $0.id == second.id }!.annotations.isEmpty)
        let sourceSolve = model.recordings.first!
        model.openSolve(sourceSolve)
        try await ready(model)
        model.resizeExtraction(annotated, start: 0, end: 0.5)
        precondition(model.extractedSolves.first!.sourceRange == resized.sourceRange)
        model.deleteExtraction(second)
        precondition(model.extractedSolves.count == 1)
        model.showLibrary()
        let restored = PlaybackModel(analysisStore: store, finalizeTrims: false)
        precondition(restored.recordings.count == 1 && restored.librarySolves.count == 1)
        precondition(restored.librarySolves[0].annotations.count == 1)
        precondition(restored.librarySolves[0].sourceRange == resized.sourceRange)
        let after = try Data(contentsOf: source)
        precondition(after == original)
        // Older solve JSON omits all new optional fields.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(annotated)) as! [String: Any]
        for key in ["sourceRange", "sourceRecordingID", "isRecording", "pendingExtractionStart"] { legacy.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(Solve.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(old.sourceRange == nil && old.isRecording == nil && old.annotations.count == 1)
        print("Recording checks passed: extraction, validation, local playback, independent analysis, persistence, legacy compatibility, and source preservation.")
    }

    @MainActor static func ready(_ model: PlaybackModel) async throws {
        for _ in 0..<200 {
            model.refresh()
            if model.isReady && model.duration > 0 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        fatalError("Video failed to become ready: \(model.errorMessage ?? "unknown")")
    }

    @MainActor static func seek(_ model: PlaybackModel, _ time: Double) async {
        model.seek(to: time)
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(10))
            model.refresh()
            if abs(model.position - time) < 0.005 { return }
        }
        fatalError("Seek failed")
    }

}
