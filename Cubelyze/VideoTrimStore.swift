import AVFoundation
import Foundation

struct PendingTrimReceipt: Codable {
    let solveID: UUID
    let originalPath: String
    let originalBookmark: Data?
    let originalSize: Int64
    let originalModificationDate: Date?
    let originalFileNumber: UInt64?
    let trimmedPath: String
}

enum VideoTrimError: LocalizedError {
    case unsupportedFormat
    case invalidOutput
    case noSpaceSaved
    case changedOriginal

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "This video's format cannot be trimmed without conversion."
        case .invalidOutput: return "The trimmed video could not be verified. The original was kept."
        case .noSpaceSaved: return "The exported video was not smaller than the original. Nothing was replaced."
        case .changedOriginal: return "The original video changed after trimming, so it was kept."
        }
    }
}

struct VideoTrimStore {
    private let files = FileManager.default

    private var baseDirectory: URL {
        files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cubelyze", isDirectory: true)
    }

    private var trimmedDirectory: URL {
        baseDirectory.appendingPathComponent("Trimmed", isDirectory: true)
    }

    private var receiptsDirectory: URL {
        baseDirectory.appendingPathComponent("PendingTrims", isDirectory: true)
    }

    func fingerprint(for url: URL) throws -> (size: Int64, modified: Date?, fileNumber: UInt64?) {
        let attributes = try files.attributesOfItem(atPath: url.path)
        return ((attributes[.size] as? NSNumber)?.int64Value ?? 0,
                attributes[.modificationDate] as? Date,
                (attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
    }

    func export(source: URL, start: Double, end: Double) async throws -> (url: URL, duration: Double, size: Int64) {
        try files.createDirectory(at: trimmedDirectory, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetPassthrough) else {
            throw VideoTrimError.unsupportedFormat
        }
        let preferred: AVFileType = source.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        guard let fileType = ([preferred, .mov, .mp4].first {
            session.supportedFileTypes.contains($0)
        }) else { throw VideoTrimError.unsupportedFormat }
        let fileExtension = fileType == .mp4 ? "mp4" : "mov"
        let identifier = UUID().uuidString
        let name = source.deletingPathExtension().lastPathComponent
        let temporary = trimmedDirectory.appendingPathComponent(".exporting-\(identifier).\(fileExtension)")
        let output = trimmedDirectory.appendingPathComponent("\(name)-trimmed-\(identifier).\(fileExtension)")
        var completed = false
        defer { if !completed { try? files.removeItem(at: temporary) } }

        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 60_000),
            duration: CMTime(seconds: end - start, preferredTimescale: 60_000))
        session.outputURL = temporary
        session.outputFileType = fileType
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                if session.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: session.error ?? VideoTrimError.invalidOutput)
                }
            }
        }
        let exportedDuration = try await AVURLAsset(url: temporary).load(.duration).seconds
        guard exportedDuration.isFinite, exportedDuration > 0,
              abs(exportedDuration - (end - start)) <= 0.1 else {
            throw VideoTrimError.invalidOutput
        }
        let outputSize = try fingerprint(for: temporary).size
        guard outputSize > 0, outputSize < (try fingerprint(for: source).size) else {
            throw VideoTrimError.noSpaceSaved
        }
        try files.moveItem(at: temporary, to: output)
        completed = true
        return (output, exportedDuration, outputSize)
    }

    func saveReceipt(_ receipt: PendingTrimReceipt) throws {
        try files.createDirectory(at: receiptsDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(receipt)
        try data.write(to: receiptURL(for: receipt.solveID), options: .atomic)
    }

    func receipts() throws -> [PendingTrimReceipt] {
        guard files.fileExists(atPath: receiptsDirectory.path) else { return [] }
        return try files.contentsOfDirectory(at: receiptsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(PendingTrimReceipt.self, from: Data(contentsOf: $0)) }
    }

    func removeReceipt(for solveID: UUID) throws {
        let url = receiptURL(for: solveID)
        if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
    }

    func discardTrimmedFile(at url: URL) throws {
        guard url.standardizedFileURL.deletingLastPathComponent() == trimmedDirectory.standardizedFileURL else {
            throw VideoTrimError.invalidOutput
        }
        if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
    }

    private func receiptURL(for solveID: UUID) -> URL {
        receiptsDirectory.appendingPathComponent("\(solveID.uuidString).json")
    }
}
