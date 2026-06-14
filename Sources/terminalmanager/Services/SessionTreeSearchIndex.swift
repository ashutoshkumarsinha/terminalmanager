import Foundation

/// Precomputed searchable text for fast sidebar filtering (PF-21).
struct SessionTreeSearchIndex {
    private var textByProfileID: [UUID: String] = [:]
    private var textByGroupID: [UUID: String] = [:]

    mutating func rebuild(from items: [SessionTreeItem]) {
        textByProfileID.removeAll(keepingCapacity: true)
        textByGroupID.removeAll(keepingCapacity: true)
        indexItems(items)
    }

    func profileMatches(_ profile: SessionProfile, needle: String) -> Bool {
        if let indexed = textByProfileID[profile.id] {
            return indexed.contains(needle)
        }
        return SessionTreeFilter.matches(profile, needle: needle)
    }

    func groupMatches(_ group: SessionGroup, needle: String) -> Bool {
        if let indexed = textByGroupID[group.id] {
            return indexed.contains(needle)
        }
        return group.name.lowercased().contains(needle)
    }

    private mutating func indexItems(_ items: [SessionTreeItem]) {
        for item in items {
            switch item {
            case .session(let profile):
                textByProfileID[profile.id] = searchableText(for: profile)
            case .folder(let folder):
                indexItems(folder.children)
            case .group(let group):
                textByGroupID[group.id] = group.name.lowercased()
            }
        }
    }

    private func searchableText(for profile: SessionProfile) -> String {
        [
            profile.name,
            profile.host,
            profile.username,
            profile.protocolType.rawValue,
            profile.protocolType.displayName,
            profile.notes
        ]
        .joined(separator: " ")
        .lowercased()
    }
}
