import Foundation

enum UserGuideLoader {
    static func markdownURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "USER_GUIDE", withExtension: "md") {
            return bundled
        }

        for root in searchRoots() {
            let url = root.appendingPathComponent("docs/USER_GUIDE.md")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    static func loadMarkdown() -> String {
        guard let url = markdownURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return """
            # User Guide Not Found

            The user guide could not be located. When running from source, open `docs/USER_GUIDE.md` in the project directory.
            """
        }
        return text
    }

    private static func searchRoots() -> [URL] {
        var roots: [URL] = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        roots.append(sourceRoot)

        if let resourceRoot = Bundle.main.resourceURL {
            roots.append(resourceRoot)
            roots.append(resourceRoot.deletingLastPathComponent().deletingLastPathComponent())
        }

        return roots
    }
}
