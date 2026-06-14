import Foundation

enum SessionTreeFilter {
    /// Returns a filtered copy of the session tree matching `query` against name, host, or protocol.
    static func filter(_ items: [SessionTreeItem], query: String) -> [SessionTreeItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let needle = trimmed.lowercased()
        return items.compactMap { filterItem($0, needle: needle) }
    }

    static func matches(_ profile: SessionProfile, needle: String) -> Bool {
        if profile.name.lowercased().contains(needle) { return true }
        if profile.host.lowercased().contains(needle) { return true }
        if profile.protocolType.rawValue.lowercased().contains(needle) { return true }
        if profile.protocolType.displayName.lowercased().contains(needle) { return true }
        if profile.username.lowercased().contains(needle) { return true }
        return false
    }

    private static func filterItem(_ item: SessionTreeItem, needle: String) -> SessionTreeItem? {
        switch item {
        case .session(let profile):
            return matches(profile, needle: needle) ? item : nil

        case .folder(var folder):
            let children = filter(folder.children, query: needle)
            guard !children.isEmpty else { return nil }
            folder.children = children
            return .folder(folder)

        case .group(let group):
            if group.name.lowercased().contains(needle) {
                return item
            }
            return nil
        }
    }
}
