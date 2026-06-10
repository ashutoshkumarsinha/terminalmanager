import Foundation

enum MarkdownHTMLConverter {
    static func htmlDocument(from markdown: String, title: String = "User Guide") -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light dark">
          <title>\(escapeHTML(title))</title>
          <style>
            :root { color-scheme: light dark; }
            body {
              font: 13px/1.55 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
              margin: 0;
              padding: 28px 36px 40px;
              max-width: 780px;
            }
            h1 { font-size: 1.75rem; font-weight: 700; margin: 0 0 0.75rem; }
            h2 {
              font-size: 1.25rem;
              font-weight: 650;
              margin: 1.75rem 0 0.75rem;
              padding-bottom: 0.25rem;
              border-bottom: 1px solid rgba(127, 127, 127, 0.35);
            }
            h3 { font-size: 1.05rem; font-weight: 650; margin: 1.25rem 0 0.5rem; }
            p { margin: 0.65rem 0; }
            hr { border: none; border-top: 1px solid rgba(127, 127, 127, 0.35); margin: 1.5rem 0; }
            ul, ol { margin: 0.5rem 0 0.75rem; padding-left: 1.35rem; }
            li { margin: 0.3rem 0; }
            pre {
              background: rgba(127, 127, 127, 0.12);
              border-radius: 8px;
              padding: 12px 14px;
              overflow-x: auto;
              font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
              white-space: pre;
              margin: 0.75rem 0;
            }
            code {
              font: 0.92em ui-monospace, SFMono-Regular, Menlo, monospace;
              background: rgba(127, 127, 127, 0.12);
              padding: 0.12em 0.35em;
              border-radius: 4px;
            }
            pre code { background: none; padding: 0; font-size: inherit; }
            table {
              width: 100%;
              border-collapse: collapse;
              margin: 0.85rem 0 1rem;
              font-size: 0.96em;
            }
            th, td {
              border: 1px solid rgba(127, 127, 127, 0.35);
              padding: 8px 10px;
              text-align: left;
              vertical-align: top;
            }
            th { background: rgba(127, 127, 127, 0.1); font-weight: 600; }
            a { color: #007aff; text-decoration: none; }
            a:hover { text-decoration: underline; }
            strong { font-weight: 650; }
          </style>
        </head>
        <body>
        \(convert(markdown))
        </body>
        </html>
        """
    }

    static func convert(_ markdown: String) -> String {
        var html = ""
        var index = markdown.startIndex
        var inCodeBlock = false
        var codeLines: [String] = []
        var tableLines: [String] = []
        var listLines: [(ordered: Bool, text: String)] = []

        func flushTable() {
            guard !tableLines.isEmpty else { return }
            html += renderTable(tableLines)
            tableLines.removeAll()
        }

        func flushList() {
            guard !listLines.isEmpty else { return }
            let ordered = listLines[0].ordered
            html += ordered ? "<ol>\n" : "<ul>\n"
            for item in listLines {
                html += "<li>\(inline(item.text))</li>\n"
            }
            html += ordered ? "</ol>\n" : "</ul>\n"
            listLines.removeAll()
        }

        while index < markdown.endIndex {
            let lineEnd = markdown[index...].firstIndex(of: "\n") ?? markdown.endIndex
            let line = String(markdown[index..<lineEnd])
            let nextIndex = lineEnd == markdown.endIndex ? markdown.endIndex : markdown.index(after: lineEnd)

            if line.hasPrefix("```") {
                flushList()
                flushTable()
                if inCodeBlock {
                    html += "<pre><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>\n"
                    codeLines.removeAll()
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                index = nextIndex
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                index = nextIndex
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushList()
                flushTable()
                index = nextIndex
                continue
            }

            if isTableRow(trimmed) {
                flushList()
                tableLines.append(trimmed)
                index = nextIndex
                continue
            }

            flushTable()

            if let listItem = parseListItem(trimmed) {
                if let last = listLines.last, last.ordered != listItem.ordered {
                    flushList()
                }
                listLines.append(listItem)
                index = nextIndex
                continue
            }

            flushList()

            if trimmed == "---" {
                html += "<hr>\n"
            } else if trimmed.hasPrefix("### ") {
                html += "<h3>\(inline(String(trimmed.dropFirst(4))))</h3>\n"
            } else if trimmed.hasPrefix("## ") {
                html += "<h2>\(inline(String(trimmed.dropFirst(3))))</h2>\n"
            } else if trimmed.hasPrefix("# ") {
                html += "<h1>\(inline(String(trimmed.dropFirst(2))))</h1>\n"
            } else {
                html += "<p>\(inline(trimmed))</p>\n"
            }

            index = nextIndex
        }

        flushList()
        flushTable()
        if inCodeBlock, !codeLines.isEmpty {
            html += "<pre><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>\n"
        }

        return html
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        line.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)
            .isEmpty
    }

    private static func renderTable(_ lines: [String]) -> String {
        let rows = lines.filter { !isTableSeparator($0) }
        guard let header = rows.first else { return "" }

        var html = "<table><thead><tr>"
        for cell in splitTableCells(header) {
            html += "<th>\(inline(cell))</th>"
        }
        html += "</tr></thead><tbody>\n"

        for row in rows.dropFirst() {
            html += "<tr>"
            for cell in splitTableCells(row) {
                html += "<td>\(inline(cell))</td>"
            }
            html += "</tr>\n"
        }

        html += "</tbody></table>\n"
        return html
    }

    private static func splitTableCells(_ row: String) -> [String] {
        row.split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseListItem(_ line: String) -> (ordered: Bool, text: String)? {
        if line.hasPrefix("- ") {
            return (false, String(line.dropFirst(2)))
        }
        if let dotIndex = line.firstIndex(of: "."),
           line.index(after: dotIndex) < line.endIndex,
           line[line.index(after: dotIndex)] == " ",
           line[..<dotIndex].allSatisfy(\.isNumber) {
            let textStart = line.index(dotIndex, offsetBy: 2)
            return (true, String(line[textStart...]))
        }
        return nil
    }

    private static func inline(_ text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            let tail = text[index...]

            if tail.hasPrefix("**") {
                let innerStart = text.index(index, offsetBy: 2)
                if let endRange = text[innerStart...].range(of: "**") {
                    let inner = String(text[innerStart..<endRange.lowerBound])
                    output += "<strong>\(inline(inner))</strong>"
                    index = endRange.upperBound
                    continue
                }
            }

            if text[index] == "`",
               let end = text[text.index(after: index)...].firstIndex(of: "`") {
                let start = text.index(after: index)
                output += "<code>\(escapeHTML(String(text[start..<end])))</code>"
                index = text.index(after: end)
                continue
            }

            if text[index] == "[",
               let closeBracket = tail.firstIndex(of: "]"),
               text.index(after: closeBracket) < text.endIndex,
               text[text.index(after: closeBracket)] == "(",
               let closeParen = text[text.index(after: closeBracket)...].firstIndex(of: ")") {
                let labelStart = text.index(after: index)
                let label = String(text[labelStart..<closeBracket])
                let urlStart = text.index(closeBracket, offsetBy: 2)
                let url = String(text[urlStart..<closeParen])
                output += "<a href=\"\(escapeHTML(url))\">\(inline(label))</a>"
                index = text.index(after: closeParen)
                continue
            }

            output += escapeHTML(String(text[index]))
            index = text.index(after: index)
        }

        return output
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
