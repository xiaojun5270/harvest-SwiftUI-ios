import Foundation
import CoreFoundation

struct ManagementResultField: Identifiable, Equatable {
    let id: String
    let key: String
    let value: String
}

struct ManagementResultSection: Identifiable, Equatable {
    let id: String
    let titleKeys: [String]
    let fields: [ManagementResultField]
}

/// Resolve JSON into a flat, stable list before SwiftUI creates any views.
/// Nested result objects never recursively instantiate a result screen.
struct ManagementResultDocument: Equatable {
    let sections: [ManagementResultSection]
    let isEmptyCollection: Bool

    init(_ payload: Any) {
        var sections: [ManagementResultSection] = []
        Self.collect(payload, path: [], titles: [], into: &sections)
        self.sections = sections
        self.isEmptyCollection = (payload as? [Any])?.isEmpty == true
    }

    private static let hiddenKeys: Set<String> = ["api_key", "password", "token", "rss", "torrent_url"]
    private static let contextOrder = [
        "sites_total", "sites_enabled", "downloaders_total", "downloaders_active",
        "schedule_tasks", "rss_feeds", "rss_subscriptions", "recent_results"
    ]

    private static func collect(_ value: Any, path: [String], titles: [String],
                                into sections: inout [ManagementResultSection]) {
        if let dictionary = value as? [String: Any] {
            let keys = dictionary.keys.filter { !hiddenKeys.contains($0.lowercased()) }.sorted {
                let left = contextOrder.firstIndex(of: $0) ?? contextOrder.count
                let right = contextOrder.firstIndex(of: $1) ?? contextOrder.count
                return left == right ? $0 < $1 : left < right
            }
            let fields = keys.compactMap { key -> ManagementResultField? in
                guard let raw = dictionary[key], let text = scalar(raw) else { return nil }
                return ManagementResultField(id: identifier(path + [key]), key: key, value: text)
            }
            if !fields.isEmpty {
                sections.append(ManagementResultSection(id: identifier(path), titleKeys: titles, fields: fields))
            }
            for key in keys {
                guard let raw = dictionary[key], scalar(raw) == nil else { continue }
                collect(raw, path: path + [key], titles: titles + [key], into: &sections)
            }
        } else if let list = value as? [Any] {
            for (index, item) in list.enumerated() {
                collect(item, path: path + [String(index)], titles: titles + ["第 \(index + 1) 项"], into: &sections)
            }
        } else if let text = scalar(value) {
            let field = ManagementResultField(id: identifier(path), key: "text", value: text)
            sections.append(ManagementResultSection(id: identifier(path), titleKeys: titles, fields: [field]))
        }
    }

    private static func scalar(_ value: Any) -> String? {
        if let text = value as? String { return text.isEmpty ? nil : text }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "是" : "否" }
            return number.stringValue
        }
        if value is NSNull { return "—" }
        return nil
    }

    private static func identifier(_ path: [String]) -> String {
        "/" + path.map { $0.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }
            .joined(separator: "/")
    }
}
