import SwiftUI

private struct ShowTooltipsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var showTooltips: Bool {
        get { self[ShowTooltipsKey.self] }
        set { self[ShowTooltipsKey.self] = newValue }
    }
}

private struct AppHelpModifier: ViewModifier {
    @Environment(\.showTooltips) private var envShowTooltips
    let text: String
    var showTooltips: Bool?

    private var isEnabled: Bool {
        showTooltips ?? envShowTooltips
    }

    func body(content: Content) -> some View {
        if isEnabled {
            content.help(text)
        } else {
            content
        }
    }
}

extension View {
    func appHelp(_ text: String, showTooltips show: Bool? = nil) -> some View {
        modifier(AppHelpModifier(text: text, showTooltips: show))
    }
}
