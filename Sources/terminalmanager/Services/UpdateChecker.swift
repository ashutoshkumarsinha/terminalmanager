import Foundation

enum UpdateChecker {
    struct ReleaseInfo: Decodable {
        let tagName: String
        let htmlURL: String
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
        }
    }

    struct UpdateInfo: Equatable {
        let version: String
        let downloadURL: String
        let releaseNotes: String?
    }

    static func fetchUpdateInfo(
        currentVersion: String,
        repository: String = "terminalmanager/terminalmanager"
    ) async -> UpdateInfo? {
        guard let release = await fetchLatestRelease(repository: repository) else { return nil }
        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let current = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard latest.compare(current, options: .numeric) == .orderedDescending else { return nil }
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateInfo(
            version: release.tagName,
            downloadURL: release.htmlURL,
            releaseNotes: notes?.isEmpty == false ? notes : nil
        )
    }

    static func checkForUpdate(currentVersion: String, repository: String = "terminalmanager/terminalmanager") async -> String? {
        await fetchUpdateInfo(currentVersion: currentVersion, repository: repository)?.downloadURL
    }

    private static func fetchLatestRelease(repository: String) async -> ReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await UpdateCheckerTesting.urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(ReleaseInfo.self, from: data)
        } catch {
            AppLogger.shared.debug("Update check failed: \(error)")
            return nil
        }
    }
}

enum UpdateCheckerTesting {
    static var urlSession: URLSession = .shared
}
