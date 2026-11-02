import SwiftUI

/// Native block layout keeps headings, lists and code readable on narrow screens.
struct AIAnswerView: View {
    @Environment(\.colorScheme) private var colorScheme
    let document: AIAnswerDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(document.blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .tint(accent(.blue))
    }

    @ViewBuilder private func blockView(_ block: AIAnswerBlock) -> some View {
        switch block.kind {
        case .paragraph:
            inlineText(block.text)
                .font(.subheadline)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level):
            inlineText(block.text, highlightsStrong: false)
                .font(headingFont(level))
                .foregroundStyle(headingColor(level))
                .lineSpacing(3)
                .padding(.top, block.id == 0 ? 0 : 5)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .listItem(let marker, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(marker == "•" ? accent(.teal) : accent(.blue))
                    .frame(minWidth: marker == "•" ? 12 : 22, alignment: .leading)
                inlineText(block.text)
                    .font(.subheadline)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(min(depth, 4)) * 12)
        case .quote:
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(emphasisColor(block.text).opacity(0.60))
                    .frame(width: 2)
                inlineText(block.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(9)
            .background(emphasisColor(block.text).opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
        case .code(let language):
            codeBlock(block.text, language: language)
        case .divider:
            Divider().padding(.vertical, 2)
        case .table:
            table(block.rows)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.bold)
        case 2: .headline.weight(.bold)
        default: .subheadline.weight(.semibold)
        }
    }

    private func headingColor(_ level: Int) -> Color {
        switch level {
        case 1: accent(.blue)
        case 2: accent(.purple)
        default: accent(.teal)
        }
    }

    /// Only explicit lead-in labels receive semantic colors; ordinary prose
    /// stays in the normal text color and is not classified by keyword matches.
    private func emphasisColor(_ text: String) -> Color {
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*`> "))
        if ["高危", "紧急", "严重风险", "严重错误"].contains(where: label.hasPrefix) { return accent(.danger) }
        if ["注意", "警告", "风险", "提醒"].contains(where: label.hasPrefix) { return accent(.warning) }
        if ["建议", "优化建议", "推荐", "解决方案", "修复方案"].contains(where: label.hasPrefix) { return accent(.teal) }
        return accent(.blue)
    }

    private func inlineText(_ source: String, highlightsStrong: Bool = true) -> Text {
        let normalized = AIAnswerDocument.inlineSource(source)
        var value = (try? AttributedString(
            markdown: normalized,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
        if highlightsStrong {
            let emphasis = value.runs.filter { run in
                run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
                    && run.inlinePresentationIntent?.contains(.code) != true
                    && run.link == nil
            }.map { (range: $0.range, text: String(value[$0.range].characters)) }
            for item in emphasis {
                let color = emphasisColor(item.text)
                value[item.range].foregroundColor = color
                value[item.range].backgroundColor = color.opacity(0.055)
            }
        }
        let codeRanges = value.runs.compactMap { run in
            run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
        }
        for range in codeRanges {
            value[range].font = .system(.caption, design: .monospaced)
            value[range].foregroundColor = accent(.code)
            value[range].backgroundColor = accent(.code).opacity(0.07)
        }
        return Text(value)
    }

    private func codeBlock(_ code: String, language: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language.isEmpty ? "代码" : language)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button { copyPrivateText(code) } label: {
                    Label("复制代码", systemImage: "doc.on.doc").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .lineSpacing(3)
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(.bottom, 2)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.055), lineWidth: 0.5) }
    }

    private func table(_ rows: [[String]]) -> some View {
        let columnCount = rows.map(\.count).max() ?? 0
        return ScrollView(.horizontal) {
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            inlineText(column < rows[rowIndex].count ? rows[rowIndex][column] : "", highlightsStrong: rowIndex != 0)
                                .font(rowIndex == 0 ? .caption.weight(.semibold) : .caption)
                                .foregroundStyle(rowIndex == 0 ? accent(.purple) : Color.primary)
                                .lineSpacing(3)
                                .frame(width: 138, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 9)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(rowIndex == 0 ? accent(.purple).opacity(0.065) : Color.clear)
                    if rowIndex < rows.count - 1 { Divider() }
                }
            }
            .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("表格，可横向滑动")
    }

    private enum Accent {
        case blue, purple, teal, warning, danger, code
    }

    private func accent(_ kind: Accent) -> Color {
        let hex: UInt32
        switch kind {
        case .blue: hex = colorScheme == .dark ? 0x8AB9F2 : 0x245EA8
        case .purple: hex = colorScheme == .dark ? 0xBDA7EF : 0x6650A4
        case .teal: hex = colorScheme == .dark ? 0x7BCBB4 : 0x23725D
        case .warning: hex = colorScheme == .dark ? 0xE8BB68 : 0x8A580C
        case .danger: hex = colorScheme == .dark ? 0xFF9AA6 : 0xB42338
        case .code: hex = colorScheme == .dark ? 0xE9B48B : 0x87502F
        }
        return Color(red: Double((hex >> 16) & 0xFF) / 255,
                     green: Double((hex >> 8) & 0xFF) / 255,
                     blue: Double(hex & 0xFF) / 255)
    }
}
