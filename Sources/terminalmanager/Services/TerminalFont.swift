import AppKit

enum TerminalFont {
    private static let preferredFontNames = [
        "MesloLGS Nerd Font Mono",
        "MesloLGS NF",
        "MesloLGM Nerd Font Mono",
        "JetBrainsMono Nerd Font",
        "JetBrainsMonoNL Nerd Font",
        "Hack Nerd Font Mono",
        "FiraCode Nerd Font",
        "CaskaydiaCove Nerd Font Mono",
        "SF Mono",
        "Menlo",
    ]

    static func preferredMonospaceFont(size: CGFloat = NSFont.systemFontSize) -> NSFont {
        for name in preferredFontNames {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
