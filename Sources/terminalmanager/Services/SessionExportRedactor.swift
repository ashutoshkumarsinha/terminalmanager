import Foundation

enum SessionExportRedactor {
    static func redact(_ items: [SessionTreeItem]) -> [SessionTreeItem] {
        items.map { redactItem($0) }
    }

    static func redactProfile(_ profile: SessionProfile) -> SessionProfile {
        var copy = profile
        copy.password = ""
        if copy.notesInKeychain || !copy.notes.isEmpty {
            copy.notes = ""
            copy.notesInKeychain = false
        }
        return copy
    }

    private static func redactItem(_ item: SessionTreeItem) -> SessionTreeItem {
        switch item {
        case .session(let profile):
            return .session(redactProfile(profile))
        case .folder(var folder):
            folder.children = redact(folder.children)
            return .folder(folder)
        case .group:
            return item
        }
    }
}
