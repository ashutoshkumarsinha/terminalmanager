import SwiftUI
import WebKit

struct UserGuideView: View {
    private let html = MarkdownHTMLConverter.htmlDocument(
        from: UserGuideLoader.loadMarkdown(),
        title: "Terminal Manager User Guide"
    )
    private let baseURL = UserGuideLoader.markdownURL()?.deletingLastPathComponent()

    var body: some View {
        UserGuideWebView(html: html, baseURL: baseURL)
            .frame(minWidth: 640, minHeight: 480)
    }
}

private struct UserGuideWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard !context.coordinator.didLoad else { return }
        context.coordinator.didLoad = true
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var didLoad = false
    }
}
