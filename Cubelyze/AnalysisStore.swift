import AppKit
import CryptoKit

struct AnalysisStore {
    private let defaults = UserDefaults.standard
    private let lastProjectKey = "LastAnalysisProject"

    private var projectsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cubelyze/Projects", isDirectory: true)
    }

    func projectURL(for videoURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(videoURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return projectsDirectory.appendingPathComponent("\(digest).json")
    }

    func savedDocument(for projectURL: URL) -> AnalysisDocument? {
        guard let data = try? Data(contentsOf: projectURL) else { return nil }
        return try? JSONDecoder().decode(AnalysisDocument.self, from: data)
    }

    func lastProject() -> (url: URL, document: AnalysisDocument)? {
        guard let path = defaults.string(forKey: lastProjectKey) else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let document = savedDocument(for: url) else { return nil }
        return (url, document)
    }

    func remember(projectURL: URL) { defaults.set(projectURL.path, forKey: lastProjectKey) }

    func save(document: AnalysisDocument, to projectURL: URL) throws {
        try FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: projectURL, options: .atomic)
    }

    func resolveVideoURL(for document: AnalysisDocument) -> (url: URL?, stale: Bool) {
        var stale = false
        let resolved = document.videoBookmark.flatMap {
            try? URL(resolvingBookmarkData: $0, options: .withSecurityScope,
                    relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        return (resolved ?? URL(fileURLWithPath: document.videoPath), stale)
    }

    func bookmark(for videoURL: URL) -> Data? {
        try? videoURL.bookmarkData(options: .withSecurityScope,
                                   includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
