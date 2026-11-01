import Foundation
import CoreFoundation
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
    let values: Any
}

/// Readable server responses without exposing raw JSON or credentials.
struct ManagementResultView: View {
    @Environment(\.dismiss) private var dismiss
    let result: ManagementResult

    var body: some View {
        NavigationStack {
            List {
                let rows = managementRows(result.values)
                if !rows.isEmpty {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Section {
                            resultFields(row)
                        }
                    }
                } else if let root = managementPayload(result.values) as? [String: Any] {
                    if root.isEmpty { Label("操作已完成", systemImage: "checkmark.circle") }
                    else { resultFields(root) }
                } else if managementPayload(result.values) is [Any] {
                    ContentUnavailableView("暂无匹配结果", systemImage: "doc.text.magnifyingglass")
                } else {
                    Text(String(describing: managementPayload(result.values))).textSelection(.enabled)
                }
            }
            .navigationTitle(result.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private func resultFields(_ row: [String: Any]) -> some View {
        ForEach(row.keys.sorted(), id: \.self) { key in
            if !["api_key", "password", "token", "rss", "torrent_url"].contains(key) {
                if let text = row[key] as? String, !text.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(managementFieldLabel(key)).font(.caption).foregroundStyle(.secondary)
                        Text(text).font(.subheadline).textSelection(.enabled)
                    }
                } else if let number = row[key] as? NSNumber {
                    let isBoolean = CFGetTypeID(number) == CFBooleanGetTypeID()
                    LabeledContent(managementFieldLabel(key), value: isBoolean ? (number.boolValue ? "是" : "否") : number.stringValue)
                } else if let nested = row[key] as? [String: Any] {
                    NavigationLink(managementFieldLabel(key)) {
                        ManagementResultView(result: ManagementResult(title: managementFieldLabel(key), values: nested))
                    }
                } else if let list = row[key] as? [[String: Any]], !list.isEmpty {
                    NavigationLink("\(managementFieldLabel(key)) · \(list.count) 项") {
                        ManagementResultView(result: ManagementResult(title: managementFieldLabel(key), values: list))
                    }
                }
            }
        }
    }
}

func managementFieldLabel(_ key: String) -> String {
    let labels = [
        "name": "名称", "title": "标题", "text": "内容", "message": "返回信息", "msg": "返回信息",
        "model": "模型", "prompt_tokens": "输入 Token", "completion_tokens": "输出 Token",
        "total": "总数", "created": "新增", "updated": "更新", "item_count": "条目数",
        "last_build": "最后构建", "feed_name": "RSS 源", "feed_id": "源编号",
        "subscription_id": "订阅编号", "pushed": "已推送", "published_at": "发布时间",
        "created_at": "创建时间", "status": "状态", "context": "项目状态", "findings": "诊断结果",
        "sites_total": "站点总数", "sites_enabled": "启用站点", "downloaders_total": "下载器总数",
        "downloaders_active": "活跃下载器", "schedule_tasks": "计划任务", "rss_feeds": "RSS 源",
        "rss_subscriptions": "RSS 订阅", "recent_results": "近期执行记录", "level": "级别",
        "code": "代码", "day": "日期", "daily_limit": "每日额度", "size": "大小（字节）",
        "link": "详情链接", "category": "分类", "summary": "摘要", "date": "日期",
        "author": "作者", "description": "描述", "isRead": "已读"
    ]
    return labels[key] ?? key
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
