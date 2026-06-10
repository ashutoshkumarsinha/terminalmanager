import SwiftUI

struct UserGuideView: View {
    @State private var markdown = UserGuideLoader.loadMarkdown()

    var body: some View {
        ScrollView {
            Group {
                if let attributed = try? AttributedString(
                    markdown: markdown,
                    options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
                ) {
                    Text(attributed)
                } else {
                    Text(markdown)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("User Guide")
        .frame(minWidth: 640, minHeight: 480)
    }
}
