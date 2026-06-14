import SwiftUI

struct SessionSidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var configStore: ConfigStore

    @State private var selectedItemID: UUID?
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var expandedGroupIDs: Set<UUID> = []
    @State private var editingSession: SessionProfile?
    @State private var renamingFolder: SessionFolder?
    @State private var renamingGroup: SessionGroup?
    @State private var showSaveGroupSheet = false
    @State private var itemPendingDeletion: SessionTreeItem?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var connectionTestMessage: String?
    @State private var sftpBrowseProfile: SessionProfile?

    private var isSearching: Bool {
        !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredTree: [SessionTreeItem] {
        configStore.filteredSessionTree(query: debouncedSearchText)
    }

    private var displayRows: [SessionSidebarFlatRow] {
        let tree = isSearching ? filteredTree : configStore.sessionTree
        let folderExpansion = isSearching
            ? SessionSidebarFlatRowBuilder.allFolderIDs(in: tree)
            : expandedFolderIDs
        let groupExpansion = isSearching
            ? SessionSidebarFlatRowBuilder.allGroupIDs(in: tree)
            : expandedGroupIDs
        return SessionSidebarFlatRowBuilder.build(
            from: tree,
            expandedFolderIDs: folderExpansion,
            expandedGroupIDs: groupExpansion
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search sessions…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .onChange(of: searchText) { _, newValue in
                    scheduleSearchDebounce(to: newValue)
                }
                .onAppear {
                    debouncedSearchText = searchText
                }

            if configStore.sessionsLoadInProgress {
                ProgressView("Loading sessions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedItemID) {
                    ForEach(displayRows) { row in
                        SessionSidebarFlatRowView(
                            row: row,
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
                            onSaveTabsAsGroup: { showSaveGroupSheet = true },
                            onTestConnection: testConnection,
                            onDuplicateToFolder: duplicateSessionToFolder,
                            onBrowseSFTP: { sftpBrowseProfile = $0 },
                            onUpdateGroupLayout: updateGroupLayout,
                            onCreateEmptyGroup: {
                                let group = appState.createEmptyGroup()
                                selectedItemID = group.id
                                renamingGroup = group
                            }
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
        }
        .alert("Connection Test", isPresented: Binding(
            get: { connectionTestMessage != nil },
            set: { if !$0 { connectionTestMessage = nil } }
        )) {
            Button("OK", role: .cancel) { connectionTestMessage = nil }
        } message: {
            Text(connectionTestMessage ?? "")
        }
        .sheet(item: $sftpBrowseProfile) { profile in
            SFTPBrowserView(profile: profile)
        }
        .contextMenu {
            sidebarBackgroundContextMenu()
        }
        .navigationTitle("Sessions")
        .onAppear {
            configStore.loadSessionsIfNeeded()
            appState.sessionTreeSelectionID = selectedItemID
        }
        .onChange(of: selectedItemID) { _, itemID in
            appState.sessionTreeSelectionID = itemID
        }
        .onChange(of: appState.pendingSessionTreeAction) { _, action in
            handleSessionTreeAction(action)
        }
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
                    !configStore.sessionNameExists(candidate, excludingSessionID: profile.id)
                }
            ) { saved in
                _ = appState.updateSessionProfile(saved)
            }
        }
        .sheet(item: $renamingFolder) { folder in
            FolderNameEditorView(
                name: folder.name,
                isNameAvailable: { candidate in
                    !configStore.folderNameExists(candidate, excludingID: folder.id)
                }
            ) { newName in
                _ = configStore.renameFolder(id: folder.id, name: newName)
            }
        }
        .sheet(item: $renamingGroup) { group in
            FolderNameEditorView(
                name: group.name,
                fieldLabel: "Group Name",
                navigationTitle: "Rename Group",
                duplicateMessage: "A group with this name already exists.",
                isNameAvailable: { candidate in
                    !configStore.groupNameExists(candidate, excludingID: group.id)
                }
            ) { newName in
                _ = configStore.renameGroup(id: group.id, name: newName)
            }
        }
        .sheet(isPresented: $showSaveGroupSheet) {
            FolderNameEditorView(
                name: "New Group",
                fieldLabel: "Group Name",
                navigationTitle: "Save Tab Group",
                duplicateMessage: "A group with this name already exists.",
                isNameAvailable: { candidate in
                    !configStore.groupNameExists(candidate)
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
        return ConfigStore.findSessionProfile(id: selectedItemID, in: configStore.sessionTree)
    }

    private var selectedGroup: SessionGroup? {
        guard let selectedItemID,
              let item = configStore.item(withID: selectedItemID),
              case .group(let group) = item else {
            return nil
        }
        return group
    }

    private func beginEditingSelection() {
        guard let selectedItemID,
              let item = configStore.item(withID: selectedItemID) else { return }
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
        if let item = configStore.item(withID: selectedItemID) {
            itemPendingDeletion = item
            return
        }
        if let (groupID, member) = ConfigStore.findGroupMember(
            id: selectedItemID,
            in: configStore.sessionTree
        ) {
            deleteGroupMember(groupID: groupID, memberID: member.id)
        }
    }

    private func deleteGroupMember(groupID: UUID, memberID: UUID) {
        _ = configStore.removeMemberFromGroup(groupID: groupID, memberID: memberID)
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
               in: configStore.sessionTree
           ) {
            if let profile = ConfigStore.findSessionProfile(
                id: member.sessionID,
                in: configStore.sessionTree
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
        let folder = configStore.addFolder("New Folder")
        selectedItemID = folder.id
        renamingFolder = folder
    }

    private func handleSessionTreeAction(_ action: SessionTreeAction?) {
        guard let action else { return }
        defer { appState.consumeSessionTreeAction() }

        switch action {
        case .createFolder:
            createFolder()
        case .renameFolder:
            guard let folder = appState.selectedSessionTreeFolder else { return }
            renamingFolder = folder
        case .deleteFolder:
            guard let folder = appState.selectedSessionTreeFolder else { return }
            itemPendingDeletion = .folder(folder)
        case .addNewSession:
            createSession(in: appState.folderIDForNewSession())
        case .createGroupFromOpenTabs:
            showSaveGroupSheet = true
        }
    }

    private func createSession(in folderID: UUID? = nil) {
        if let folderID {
            expandFolderPath(to: folderID)
        }
        let profile = SessionProfile(name: "New Session", host: "example.com", username: "user")
        let saved = configStore.addSession(profile, to: folderID)
        editingSession = saved
    }

    private func expandFolderPath(to folderID: UUID) {
        var current: UUID? = folderID
        while let id = current {
            expandedFolderIDs.insert(id)
            current = ConfigStore.parentFolderID(of: id, in: configStore.sessionTree)
        }
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
        guard let saved = configStore.duplicateGroup(id: group.id) else { return }
        selectedItemID = saved.id
    }

    private func duplicateSession(_ profile: SessionProfile) {
        guard let saved = configStore.duplicateSession(id: profile.id) else { return }
        if saved.sshAuthMethod == .password, !saved.password.isEmpty {
            _ = SSHAuthHelper.writeAskpassScript(password: saved.password, profileID: saved.id)
        }
        selectedItemID = saved.id
        editingSession = saved
    }

    private func handleRootDrop(_ items: [String]) -> Bool {
        guard let draggedID = items.compactMap({ UUID(uuidString: $0) }).first else { return false }
        return configStore.moveItem(withID: draggedID, toParentFolderID: nil, beforeItemID: nil)
    }

    @ViewBuilder
    private func sidebarBackgroundContextMenu() -> some View {
        Button("New Folder") { createFolder() }
        Button("New Session") { createSession() }
        Button("New Empty Group") {
            let group = appState.createEmptyGroup()
            selectedItemID = group.id
            renamingGroup = group
        }
        if let group = selectedGroup {
            Button("Duplicate Group") { duplicateGroup(group) }
            Button("Update Group Layout") { updateGroupLayout(group) }
        }
        if !appState.tabs.isEmpty {
            Divider()
            Button("Save Tabs as Group…") { showSaveGroupSheet = true }
        }
    }

    private func testConnection(for profile: SessionProfile) {
        Task {
            let result = await appState.testConnection(for: profile)
            switch result {
            case .success:
                connectionTestMessage = "Connection to \(profile.host) succeeded."
            case .failure(let message):
                connectionTestMessage = message
            }
        }
    }

    private func duplicateSessionToFolder(_ profile: SessionProfile) {
        let folderID = appState.folderIDForNewSession()
            ?? ConfigStore.parentFolderID(of: profile.id, in: configStore.sessionTree)
        guard let folderID,
              let saved = appState.duplicateSessionToFolder(sessionID: profile.id, folderID: folderID) else {
            return
        }
        selectedItemID = saved.id
    }

    private func updateGroupLayout(_ group: SessionGroup) {
        if appState.updateGroupLayout(for: group.id) {
            connectionTestMessage = "Updated layout for group \"\(group.name)\"."
        }
    }

    private func scheduleSearchDebounce(to value: String) {
        searchDebounceTask?.cancel()
        let delayMs = appState.settings.sidebarSearchDebounceMs
        if delayMs <= 0 {
            debouncedSearchText = value
            return
        }
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled else { return }
            debouncedSearchText = value
        }
    }
}

private struct SessionTreeRowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var configStore: ConfigStore

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
    let onTestConnection: (SessionProfile) -> Void
    let onDuplicateToFolder: (SessionProfile) -> Void
    let onBrowseSFTP: (SessionProfile) -> Void
    let onUpdateGroupLayout: (SessionGroup) -> Void
    let onCreateEmptyGroup: () -> Void

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
                            onSaveTabsAsGroup: onSaveTabsAsGroup,
                            onTestConnection: onTestConnection,
                            onDuplicateToFolder: onDuplicateToFolder,
                            onBrowseSFTP: onBrowseSFTP,
                            onUpdateGroupLayout: onUpdateGroupLayout,
                            onCreateEmptyGroup: onCreateEmptyGroup
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
                                _ = configStore.removeMemberFromGroup(groupID: groupID, memberID: memberID)
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
            HStack(spacing: 6) {
                if let tagColor = TagColorHelper.color(from: profile.tagColor) {
                    Circle()
                        .fill(tagColor)
                        .frame(width: 8, height: 8)
                }
                Label(profile.name, systemImage: SessionLookup.icon(for: profile.protocolType))
                Spacer()
                if profile.sftpEnabled {
                    Button {
                        onBrowseSFTP(profile)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .appHelp("Browse remote files via SFTP")

                    Button {
                        appState.launchSFTP(for: profile)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                    .appHelp("Open SFTP in an embedded tab")
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

struct GroupMemberRowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var configStore: ConfigStore

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
        ConfigStore.findSessionProfile(id: member.sessionID, in: configStore.sessionTree)
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

enum TagColorHelper {
    static func color(from value: String?) -> Color? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("#"), value.count >= 7 {
            let hex = String(value.dropFirst())
            if let rgb = Int(hex.prefix(6), radix: 16) {
                let red = Double((rgb >> 16) & 0xFF) / 255
                let green = Double((rgb >> 8) & 0xFF) / 255
                let blue = Double(rgb & 0xFF) / 255
                return Color(red: red, green: green, blue: blue)
            }
        }
        switch value.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        default: return nil
        }
    }
}

enum SessionLookup {
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

extension View {
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
