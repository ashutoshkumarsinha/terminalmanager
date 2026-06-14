import SwiftUI

/// Single flat sidebar row (PF-20) — no nested `ForEach`.
struct SessionSidebarFlatRowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var configStore: ConfigStore

    let row: SessionSidebarFlatRow
    @Binding var selectedItemID: UUID?
    @Binding var expandedFolderIDs: Set<UUID>
    @Binding var expandedGroupIDs: Set<UUID>
    let onEditSession: (SessionProfile) -> Void
    let onRenameFolder: (SessionFolder) -> Void
    let onRenameGroup: (SessionGroup) -> Void
    let onDelete: (SessionTreeItem) -> Void
    let onNewSession: (UUID?) -> Void
    let onDuplicateSession: (SessionProfile) -> Void
    let onDuplicateGroup: (SessionGroup) -> Void
    let onOpenSession: (SessionProfile) -> Void
    let onOpenGroup: (SessionGroup) -> Void
    let onSaveTabsAsGroup: () -> Void
    let onTestConnection: (SessionProfile) -> Void
    let onDuplicateToFolder: (SessionProfile) -> Void
    let onBrowseSFTP: (SessionProfile) -> Void
    let onUpdateGroupLayout: (SessionGroup) -> Void
    let onCreateEmptyGroup: () -> Void

    @State private var isDropTarget = false

    var body: some View {
        rowContent
            .padding(.leading, CGFloat(depth) * 14)
            .listRowBackground(rowBackground)
            .tag(row.id)
    }

    private var depth: Int {
        switch row {
        case .folder(_, let depth), .session(_, let depth, _), .group(_, let depth), .groupMember(_, _, let depth):
            depth
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        switch row {
        case .folder(let folder, _):
            folderRow(folder)
        case .session(let profile, _, let parentFolderID):
            sessionRow(profile, parentFolderID: parentFolderID)
        case .group(let group, _):
            groupRow(group)
        case .groupMember(let groupID, let member, _):
            GroupMemberRowView(
                member: member,
                groupID: groupID,
                selectedItemID: $selectedItemID,
                onOpenSession: onOpenSession,
                onSaveTabsAsGroup: onSaveTabsAsGroup,
                onDeleteMember: { groupID, memberID in
                    _ = configStore.removeMemberFromGroup(groupID: groupID, memberID: memberID)
                    if selectedItemID == memberID {
                        selectedItemID = nil
                    }
                }
            )
        }
    }

    private func folderRow(_ folder: SessionFolder) -> some View {
        let item: SessionTreeItem = .folder(folder)
        return HStack(spacing: 4) {
            Button {
                toggleFolder(folder.id)
            } label: {
                Image(systemName: expandedFolderIDs.contains(folder.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)

            Label(folder.name, systemImage: "folder")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .sidebarSelectAndActivate(
                    itemID: folder.id,
                    selectedItemID: $selectedItemID,
                    onDoubleClick: { expandedFolderIDs.insert(folder.id) }
                )
        }
        .draggable(folder.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, onto: item)
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            Button("New Session") { onNewSession(folder.id) }
            Divider()
            Button("Rename…") { onRenameFolder(folder) }
            Divider()
            Button("Delete Folder", role: .destructive) { onDelete(item) }
            saveTabsAsGroupMenuItems
        }
    }

    private func groupRow(_ group: SessionGroup) -> some View {
        let item: SessionTreeItem = .group(group)
        return HStack(spacing: 4) {
            Button {
                toggleGroup(group.id)
            } label: {
                Image(systemName: expandedGroupIDs.contains(group.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)

            Label(group.name, systemImage: "rectangle.3.group")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .sidebarSelectAndActivate(
                    itemID: group.id,
                    selectedItemID: $selectedItemID,
                    onDoubleClick: { onOpenGroup(group) }
                )
                .contextMenu {
                    groupContextMenu(group: group, item: item)
                }
        }
        .draggable(group.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, onto: item)
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            groupContextMenu(group: group, item: item)
        }
    }

    private func sessionRow(_ profile: SessionProfile, parentFolderID: UUID?) -> some View {
        let item: SessionTreeItem = .session(profile)
        return HStack(spacing: 6) {
            if let tagColor = TagColorHelper.color(from: profile.tagColor) {
                Circle()
                    .fill(tagColor)
                    .frame(width: 8, height: 8)
            }
            Label(profile.name, systemImage: SessionLookup.icon(for: profile.protocolType))
            Spacer()
            if profile.sftpEnabled {
                Button { onBrowseSFTP(profile) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                Button { appState.launchSFTP(for: profile) } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .sidebarSelectAndActivate(
            itemID: profile.id,
            selectedItemID: $selectedItemID,
            onDoubleClick: { onOpenSession(profile) }
        )
        .draggable(profile.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, onto: item, parentFolderID: parentFolderID)
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            Button("New Session") { onNewSession(parentFolderID) }
            Divider()
            Button("Connect") { onOpenSession(profile) }
            Button("Test Connection") { onTestConnection(profile) }
            Button("Edit…") { onEditSession(profile) }
            Button("Duplicate") { onDuplicateSession(profile) }
            Button("Duplicate to Folder") { onDuplicateToFolder(profile) }
            if profile.sftpEnabled {
                Button("Browse SFTP…") { onBrowseSFTP(profile) }
                Button("SFTP") { appState.launchSFTP(for: profile) }
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete(item) }
            saveTabsAsGroupMenuItems
        }
    }

    @ViewBuilder
    private var saveTabsAsGroupMenuItems: some View {
        if !appState.tabs.isEmpty {
            Divider()
            Button("Save Tabs as Group…", action: onSaveTabsAsGroup)
        }
    }

    @ViewBuilder
    private func groupContextMenu(group: SessionGroup, item: SessionTreeItem) -> some View {
        Button("Open Group") { onOpenGroup(group) }
        Divider()
        Button("Rename…") {
            selectedItemID = group.id
            onRenameGroup(group)
        }
        Button("Duplicate Group") {
            selectedItemID = group.id
            onDuplicateGroup(group)
        }
        Button("Update Group Layout") { onUpdateGroupLayout(group) }
            .disabled(appState.tabs.isEmpty)
        Button("New Empty Group", action: onCreateEmptyGroup)
        Divider()
        Button("Delete", role: .destructive) {
            selectedItemID = group.id
            onDelete(item)
        }
        saveTabsAsGroupMenuItems
    }

    private var rowBackground: some View {
        Group {
            if isDropTarget {
                Color.accentColor.opacity(0.15)
            } else if selectedItemID == row.id {
                Color.accentColor.opacity(0.28)
            } else {
                Color.clear
            }
        }
    }

    private func toggleFolder(_ id: UUID) {
        if expandedFolderIDs.contains(id) {
            expandedFolderIDs.remove(id)
        } else {
            expandedFolderIDs.insert(id)
        }
    }

    private func toggleGroup(_ id: UUID) {
        if expandedGroupIDs.contains(id) {
            expandedGroupIDs.remove(id)
        } else {
            expandedGroupIDs.insert(id)
        }
    }

    private func handleDrop(_ items: [String], onto target: SessionTreeItem, parentFolderID: UUID? = nil) -> Bool {
        guard let draggedID = items.compactMap({ UUID(uuidString: $0) }).first else { return false }
        guard draggedID != target.id else { return false }

        switch target {
        case .folder(let folder):
            return configStore.moveItem(
                withID: draggedID,
                toParentFolderID: folder.id,
                beforeItemID: nil
            )
        case .group(let group):
            if ConfigStore.findSessionProfile(id: draggedID, in: configStore.sessionTree) != nil {
                return configStore.addSessionToGroup(groupID: group.id, sessionID: draggedID)
            }
            return configStore.moveItem(
                withID: draggedID,
                toParentFolderID: parentFolderID,
                beforeItemID: group.id
            )
        case .session:
            return configStore.moveItem(
                withID: draggedID,
                toParentFolderID: parentFolderID,
                beforeItemID: target.id
            )
        }
    }
}
