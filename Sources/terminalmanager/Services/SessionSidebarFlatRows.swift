import Foundation

/// Flat row model for virtualized sidebar rendering (PF-20).
enum SessionSidebarFlatRow: Identifiable, Hashable {
    case folder(SessionFolder, depth: Int)
    case session(SessionProfile, depth: Int, parentFolderID: UUID?)
    case group(SessionGroup, depth: Int)
    case groupMember(groupID: UUID, member: SessionGroupMember, depth: Int)

    var id: UUID {
        switch self {
        case .folder(let folder, _): folder.id
        case .session(let profile, _, _): profile.id
        case .group(let group, _): group.id
        case .groupMember(_, let member, _): member.id
        }
    }
}

enum SessionSidebarFlatRowBuilder {
    static func build(
        from items: [SessionTreeItem],
        expandedFolderIDs: Set<UUID>,
        expandedGroupIDs: Set<UUID>,
        parentFolderID: UUID? = nil,
        depth: Int = 0
    ) -> [SessionSidebarFlatRow] {
        var rows: [SessionSidebarFlatRow] = []
        for item in items {
            switch item {
            case .folder(let folder):
                rows.append(.folder(folder, depth: depth))
                if expandedFolderIDs.contains(folder.id) {
                    rows += build(
                        from: folder.children,
                        expandedFolderIDs: expandedFolderIDs,
                        expandedGroupIDs: expandedGroupIDs,
                        parentFolderID: folder.id,
                        depth: depth + 1
                    )
                }
            case .session(let profile):
                rows.append(.session(profile, depth: depth, parentFolderID: parentFolderID))
            case .group(let group):
                rows.append(.group(group, depth: depth))
                if expandedGroupIDs.contains(group.id) {
                    for member in group.members {
                        rows.append(.groupMember(groupID: group.id, member: member, depth: depth + 1))
                    }
                }
            }
        }
        return rows
    }

    static func allFolderIDs(in items: [SessionTreeItem]) -> Set<UUID> {
        var ids = Set<UUID>()
        collectFolderIDs(items, into: &ids)
        return ids
    }

    static func allGroupIDs(in items: [SessionTreeItem]) -> Set<UUID> {
        var ids = Set<UUID>()
        collectGroupIDs(items, into: &ids)
        return ids
    }

    private static func collectFolderIDs(_ items: [SessionTreeItem], into ids: inout Set<UUID>) {
        for item in items {
            switch item {
            case .folder(let folder):
                ids.insert(folder.id)
                collectFolderIDs(folder.children, into: &ids)
            case .session, .group:
                break
            }
        }
    }

    private static func collectGroupIDs(_ items: [SessionTreeItem], into ids: inout Set<UUID>) {
        for item in items {
            switch item {
            case .group(let group):
                ids.insert(group.id)
            case .folder(let folder):
                collectGroupIDs(folder.children, into: &ids)
            case .session:
                break
            }
        }
    }
}
