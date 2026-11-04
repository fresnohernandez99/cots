import CotsCore
import SwiftUI

/// A small block-level Markdown renderer. SwiftUI's `Text(markdown)` only handles
/// inline syntax, and we need task items to be clickable and to know their source line.
struct MarkdownView: View {
    let text: String
    var onToggleTask: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        // Links in a note can't open files or apps, only web pages and mail.
        .environment(\.openURL, OpenURLAction { url in
            ActionPolicy.isWebURL(url.absoluteString) ? .systemAction : .discarded
        })
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Text(inline(text))
        case .bullet(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(text))
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .numbered(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary).monospacedDigit()
                Text(inline(text))
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .task(let indent, let checked, let text, let line):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button {
                    onToggleTask?(line)
                } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(onToggleTask == nil)
                Text(inline(text))
                    .strikethrough(checked)
                    .foregroundStyle(checked ? .secondary : .primary)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .quote(let text):
            Text(inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(.callout, design: .monospaced)).padding(10)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        case .rule:
            Divider()
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

enum MarkdownBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case bullet(Int, String)
    case numbered(Int, String, String)
    /// `line` is the index of the source line, so toggling can rewrite it.
    case task(Int, Bool, String, line: Int)
    case quote(String)
    case code(String)
    case rule

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }

        for (i, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil { code?.append(raw); continue }

            let indent = (raw.prefix { $0 == " " || $0 == "\t" }.count) / 2
            if trimmed.isEmpty { flush(); continue }
            if let level = headingLevel(trimmed) {
                flush()
                blocks.append(.heading(level, String(trimmed.dropFirst(level + 1))))
            } else if ["---", "***", "___"].contains(trimmed) {
                flush()
                blocks.append(.rule)
            } else if let (checked, rest) = task(trimmed) {
                flush()
                blocks.append(.task(indent, checked, rest, line: i))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flush()
                blocks.append(.bullet(indent, String(trimmed.dropFirst(2))))
            } else if let (marker, rest) = numbered(trimmed) {
                flush()
                blocks.append(.numbered(indent, marker, rest))
            } else if trimmed.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(trimmed)
            }
        }
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func task(_ line: String) -> (Bool, String)? {
        for prefix in ["- [ ] ", "* [ ] ", "- [x] ", "- [X] ", "* [x] ", "* [X] "] where line.hasPrefix(prefix) {
            return (!prefix.contains("[ ]"), String(line.dropFirst(prefix.count)))
        }
        return nil
    }

    private static func numbered(_ line: String) -> (String, String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return (digits + ".", String(line.dropFirst(digits.count + 2)))
    }
}

/// Splits a `log` body into `## <timestamp>` entries, newest first.
struct LogEntry: Identifiable {
    let id: Int
    let heading: String
    let text: String
    /// Line offset of `text` inside the full body, so task toggles map back.
    let lineOffset: Int

    static func parse(_ body: String) -> (preamble: String, entries: [LogEntry]) {
        let lines = body.components(separatedBy: "\n")
        var preamble: [String] = []
        var entries: [LogEntry] = []
        var current: (heading: String, start: Int, lines: [String])?

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("## ") {
                if let c = current {
                    entries.append(LogEntry(id: entries.count, heading: c.heading,
                                            text: c.lines.joined(separator: "\n"), lineOffset: c.start))
                }
                current = (String(line.dropFirst(3)), i + 1, [])
            } else if current != nil {
                current?.lines.append(line)
            } else {
                preamble.append(line)
            }
        }
        if let c = current {
            entries.append(LogEntry(id: entries.count, heading: c.heading, text: c.lines.joined(separator: "\n"), lineOffset: c.start))
        }
        return (preamble.joined(separator: "\n"), entries.reversed())
    }
}
