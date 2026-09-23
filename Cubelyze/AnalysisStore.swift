import Foundation

struct AnalysisStore {
    private var solvesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cubelyze/Solves", isDirectory: true)
    }

    func allSolves() throws -> [Solve] {
        guard FileManager.default.fileExists(atPath: solvesDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: solvesDirectory,
                                                           includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(Solve.self, from: Data(contentsOf: $0)) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func save(_ solve: Solve) throws {
        try FileManager.default.createDirectory(at: solvesDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(solve).write(
            to: solvesDirectory.appendingPathComponent("\(solve.id.uuidString).json"), options: .atomic)
    }

    func resolveVideoURL(for solve: Solve) -> URL {
        var stale = false
        let bookmarked = solve.videoBookmark.flatMap {
            try? URL(resolvingBookmarkData: $0, options: .withSecurityScope,
                    relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        return bookmarked ?? URL(fileURLWithPath: solve.videoPath)
    }

    func videoExists(for solve: Solve) -> Bool {
        FileManager.default.fileExists(atPath: resolveVideoURL(for: solve).path)
    }

    func bookmark(for videoURL: URL) -> Data? {
        try? videoURL.bookmarkData(options: .withSecurityScope,
                                   includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
