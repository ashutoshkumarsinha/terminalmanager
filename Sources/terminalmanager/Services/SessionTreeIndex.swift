import Foundation

/// O(1) lookup index for the session tree. Rebuilt when `sessionTree` changes.
struct SessionTreeIndex {
    private var itemsByID: [UUID: SessionTreeItem] = [:]
    private var parentFolderByItemID: [UUID: UUID] = [:]

    mutating func rebuild(from items: [SessionTreeItem]) {
        itemsByID.removeAll(keepingCapacity: true)
        parentFolderByItemID.removeAll(keepingCapacity: true)
        indexItems(items, parentFolderID: nil)
    }

    func item(withID id: UUID) -> SessionTreeItem? {
        itemsByID[id]
    }

    func parentFolderID(of itemID: UUID) -> UUID? {
        parentFolderByItemID[itemID]
    }

    func sessionProfile(withID id: UUID) -> SessionProfile? {
        guard case .session(let profile) = itemsByID[id] else { return nil }
        return profile
    }

    private mutating func indexItems(_ items: [SessionTreeItem], parentFolderID: UUID?) {
        for item in items {
            itemsByID[item.id] = item
            if let parentFolderID {
                parentFolderByItemID[item.id] = parentFolderID
            }
            if case .folder(let folder) = item {
                indexItems(folder.children, parentFolderID: folder.id)
            }
        }
    }
}
