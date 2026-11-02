import Foundation
import SwiftUI
import UIKit

enum ManagementFeatureDefaults {
    static let aiKey = "features.ai.enabled"
    static let rssKey = "features.rss.enabled"
}

enum ManagementAPI {
    static let aiProviders = "/api/ai/providers"
    static let aiTest = "/api/ai/providers/test"
    static let aiChat = "/api/ai/assistant/chat"
    static let aiHistory = "/api/ai/assistant/history"
    static let aiHistoryDates = "/api/ai/assistant/history/dates"
    static let aiUsage = "/api/ai/usage"
    static let aiDiagnostics = "/api/ai/diagnostics/run"
    static let rssFeeds = "/api/option/rss/feeds"
    static let rssTags = "/api/option/rss/tags"
    static let rssPlans = "/api/option/rss/plans"
    static let rssSubscriptions = "/api/option/rss/subscriptions"
    static let rssHistory = "/api/option/rss/history"
    static let rssRun = "/api/option/rss/run"
    static let qbRSS = "/api/option/downloaders/rss"
}

/// Unwrap only transport envelopes; preserve domain dictionaries and empty lists.
func managementPayload(_ raw: Any) -> Any {
    guard let root = raw as? [String: Any] else { return raw }
    if let value = root["data"] { return value }
    if root["code"] != nil, let value = root["result"] { return value }
    return root
}

func managementRows(_ raw: Any) -> [[String: Any]] {
    let value = managementPayload(raw)
    if let rows = value as? [[String: Any]] { return rows }
    guard let root = value as? [String: Any] else { return [] }
    for key in ["items", "results", "rows", "records", "list"] {
        if let rows = root[key] as? [[String: Any]] { return rows }
    }
    return []
}

struct ManagementRecord: Identifiable {
    let id: Int
    let values: [String: Any]
    init(_ values: [String: Any]) {
        id = values.int("id") ?? 0
        self.values = values
    }
    var name: String { values.string("name", "title") ?? "未命名" }
}

struct ManagementResult: Identifiable {
    let id = UUID()
    let title: String
    let document: ManagementResultDocument

    init(title: String, values: Any) {
        self.title = title
        self.document = ManagementResultDocument(managementPayload(values))
    }
}

/// Readable server responses without exposing raw JSON or credentials.
struct ManagementResultView: View {
    @Environment(\.dismiss) private var dismiss
    let result: ManagementResult

    var body: some View {
        NavigationStack {
            List {
                if result.document.sections.isEmpty {
                    if result.document.isEmptyCollection {
                        ContentUnavailableView("暂无匹配结果", systemImage: "doc.text.magnifyingglass")
                    } else {
                        Label("操作已完成", systemImage: "checkmark.circle")
                    }
                } else {
                    ForEach(result.document.sections) { section in
                        Section {
                            ForEach(section.fields) { field in
                                resultField(field)
                            }
                        } header: {
                            if !section.titleKeys.isEmpty {
                                Text(section.titleKeys.map(managementFieldLabel).joined(separator: " · "))
                            }
                        }
                    }
                }
            }
            .navigationTitle(result.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private func resultField(_ field: ManagementResultField) -> some View {
        let value = ManagementResultLocalization.displayValue(field.value, for: field.key)
        Group {
            if value.count <= 40, !value.contains("\n") {
                LabeledContent(managementFieldLabel(field.key), value: value)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(managementFieldLabel(field.key)).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.subheadline).textSelection(.enabled)
                }
            }
        }
        .contextMenu {
            Button("复制内容", systemImage: "doc.on.doc") { copyPrivateText(value) }
            Button("复制原字段", systemImage: "textformat") { copyPrivateText(field.key + ": " + field.value) }
        }
    }
}

func managementFieldLabel(_ key: String) -> String {
    ManagementResultLocalization.fieldTitle(key)
}

enum ManagementFieldKind: Equatable {
    case text, secret, integer, decimal, toggle, strings
}

struct ManagementField: Identifiable {
    let key: String
    let label: String
    var kind: ManagementFieldKind = .text
    var defaultValue: Any = ""
    var required = false
    var id: String { key }
}

/// Shared native fields for schemas whose API stores lists, booleans and numbers.
struct ManagementFieldInput: View {
    let field: ManagementField
    @Binding var values: [String: Any]

    var body: some View {
        Group {
            switch field.kind {
            case .toggle:
                Toggle(field.label, isOn: Binding(
                    get: { values.bool(field.key) ?? (field.defaultValue as? Bool ?? false) },
                    set: { values[field.key] = $0 }
                ))
            case .secret:
                SecureField(field.label, text: textBinding)
                    .textContentType(.password)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.label).font(.caption).foregroundStyle(.secondary)
                    TextField(field.kind == .strings ? "多项用逗号分隔" : field.label, text: textBinding, axis: .vertical)
                        .keyboardType(keyboardType)
                }
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private var keyboardType: UIKeyboardType {
        switch field.kind {
        case .integer: .numbersAndPunctuation
        case .decimal: .decimalPad
        default: .default
        }
    }

    private var textBinding: Binding<String> {
        Binding(get: {
            if values[field.key] is [Any] { return values.strings(field.key).joined(separator: ", ") }
            return values.string(field.key) ?? String(describing: field.defaultValue)
        }, set: { values[field.key] = $0 })
    }
}

func managementFormPayload(_ values: [String: Any], fields: [ManagementField]) throws -> [String: Any] {
    var result: [String: Any] = [:]
    for field in fields {
        let text = (values.string(field.key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if field.required, text.isEmpty {
            throw APIError(statusCode: 0, message: "请填写\(field.label)")
        }
        switch field.kind {
        case .toggle:
            result[field.key] = values.bool(field.key) ?? (field.defaultValue as? Bool ?? false)
        case .integer:
            guard let number = Int(text) ?? (values[field.key] == nil ? field.defaultValue as? Int : nil) else {
                throw APIError(statusCode: 0, message: "\(field.label)请输入整数")
            }
            result[field.key] = number
        case .decimal:
            guard let number = Double(text) ?? (values[field.key] == nil ? field.defaultValue as? Double : nil), number.isFinite else {
                throw APIError(statusCode: 0, message: "\(field.label)请输入有效数字")
            }
            result[field.key] = number
        case .strings:
            if values[field.key] is [Any] { result[field.key] = values.strings(field.key) }
            else {
                result[field.key] = text.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
        case .secret:
            if !text.isEmpty { result[field.key] = text }
        case .text:
            result[field.key] = text
        }
    }
    return result
}
