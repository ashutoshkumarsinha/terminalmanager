import Combine
import Foundation

/// Sidebar session library state extracted from `AppState` (TE-02 / HLD §13.4).
@MainActor
final class SessionLibraryState: ObservableObject {
    @Published var selectionID: UUID?
    @Published var pendingAction: SessionTreeAction?
    @Published var searchText = ""
    @Published private(set) var debouncedSearchText = ""
    @Published var expandedFolderIDs: Set<UUID> = []
    @Published var expandedGroupIDs: Set<UUID> = []

    private var searchDebounceTask: Task<Void, Never>?

    var isSearching: Bool {
        !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func requestAction(_ action: SessionTreeAction) {
        pendingAction = action
    }

    func consumeAction() {
        pendingAction = nil
    }

    func folderIDForNewSession(using configStore: ConfigStore) -> UUID? {
        guard let selectionID,
              let item = configStore.item(withID: selectionID) else {
            return nil
        }
        switch item {
        case .folder(let folder):
            return folder.id
        case .session:
            return configStore.parentFolderID(of: selectionID)
        case .group:
            return nil
        }
    }

    func selectedFolder(using configStore: ConfigStore) -> SessionFolder? {
        guard let selectionID,
              let item = configStore.item(withID: selectionID),
              case .folder(let folder) = item else {
            return nil
        }
        return folder
    }

    func expandFolderPath(to folderID: UUID, using configStore: ConfigStore) {
        var current: UUID? = folderID
        while let id = current {
            expandedFolderIDs.insert(id)
            current = ConfigStore.parentFolderID(of: id, in: configStore.sessionTree)
        }
    }

    func scheduleSearchDebounce(to value: String, debounceMs: Int) {
        searchDebounceTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard debounceMs > 0 else {
            debouncedSearchText = value
            return
        }
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            debouncedSearchText = value
            if trimmed.isEmpty {
                debouncedSearchText = ""
            }
        }
    }

    func syncDebouncedSearchFromText() {
        debouncedSearchText = searchText
    }
}
