import Foundation

struct AIAnswerBlock: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case paragraph
        case heading(Int)
        case listItem(marker: String, depth: Int)
        case quote
        case code(language: String)
        case divider
        case table
    }

    let id: Int
    let kind: Kind
    let text: String
    var rows: [[String]] = []
}

/// Parse presentation blocks without flattening Markdown paragraph boundaries.
/// The original message remains the source for copying and server history.
struct AIAnswerDocument: Equatable, Sendable {
    let blocks: [AIAnswerBlock]

    init(_ content: String) {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [AIAnswerBlock] = []
        var paragraph: [String] = []
        var index = 0

        func append(_ kind: AIAnswerBlock.Kind, text: String = "", rows: [[String]] = []) {
            blocks.append(AIAnswerBlock(id: blocks.count, kind: kind, text: text, rows: rows))
        }
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            append(.paragraph, text: paragraph.joined(separator: "\n"))
            paragraph.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flushParagraph(); index += 1; continue }

            if let fence = Self.fence(trimmed) {
                flushParagraph()
                let language = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.count >= fence.count, candidate.allSatisfy({ $0 == fence.marker }) {
                        index += 1
                        break
                    }
                    code.append(lines[index])
                    index += 1
                }
                append(.code(language: language), text: code.joined(separator: "\n"))
                continue
            }

            if let heading = Self.heading(trimmed) {
                flushParagraph()
                append(.heading(heading.level), text: heading.text)
                index += 1
                continue
            }

            if index + 1 < lines.count, let level = Self.setextLevel(lines[index + 1]),
               !trimmed.hasPrefix(">"), Self.listItem(line) == nil {
                flushParagraph()
                append(.heading(level), text: trimmed)
                index += 2
                continue
            }

            if Self.isDivider(trimmed) {
                flushParagraph()
                append(.divider)
                index += 1
                continue
            }

            if let header = Self.tableCells(trimmed), index + 1 < lines.count,
               Self.isTableSeparator(lines[index + 1], columns: header.count) {
                flushParagraph()
                var rows = [header]
                index += 2
                while index < lines.count, let cells = Self.tableCells(lines[index]),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells)
                    index += 1
                }
                append(.table, rows: rows)
                continue
            }

            if let item = Self.listItem(line) {
                flushParagraph()
                var text = [item.text]
                index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !next.isEmpty, !Self.startsBlock(lines[index]) else { break }
                    if index + 1 < lines.count,
                       Self.setextLevel(lines[index + 1]) != nil || Self.isTableSeparator(lines[index + 1]) { break }
                    text.append(next)
                    index += 1
                }
                append(.listItem(marker: item.marker, depth: item.depth), text: text.joined(separator: "\n"))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix(">") else { break }
                    quote.append(String(next.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                append(.quote, text: quote.joined(separator: "\n"))
                continue
            }

            paragraph.append(line)
            index += 1
        }
        flushParagraph()
        self.blocks = blocks
    }

    /// A numeric range is plain text, not the start of a strikethrough span.
    /// Do not rewrite inline code or explicit Markdown ~~strikethrough~~.
    static func inlineSource(_ content: String) -> String {
        let characters = Array(content)
        var result = ""
        var codeDelimiter = 0
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "`" {
                var end = index + 1
                while end < characters.count, characters[end] == "`" { end += 1 }
                let count = end - index
                if codeDelimiter == 0 { codeDelimiter = count }
                else if codeDelimiter == count { codeDelimiter = 0 }
                result += String(repeating: "`", count: count)
                index = end
                continue
            }
            if character == "~", codeDelimiter == 0, index > 0, characters[index - 1] != "\\" {
                var before = index - 1
                var after = index + 1
                while before > 0, characters[before].isWhitespace { before -= 1 }
                while after < characters.count, characters[after].isWhitespace { after += 1 }
                if characters[before].isNumber, after < characters.count, characters[after].isNumber {
                    result.append("\\")
                }
            }
            result.append(character)
            index += 1
        }
        return result
    }

    private static func fence(_ line: String) -> (marker: Character, count: Int)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix(while: { $0 == first }).count
        return count >= 3 ? (first, count) : nil
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        if (1...6).contains(hashes) {
            let rest = line.dropFirst(hashes)
            if rest.first?.isWhitespace == true {
                let title = rest.trimmingCharacters(in: .whitespaces)
                return (hashes, title.replacingOccurrences(of: "[ \\t]+#+$", with: "", options: .regularExpression))
            }
        }
        if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4, line.count <= 100 {
            let title = String(line.dropFirst(2).dropLast(2))
            if !title.contains("**") { return (3, title) }
        }
        if line.count <= 60,
           line.range(of: "^[一二三四五六七八九十百]+[、．.][^。！？；]+$", options: .regularExpression) != nil {
            return (2, line)
        }
        return nil
    }

    private static func setextLevel(_ line: String) -> Int? {
        let value = line.trimmingCharacters(in: .whitespaces)
        guard value.count >= 3 else { return nil }
        if value.allSatisfy({ $0 == "=" }) { return 1 }
        if value.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static let listPattern = try! NSRegularExpression(pattern: "^([ \\t]*)(?:([-+*•])|([0-9]{1,5})[.)、])[ \\t]+(.+)$")

    private static func listItem(_ line: String) -> (marker: String, depth: Int, text: String)? {
        guard let match = listPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let indentRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 4), in: line) else { return nil }
        let indent = line[indentRange].reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let marker: String
        if let range = Range(match.range(at: 3), in: line) { marker = String(line[range]) + "." }
        else { marker = "•" }
        return (marker, min(6, indent / 2), String(line[textRange]))
    }

    private static func startsBlock(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespaces)
        return fence(value) != nil || heading(value) != nil || isDivider(value)
            || listItem(line) != nil || value.hasPrefix(">")
    }

    private static func tableCells(_ line: String) -> [String]? {
        let value = line.trimmingCharacters(in: .whitespaces)
        var cells: [String] = []
        var cell = ""
        var escaped = false
        var codeDelimiter = 0
        let characters = Array(value)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if escaped {
                if character != "|" { cell.append("\\") }
                cell.append(character)
                escaped = false
            } else if character == "\\" { escaped = true }
            else if character == "`" {
                var end = index + 1
                while end < characters.count, characters[end] == "`" { end += 1 }
                let count = end - index
                if codeDelimiter == 0 { codeDelimiter = count }
                else if codeDelimiter == count { codeDelimiter = 0 }
                cell += String(repeating: "`", count: count)
                index = end
                continue
            } else if character == "|", codeDelimiter == 0 {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else { cell.append(character) }
            index += 1
        }
        if escaped { cell.append("\\") }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        guard cells.count > 1 else { return nil }
        if value.hasPrefix("|"), cells.first == "" { cells.removeFirst() }
        if value.hasSuffix("|"), cells.last == "" { cells.removeLast() }
        return cells.isEmpty ? nil : cells
    }

    private static func isTableSeparator(_ line: String, columns: Int? = nil) -> Bool {
        guard let cells = tableCells(line), columns == nil || cells.count == columns else { return false }
        return cells.allSatisfy { cell in
            let value = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return value.count >= 3 && value.allSatisfy { $0 == "-" }
        }
    }
}
