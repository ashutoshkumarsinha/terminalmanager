import SwiftUI

/// In-app update prompt when a newer GitHub release is detected (EN-07 lite; Sparkle optional later).
struct UpdateAvailableAlertModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content
            .alert(
                "Update Available",
                isPresented: Binding(
                    get: { appState.showUpdatePrompt },
                    set: { if !$0 { appState.dismissUpdatePrompt() } }
                )
            ) {
                Button("Download") {
                    appState.openPendingUpdate()
                }
                Button("Later", role: .cancel) {
                    appState.dismissUpdatePrompt()
                }
            } message: {
                if let update = appState.pendingUpdate {
                    if let notes = update.releaseNotes, !notes.isEmpty {
                        Text("Version \(update.version) is available.\n\n\(notes)")
                    } else {
                        Text("Version \(update.version) is available on GitHub.")
                    }
                }
            }
    }
}

extension View {
    func updateAvailableAlert() -> some View {
        modifier(UpdateAvailableAlertModifier())
    }
}
