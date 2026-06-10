import SwiftUI

struct SessionSidebarView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedItemID: UUID?
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var expandedGroupIDs: Set<UUID> = []
    @State private var editingSession: SessionProfile?
    @State private var renamingFolder: SessionFolder?
    @State private var renamingGroup: SessionGroup?
    @State private var showSaveGroupSheet = false
    @State private var itemPendingDeletion: SessionTreeItem?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedItemID) {
                ForEach(appState.configStore.sessionTree) { item in
                    SessionTreeRowView(
                        item: item,
                        parentFolderID: nil,
                        selectedItemID: $selectedItemID,
                        expandedFolderIDs: $expandedFolderIDs,
                        expandedGroupIDs: $expandedGroupIDs,
                        onEditSession: { editingSession = $0 },
                        onRenameFolder: { renamingFolder = $0 },
                        onRenameGroup: { renamingGroup = $0 },
                        onDelete: { itemPendingDeletion = $0 },
                        onNewSession: { createSession(in: $0) },
                        onDuplicateSession: duplicateSession,
                        onDuplicateGroup: duplicateGroup,
                        onOpenSession: { appState.openTab(from: $0) },
                        onOpenGroup: { appState.openGroup($0) },
                        onSaveTabsAsGroup: { showSaveGroupSheet = true }
                    )
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: UUID.self) { selectedIDs in
                groupMemberContextMenu(for: selectedIDs)
            }
            .contextMenu {
                sidebarBackgroundContextMenu()
            }
            .dropDestination(for: String.self) { items, _ in
                handleRootDrop(items)
            }
        }
        .contextMenu {
            sidebarBackgroundContextMenu()
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItemGroup {
                if let profile = selectedSession {
                    Button {
                        appState.openTab(from: profile)
                    } label: {
                        Label("Connect", systemImage: "play.fill")
                    }
                    .appHelp("Open selected session in a new tab")
                }

                if let group = selectedGroup {
                    Button {
                        appState.openGroup(group)
                    } label: {
                        Label("Open Group", systemImage: "play.rectangle.on.rectangle")
                    }
                    .appHelp("Open all sessions in this group with saved layout")
                }

                if !appState.tabs.isEmpty {
                    Button {
                        showSaveGroupSheet = true
                    } label: {
                        Label("Save as Group", systemImage: "rectangle.3.group.badge.plus")
                    }
                    .appHelp("Save open tabs and their split layout as a new group")
                }

                Button {
                    beginEditingSelection()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(selectedItemID == nil)
                .appHelp("Edit selected session, folder, or group")

                if selectedSession != nil {
                    Button {
                        duplicateSelectedSession()
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .appHelp("Duplicate the selected session in the sidebar")
                }

                if selectedGroup != nil {
                    Button {
                        duplicateSelectedGroup()
                    } label: {
                        Label("Duplicate Group", systemImage: "plus.square.on.square")
                    }
                    .appHelp("Duplicate the selected group in the sidebar")
                }
            }
        }
        .onDeleteCommand {
            beginDeletingSelection()
        }
        .sheet(item: $editingSession) { profile in
            SessionEditorView(
                profile: profile,
                isNameAvailable: { candidate in
                    !appState.configStore.sessionNameExists(candidate, excludingSessionID: profile.id)
                }
            ) { saved in
                _ = appState.updateSessionProfile(saved)
            }
        }
        .sheet(item: $renamingFolder) { folder in
            FolderNameEditorView(
                name: folder.name,
                isNameAvailable: { candidate in
                    !appState.configStore.folderNameExists(candidate, excludingID: folder.id)
                }
            ) { newName in
                _ = appState.configStore.renameFolder(id: folder.id, name: newName)
            }
        }
        .sheet(item: $renamingGroup) { group in
            FolderNameEditorView(
                name: group.name,
                fieldLabel: "Group Name",
                navigationTitle: "Rename Group",
                duplicateMessage: "A group with this name already exists.",
                isNameAvailable: { candidate in
                    !appState.configStore.groupNameExists(candidate, excludingID: group.id)
                }
            ) { newName in
                _ = appState.configStore.renameGroup(id: group.id, name: newName)
            }
        }
        .sheet(isPresented: $showSaveGroupSheet) {
            FolderNameEditorView(
                name: "New Group",
                fieldLabel: "Group Name",
                navigationTitle: "Save Tab Group",
                duplicateMessage: "A group with this name already exists.",
                isNameAvailable: { candidate in
                    !appState.configStore.groupNameExists(candidate)
                }
            ) { name in
                if let group = appState.saveCurrentTabsAsGroup(name: name) {
                    selectedItemID = group.id
                }
            }
        }
        .confirmationDialog(
            "Delete \(itemPendingDeletion?.name ?? "item")?",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { if !$0 { itemPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = itemPendingDeletion {
                    appState.removeSessionItem(id: item.id)
                    if selectedItemID == item.id {
                        selectedItemID = nil
                    }
                }
                itemPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                itemPendingDeletion = nil
            }
        } message: {
            switch itemPendingDeletion {
            case .folder:
                Text("This folder and all sessions inside it will be removed.")
            case .group:
                Text("This group will be removed. Open tabs are not affected.")
            default:
                Text("This session will be removed from the sidebar. Open tabs using it will be closed.")
            }
        }
    }

    private var selectedSession: SessionProfile? {
        guard let selectedItemID else { return nil }
        return ConfigStore.findSessionProfile(id: selectedItemID, in: appState.configStore.sessionTree)
    }

    private var selectedGroup: SessionGroup? {
        guard let selectedItemID,
              let item = appState.configStore.item(withID: selectedItemID),
              case .group(let group) = item else {
            return nil
        }
        return group
    }

    private func beginEditingSelection() {
        guard let selectedItemID,
              let item = appState.configStore.item(withID: selectedItemID) else { return }
        switch item {
        case .session(let profile):
            editingSession = profile
        case .folder(let folder):
            renamingFolder = folder
        case .group(let group):
            renamingGroup = group
        }
    }

    private func beginDeletingSelection() {
        guard let selectedItemID else { return }
        if let item = appState.configStore.item(withID: selectedItemID) {
            itemPendingDeletion = item
            return
        }
        if let (groupID, member) = ConfigStore.findGroupMember(
            id: selectedItemID,
            in: appState.configStore.sessionTree
        ) {
            deleteGroupMember(groupID: groupID, memberID: member.id)
        }
    }

    private func deleteGroupMember(groupID: UUID, memberID: UUID) {
        _ = appState.configStore.removeMemberFromGroup(groupID: groupID, memberID: memberID)
        if selectedItemID == memberID {
            selectedItemID = nil
        }
    }

    @ViewBuilder
    private func groupMemberContextMenu(for selectedIDs: Set<UUID>) -> some View {
        if selectedIDs.count == 1,
           let selectedID = selectedIDs.first,
           let (groupID, member) = ConfigStore.findGroupMember(
               id: selectedID,
               in: appState.configStore.sessionTree
           ) {
            if let profile = ConfigStore.findSessionProfile(
                id: member.sessionID,
                in: appState.configStore.sessionTree
            ) {
                Button("Connect") { appState.openTab(from: profile) }
                Divider()
            }
            Button("Delete", role: .destructive) {
                deleteGroupMember(groupID: groupID, memberID: member.id)
            }
            if !appState.tabs.isEmpty {
                Divider()
                Button("Save Tabs as Group…") { showSaveGroupSheet = true }
            }
        }
    }

    private func createFolder() {
        let folder = appState.configStore.addFolder("New Folder")
        selectedItemID = folder.id
        renamingFolder = folder
    }

    private func createSession(in folderID: UUID? = nil) {
        let profile = SessionProfile(name: "New Session", host: "example.com", username: "user")
        let saved = appState.configStore.addSession(profile, to: folderID)
        editingSession = saved
    }

    private func duplicateSelectedSession() {
        guard let profile = selectedSession else { return }
        duplicateSession(profile)
    }

    private func duplicateSelectedGroup() {
        guard let group = selectedGroup else { return }
        duplicateGroup(group)
    }

    private func duplicateGroup(_ group: SessionGroup) {
        guard let saved = appState.configStore.duplicateGroup(id: group.id) else { return }
        selectedItemID = saved.id
    }

    private func duplicateSession(_ profile: SessionProfile) {
        guard let saved = appState.configStore.duplicateSession(id: profile.id) else { return }
        if saved.sshAuthMethod == .password, !saved.password.isEmpty {
            _ = SSHAuthHelper.writeAskpassScript(password: saved.password, profileID: saved.id)
        }
        selectedItemID = saved.id
        editingSession = saved
    }

    private func handleRootDrop(_ items: [String]) -> Bool {
        guard let draggedID = items.compactMap({ UUID(uuidString: $0) }).first else { return false }
        return appState.configStore.moveItem(withID: draggedID, toParentFolderID: nil, beforeItemID: nil)
    }

    @ViewBuilder
    private func sidebarBackgroundContextMenu() -> some View {
        Button("New Folder") { createFolder() }
        Button("New Session") { createSession() }
        if let group = selectedGroup {
            Button("Duplicate Group") { duplicateGroup(group) }
        }
        if !appState.tabs.isEmpty {
            Divider()
            Button("Save Tabs as Group…") { showSaveGroupSheet = true }
        }
    }
}

private struct SessionTreeRowView: View {
    @EnvironmentObject private var appState: AppState

    let item: SessionTreeItem
    let parentFolderID: UUID?
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

    @State private var isDropTarget = false

    var body: some View {
        switch item {
        case .folder(let folder):
            DisclosureGroup(
                isExpanded: folderExpansionBinding(for: folder.id),
                content: {
                    ForEach(folder.children) { child in
                        SessionTreeRowView(
                            item: child,
                            parentFolderID: folder.id,
                            selectedItemID: $selectedItemID,
                            expandedFolderIDs: $expandedFolderIDs,
                            expandedGroupIDs: $expandedGroupIDs,
                            onEditSession: onEditSession,
                            onRenameFolder: onRenameFolder,
                            onRenameGroup: onRenameGroup,
                            onDelete: onDelete,
                            onNewSession: onNewSession,
                            onDuplicateSession: onDuplicateSession,
                            onDuplicateGroup: onDuplicateGroup,
                            onOpenSession: onOpenSession,
                            onOpenGroup: onOpenGroup,
                            onSaveTabsAsGroup: onSaveTabsAsGroup
                        )
                    }
                },
                label: {
                    Label(folder.name, systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .sidebarSelectAndActivate(
                            itemID: folder.id,
                            selectedItemID: $selectedItemID,
                            onDoubleClick: { expandedFolderIDs.insert(folder.id) }
                        )
                }
            )
            .tag(folder.id)
            .listRowBackground(rowBackground(for: folder.id))
            .draggable(item.id.uuidString)
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

        case .group(let group):
            DisclosureGroup(
                isExpanded: groupExpansionBinding(for: group.id),
                content: {
                    ForEach(group.members) { member in
                        GroupMemberRowView(
                            member: member,
                            groupID: group.id,
                            selectedItemID: $selectedItemID,
                            onOpenSession: onOpenSession,
                            onSaveTabsAsGroup: onSaveTabsAsGroup,
                            onDeleteMember: { groupID, memberID in
                                _ = appState.configStore.removeMemberFromGroup(groupID: groupID, memberID: memberID)
                                if selectedItemID == memberID {
                                    selectedItemID = nil
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 8))
                    }
                },
                label: {
                    Label(group.name, systemImage: "rectangle.3.group")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .sidebarSelectAndActivate(
                            itemID: group.id,
                            selectedItemID: $selectedItemID,
                            onDoubleClick: { onOpenGroup(group) }
                        )
                        .contextMenu {
                            groupContextMenu(group: group)
                        }
                }
            )
            .tag(group.id)
            .listRowBackground(rowBackground(for: group.id))
            .draggable(item.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items, onto: item)
            } isTargeted: { isDropTarget = $0 }
            .contextMenu {
                groupContextMenu(group: group)
            }

        case .session(let profile):
            HStack {
                Label(profile.name, systemImage: SessionLookup.icon(for: profile.protocolType))
                Spacer()
                if profile.sftpEnabled {
                    Button {
                        appState.launchSFTP(for: profile)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                    .appHelp("Open SFTP in Ghostty")
                }
            }
            .tag(profile.id)
            .listRowBackground(rowBackground(for: profile.id))
            .sidebarSelectAndActivate(
                itemID: profile.id,
                selectedItemID: $selectedItemID,
                onDoubleClick: { onOpenSession(profile) }
            )
            .draggable(item.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items, onto: item)
            } isTargeted: { isDropTarget = $0 }
            .contextMenu {
                Button("New Session") { onNewSession(parentFolderID) }
                Divider()
                Button("Connect") { onOpenSession(profile) }
                Button("Edit…") { onEditSession(profile) }
                Button("Duplicate") { onDuplicateSession(profile) }
                if profile.sftpEnabled {
                    Button("SFTP") { appState.launchSFTP(for: profile) }
                }
                Divider()
                Button("Delete", role: .destructive) { onDelete(item) }
                saveTabsAsGroupMenuItems
            }
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
    private func groupContextMenu(group: SessionGroup) -> some View {
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
        Divider()
        Button("Delete", role: .destructive) {
            selectedItemID = group.id
            onDelete(item)
        }
        saveTabsAsGroupMenuItems
    }

    private func folderExpansionBinding(for folderID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedFolderIDs.contains(folderID) },
            set: { isExpanded in
                if isExpanded {
                    expandedFolderIDs.insert(folderID)
                } else {
                    expandedFolderIDs.remove(folderID)
                }
            }
        )
    }

    private func groupExpansionBinding(for groupID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedGroupIDs.contains(groupID) },
            set: { isExpanded in
                if isExpanded {
                    expandedGroupIDs.insert(groupID)
                } else {
                    expandedGroupIDs.remove(groupID)
                }
            }
        )
    }

    private func rowBackground(for itemID: UUID) -> some View {
        Group {
            if isDropTarget {
                Color.accentColor.opacity(0.15)
            } else if selectedItemID == itemID {
                Color.accentColor.opacity(0.28)
            } else {
                Color.clear
            }
        }
    }

    private func handleDrop(_ items: [String], onto target: SessionTreeItem) -> Bool {
        guard let draggedID = items.compactMap({ UUID(uuidString: $0) }).first else { return false }
        guard draggedID != target.id else { return false }

        switch target {
        case .folder(let folder):
            return appState.configStore.moveItem(
                withID: draggedID,
                toParentFolderID: folder.id,
                beforeItemID: nil
            )
        case .group(let group):
            if ConfigStore.findSessionProfile(id: draggedID, in: appState.configStore.sessionTree) != nil {
                return appState.configStore.addSessionToGroup(groupID: group.id, sessionID: draggedID)
            }
            return appState.configStore.moveItem(
                withID: draggedID,
                toParentFolderID: parentFolderID,
                beforeItemID: group.id
            )
        case .session:
            return appState.configStore.moveItem(
                withID: draggedID,
                toParentFolderID: parentFolderID,
                beforeItemID: target.id
            )
        }
    }
}

private struct GroupMemberRowView: View {
    @EnvironmentObject private var appState: AppState

    let member: SessionGroupMember
    let groupID: UUID
    @Binding var selectedItemID: UUID?
    let onOpenSession: (SessionProfile) -> Void
    let onSaveTabsAsGroup: () -> Void
    let onDeleteMember: (UUID, UUID) -> Void

    var body: some View {
        memberLabel
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(member.id)
            .listRowBackground(memberRowBackground)
            .sidebarSelectAndActivate(
                itemID: member.id,
                selectedItemID: $selectedItemID,
                onDoubleClick: {
                    if let profile = sessionProfile {
                        onOpenSession(profile)
                    }
                }
            )
            .contextMenu {
                memberContextMenu
            }
    }

    @ViewBuilder
    private var memberLabel: some View {
        if let profile = sessionProfile {
            Label(profile.name, systemImage: SessionLookup.icon(for: profile.protocolType))
        } else {
            Label("Missing session", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var memberContextMenu: some View {
        if let profile = sessionProfile {
            Button("Connect") { onOpenSession(profile) }
            Divider()
        }
        Button("Delete", role: .destructive) {
            onDeleteMember(groupID, member.id)
        }
        if !appState.tabs.isEmpty {
            Divider()
            Button("Save Tabs as Group…", action: onSaveTabsAsGroup)
        }
    }

    private var sessionProfile: SessionProfile? {
        ConfigStore.findSessionProfile(id: member.sessionID, in: appState.configStore.sessionTree)
    }

    private var memberRowBackground: some View {
        Group {
            if selectedItemID == member.id {
                Color.accentColor.opacity(0.28)
            } else {
                Color.clear
            }
        }
    }
}

private enum SessionLookup {
    static func icon(for protocolType: ConnectionProtocol) -> String {
        switch protocolType {
        case .ssh: "lock.shield"
        case .telnet: "network"
        case .rlogin: "person.crop.circle"
        case .raw: "cable.connector"
        case .local: "terminal"
        }
    }
}

private extension View {
    func sidebarSelectAndActivate(
        itemID: UUID,
        selectedItemID: Binding<UUID?>,
        onDoubleClick: @escaping () -> Void
    ) -> some View {
        contentShape(Rectangle())
            .onTapGesture {
                selectedItemID.wrappedValue = itemID
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    selectedItemID.wrappedValue = itemID
                    onDoubleClick()
                }
            )
    }
}
