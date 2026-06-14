import Foundation

enum SessionTreeFilter {
    /// Returns a filtered copy of the session tree matching `query` against name, host, protocol, or notes.
    static func filter(_ items: [SessionTreeItem], query: String) -> [SessionTreeItem] {
        filter(items, query: query, searchIndex: nil)
    }

    static func filter(
        _ items: [SessionTreeItem],
        query: String,
        searchIndex: SessionTreeSearchIndex?
    ) -> [SessionTreeItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let needle = trimmed.lowercased()
        return items.compactMap { filterItem($0, needle: needle, searchIndex: searchIndex) }
    }

    static func matches(_ profile: SessionProfile, needle: String) -> Bool {
        if profile.name.lowercased().contains(needle) { return true }
        if profile.host.lowercased().contains(needle) { return true }
        if profile.protocolType.rawValue.lowercased().contains(needle) { return true }
        if profile.protocolType.displayName.lowercased().contains(needle) { return true }
        if profile.username.lowercased().contains(needle) { return true }
        if profile.notes.lowercased().contains(needle) { return true }
        return false
    }

    private static func filterItem(
        _ item: SessionTreeItem,
        needle: String,
        searchIndex: SessionTreeSearchIndex?
    ) -> SessionTreeItem? {
        switch item {
        case .session(let profile):
            if let searchIndex {
                return searchIndex.profileMatches(profile, needle: needle) ? item : nil
            }
            return matches(profile, needle: needle) ? item : nil

        case .folder(var folder):
            let children = filter(folder.children, query: needle, searchIndex: searchIndex)
            guard !children.isEmpty else { return nil }
            folder.children = children
            return .folder(folder)

        case .group(let group):
            if let searchIndex {
                return searchIndex.groupMatches(group, needle: needle) ? item : nil
            }
            if group.name.lowercased().contains(needle) {
                return item
            }
            return nil
        }
    }
}
