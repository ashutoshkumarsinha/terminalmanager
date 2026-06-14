import Foundation

enum SessionNotesHelper {
    private static func account(for profileID: UUID) -> String {
        "notes-\(profileID.uuidString)"
    }

    static func resolvedNotes(for profile: SessionProfile) -> String {
        if profile.notesInKeychain {
            return KeychainSecretStore.load(account: account(for: profile.id)) ?? ""
        }
        return profile.notes
    }

    static func storeNotes(_ notes: String, for profileID: UUID) throws {
        try KeychainSecretStore.store(secret: notes, account: account(for: profileID))
    }

    static func deleteNotes(for profileID: UUID) throws {
        try KeychainSecretStore.delete(account: account(for: profileID))
    }

    @discardableResult
    static func migrateNotesToKeychain(for profile: inout SessionProfile) -> Bool {
        guard !profile.notesInKeychain, !profile.notes.isEmpty else { return false }
        do {
            try storeNotes(profile.notes, for: profile.id)
            profile.notes = ""
            profile.notesInKeychain = true
            return true
        } catch {
            AppLogger.shared.error("Failed to migrate notes to Keychain: \(error)")
            return false
        }
    }
}
