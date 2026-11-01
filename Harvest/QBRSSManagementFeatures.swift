import SwiftUI

struct QBRSSNode: Identifiable {
    let name: String
    let path: String
    let depth: Int
    let isFolder: Bool
    let values: [String: Any]
    var id: String { path }

    static func flatten(_ root: [String: Any], parent: String = "", depth: Int = 0) -> [QBRSSNode] {
        guard depth < 30 else { return [] }
        var result: [QBRSSNode] = []
        for name in root.keys.sorted() {
            let values = root[name] as? [String: Any] ?? [:]
            let path = parent.isEmpty ? name : parent + "/" + name
            let isFolder = values["uid"] == nil && values["url"] == nil
            result.append(QBRSSNode(name: name, path: path, depth: depth, isFolder: isFolder, values: values))
            if isFolder { result.append(contentsOf: flatten(values, parent: path, depth: depth + 1)) }
        }
        return result
    }
}

struct QBRSSRule: Identifiable {
    let name: String
    let values: [String: Any]
    var id: String { name }
}

enum QBRSSActionKind: String { case folder = "新建文件夹", feed = "添加 RSS 源", editFeed = "修改源地址", move = "移动条目", rule = "自动下载规则", rename = "重命名规则" }

struct QBRSSEditTarget: Identifiable {
    let id = UUID()
    let kind: QBRSSActionKind
    var name = ""
    var values: [String: Any] = [:]
}

@MainActor
final class QBRSSManagementModel: ObservableObject {
    @Published var downloaders: [DownloaderItem] = []
    @Published var nodes: [QBRSSNode] = []
    @Published var rules: [QBRSSRule] = []
    @Published var autoDownload = false
    @Published var processing = false
    @Published var loading = false
    @Published var togglesLoaded = false
    @Published var error = ""
    @Published var working = false
    @Published var result: ManagementResult?
    var generation = 0
    private var loadedID: Int?

    func loadDownloaders(_ app: AppState) async {
        do {
            downloaders = jsonRows(try await app.api(APIPath.downloaders)).map(DownloaderItem.init)
                .filter { !$0.category.lowercased().contains("tr") }
        } catch { if !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }

    func load(_ app: AppState, id: Int, withData: Bool) async {
        guard id > 0 else { return }
        generation += 1
        let requestGeneration = generation
        if loadedID != id { nodes = []; rules = []; loadedID = id }
        loading = true
        togglesLoaded = false
        error = ""
        defer { if requestGeneration == generation { loading = false } }
        do {
            let raw = managementPayload(try await app.api(ManagementAPI.qbRSS + "/\(id)", query: ["with_data": withData]))
            guard !Task.isCancelled, generation == requestGeneration else { return }
            nodes = QBRSSNode.flatten(raw as? [String: Any] ?? [:])
            let ruleMap = managementPayload(try await app.api(ManagementAPI.qbRSS + "/rules/\(id)")) as? [String: Any] ?? [:]
            guard !Task.isCancelled, generation == requestGeneration else { return }
            rules = ruleMap.keys.sorted().compactMap { name in
                guard let value = ruleMap[name] as? [String: Any] else { return nil }
                return QBRSSRule(name: name, values: value)
            }
            let prefs = managementPayload(try await app.api(APIPath.downloaderPreferences + "\(id)")) as? [String: Any] ?? [:]
            guard !Task.isCancelled, generation == requestGeneration else { return }
            let values = prefs.dict("prefs", "preferences") ?? prefs
            autoDownload = values.bool("rss_auto_downloading_enabled") ?? false
            processing = values.bool("rss_processing_enabled") ?? false
            togglesLoaded = true
        } catch { if !isRequestCancellation(error), generation == requestGeneration { self.error = error.localizedDescription } }
    }

    func perform(_ app: AppState, title: String, path: String, method: HTTPMethod = .post,
                 query: [String: Any] = [:], body: Any? = nil, showResult: Bool = false) async -> Bool {
        guard !working else { return false }
        working = true
        error = ""
        let feedback = app.beginManualTask(title)
        defer { working = false }
        do {
            let value = try await app.api(path, method: method, query: query, body: body)
            if showResult { result = ManagementResult(title: title, values: value) }
            app.finishManualTask(feedback, success: true, message: jsonMessage(value) ?? "操作完成")
            return true
        } catch {
            if isRequestCancellation(error) { app.cancelManualTask(feedback) }
            else { self.error = error.localizedDescription; app.finishManualTask(feedback, success: false, message: error.localizedDescription) }
            return false
        }
    }
}

struct QBRSSManagementView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var model = QBRSSManagementModel()
    @State private var downloaderID: Int
    @State private var withData = false
    @State private var edit: QBRSSEditTarget?
    @State private var deleteNode: QBRSSNode?
    @State private var deleteRule: QBRSSRule?

    init(initialDownloaderID: Int = 0) { _downloaderID = State(initialValue: initialDownloaderID) }

    var body: some View {
        List {
            Section("下载器") {
                Picker("qBittorrent", selection: $downloaderID) {
                    Text("请选择").tag(0)
                    ForEach(model.downloaders) { Text($0.name).tag($0.id) }
                }.disabled(model.working)
                if downloaderID > 0 { options }
            }
            if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(HarvestTheme.coral) }
            if model.loading { ProgressView("正在加载 RSS") }
            if downloaderID > 0 {
                Section("RSS 源与文件夹") {
                    if model.nodes.isEmpty, !model.loading { Text("暂无 RSS 源").foregroundStyle(.secondary) }
                    ForEach(model.nodes) { node in nodeRow(node) }
                }
                Section("自动下载规则") {
                    if model.rules.isEmpty, !model.loading { Text("暂无规则").foregroundStyle(.secondary) }
                    ForEach(model.rules) { rule in ruleRow(rule) }
                }
            }
        }
        .navigationTitle("下载器 RSS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task {
            await model.loadDownloaders(app)
            if downloaderID == 0 { downloaderID = model.downloaders.first?.id ?? 0 }
        }
        .task(id: "\(downloaderID)-\(withData)") { await model.load(app, id: downloaderID, withData: withData) }
        .refreshable { await model.load(app, id: downloaderID, withData: withData) }
        .sheet(item: $edit) { target in
            QBRSSActionSheet(target: target, downloaderID: downloaderID, model: model) {
                await model.load(app, id: downloaderID, withData: withData)
            }.environmentObject(app)
        }
        .sheet(item: $model.result) { ManagementResultView(result: $0) }
        .confirmationDialog("删除选中的 RSS 条目？", isPresented: Binding(
            get: { deleteNode != nil }, set: { if !$0 { deleteNode = nil } }
        ), titleVisibility: .visible) {
            Button("删除条目", role: .destructive) {
                guard let node = deleteNode else { return }
                deleteNode = nil
                action("删除 RSS 条目", suffix: "/item/\(downloaderID)", method: .delete, query: ["path": node.path])
            }
        }
        .confirmationDialog("删除选中的自动下载规则？", isPresented: Binding(
            get: { deleteRule != nil }, set: { if !$0 { deleteRule = nil } }
        ), titleVisibility: .visible) {
            Button("删除规则", role: .destructive) {
                guard let rule = deleteRule else { return }
                deleteRule = nil
                action("删除 RSS 规则", suffix: "/rules/\(downloaderID)/" + urlPathSegment(rule.name), method: .delete)
            }
        }
    }

    private var options: some View {
        Group {
            Toggle("自动下载", isOn: Binding(get: { model.autoDownload }, set: { value in
                action("设置自动下载", suffix: "/auto-download/\(downloaderID)", method: .put, body: ["enabled": value])
            })).disabled(!model.togglesLoaded || model.working)
            Toggle("RSS 处理", isOn: Binding(get: { model.processing }, set: { value in
                action("设置 RSS 处理", suffix: "/processing/\(downloaderID)", method: .put, body: ["enabled": value])
            })).disabled(!model.togglesLoaded || model.working)
            Toggle("读取文章明细", isOn: $withData).disabled(model.working)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("添加 RSS 源") { edit = QBRSSEditTarget(kind: .feed) }
                Button("新建文件夹") { edit = QBRSSEditTarget(kind: .folder) }
                Button("新建自动下载规则") { edit = QBRSSEditTarget(kind: .rule) }
                Button("刷新") { Task { await model.load(app, id: downloaderID, withData: withData) } }
            } label: { Image(systemName: "plus.circle") }
            .disabled(downloaderID == 0 || model.working)
        }
    }

    private func nodeRow(_ node: QBRSSNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: node.isFolder ? "folder" : "dot.radiowaves.left.and.right").foregroundStyle(HarvestTheme.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name).font(.subheadline.weight(.medium))
                if node.values.bool("hasError") == true { Text("该源存在错误").font(.caption).foregroundStyle(HarvestTheme.coral) }
                if let date = node.values.string("lastBuildDate"), !date.isEmpty { Text(date).font(.caption2).foregroundStyle(.secondary) }
                if !node.isFolder, withData {
                    NavigationLink("文章 · \(node.values.rows("articles").count) 项") {
                        QBRSSArticlesView(node: node, downloaderID: downloaderID, model: model)
                    }.font(.caption)
                }
            }
            Spacer()
            Menu {
                Button("刷新") { action("刷新 RSS 条目", suffix: "/item/refresh/\(downloaderID)", body: ["path": node.path]) }
                if !node.isFolder {
                    Button("修改地址") { edit = QBRSSEditTarget(kind: .editFeed, name: node.path, values: ["url": node.values.string("url") ?? "", "path": node.path]) }
                }
                Button("移动") { edit = QBRSSEditTarget(kind: .move, name: node.path, values: ["item_path": node.path]) }
                Button("删除", role: .destructive) { deleteNode = node }
            } label: { Image(systemName: "ellipsis") }.disabled(model.working)
        }.padding(.leading, CGFloat(min(node.depth, 5)) * 12)
    }

    private func ruleRow(_ rule: QBRSSRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name).font(.subheadline.weight(.semibold))
                Text(rule.values.bool("enabled") == true ? "启用" : "停用").font(.caption).foregroundStyle(.secondary)
                Text([rule.values.string("mustContain"), rule.values.string("mustNotContain")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("编辑") { edit = QBRSSEditTarget(kind: .rule, name: rule.name, values: rule.values) }
                Button("重命名") { edit = QBRSSEditTarget(kind: .rename, name: rule.name) }
                Button("预览匹配文章") {
                    action("匹配文章", suffix: "/rules/matching/\(downloaderID)/" + urlPathSegment(rule.name), method: .get, showResult: true)
                }
                Button("删除", role: .destructive) { deleteRule = rule }
            } label: { Image(systemName: "ellipsis") }.disabled(model.working)
        }
    }

    private func action(_ title: String, suffix: String, method: HTTPMethod = .post,
                        query: [String: Any] = [:], body: Any? = nil, showResult: Bool = false) {
        let id = downloaderID
        Task {
            if await model.perform(app, title: title, path: ManagementAPI.qbRSS + suffix,
                                   method: method, query: query, body: body, showResult: showResult), id == downloaderID {
                await model.load(app, id: id, withData: withData)
            }
        }
    }
}

private struct QBRSSArticlesView: View {
    @EnvironmentObject private var app: AppState
    let node: QBRSSNode
    let downloaderID: Int
    @ObservedObject var model: QBRSSManagementModel
    @State private var readIDs: Set<String> = []

    var body: some View {
        List(Array(node.values.rows("articles").enumerated()), id: \.offset) { _, article in
            VStack(alignment: .leading, spacing: 6) {
                Text(article.string("title") ?? "未命名文章").font(.subheadline.weight(.medium))
                Text(article.string("date") ?? "").font(.caption2).foregroundStyle(.secondary)
                if let id = article.string("id"), article.bool("isRead") != true, !readIDs.contains(id) {
                    Button("标记已读") {
                        Task {
                            if await model.perform(app, title: "标记文章已读", path: ManagementAPI.qbRSS + "/item/read/\(downloaderID)", body: ["path": node.path, "article_id": id]) {
                                readIDs.insert(id)
                            }
                        }
                    }.disabled(model.working)
                }
                if let link = article.string("link"), let url = URL(string: link), ["http", "https"].contains(url.scheme ?? "") {
                    Link("查看详情", destination: url)
                }
            }
        }.navigationTitle(node.name)
    }
}

private struct QBRSSActionSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let target: QBRSSEditTarget
    let downloaderID: Int
    @ObservedObject var model: QBRSSManagementModel
    let onSaved: () async -> Void
    @State private var values: [String: Any]
    @State private var ruleName: String
    @State private var feedPaths: Set<String>
    @State private var savePath: String
    @State private var category: String
    @State private var error = ""

    init(target: QBRSSEditTarget, downloaderID: Int, model: QBRSSManagementModel, onSaved: @escaping () async -> Void) {
        self.target = target
        self.downloaderID = downloaderID
        self.model = model
        self.onSaved = onSaved
        _values = State(initialValue: target.values)
        _ruleName = State(initialValue: target.name)
        _feedPaths = State(initialValue: Set(target.values.strings("affectedFeeds")))
        let params = target.values.dict("torrentParams") ?? [:]
        _savePath = State(initialValue: params.string("save_path", "savePath") ?? "")
        _category = State(initialValue: params.string("category") ?? "")
    }

    private var fields: [ManagementField] {
        switch target.kind {
        case .folder: return [.init(key: "path", label: "文件夹路径", required: true)]
        case .feed, .editFeed: return [.init(key: "url", label: "RSS 地址", required: true), .init(key: "path", label: "源路径（可选）")]
        case .move: return [.init(key: "item_path", label: "当前路径", required: true), .init(key: "dest_path", label: "目标路径", required: true)]
        case .rename: return [.init(key: "new_rule_name", label: "新规则名称", required: true)]
        case .rule:
            return [.init(key: "enabled", label: "启用", kind: .toggle, defaultValue: true),
                    .init(key: "priority", label: "优先级", kind: .integer, defaultValue: 0),
                    .init(key: "useRegex", label: "使用正则", kind: .toggle, defaultValue: false),
                    .init(key: "mustContain", label: "必须包含"), .init(key: "mustNotContain", label: "必须排除"),
                    .init(key: "episodeFilter", label: "剧集过滤"),
                    .init(key: "ignoreDays", label: "忽略天数", kind: .integer, defaultValue: 0),
                    .init(key: "smartFilter", label: "智能过滤", kind: .toggle, defaultValue: false)]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if target.kind == .rule { TextField("规则名称", text: $ruleName).disabled(!target.name.isEmpty) }
                ForEach(fields) { ManagementFieldInput(field: $0, values: $values) }
                if target.kind == .rule {
                    Section("下载目标") { TextField("保存路径", text: $savePath); TextField("分类", text: $category) }
                    Section("作用于 RSS 源") {
                        ForEach(model.nodes.filter { !$0.isFolder }) { node in
                            let url = node.values.string("url") ?? node.path
                            Toggle(node.path, isOn: Binding(get: { feedPaths.contains(url) }, set: {
                                if $0 { feedPaths.insert(url) } else { feedPaths.remove(url) }
                            }))
                        }
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(HarvestTheme.coral) }
                if !model.error.isEmpty { Text(model.error).foregroundStyle(HarvestTheme.coral) }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(target.kind.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(model.working) }
            }
        }.presentationDetents([.large])
    }

    @MainActor private func save() async {
        do {
            var body = try managementFormPayload(values, fields: fields)
            let suffix: String
            let method: HTTPMethod
            switch target.kind {
            case .folder: suffix = "/folders/\(downloaderID)"; method = .post
            case .feed: suffix = "/feeds/\(downloaderID)"; method = .post
            case .editFeed: suffix = "/feeds/\(downloaderID)"; method = .put
            case .move: suffix = "/item/move/\(downloaderID)"; method = .put
            case .rename:
                suffix = "/rules/rename/\(downloaderID)"; method = .put
                body["rule_name"] = target.name
            case .rule:
                guard !ruleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw APIError(statusCode: 0, message: "请填写规则名称")
                }
                suffix = "/rules/\(downloaderID)"; method = .put
                body["affectedFeeds"] = feedPaths.sorted()
                var params = target.values.dict("torrentParams") ?? [:]
                params["save_path"] = savePath
                params["category"] = category
                body["torrentParams"] = params
                body = ["rule_name": ruleName, "rule": body]
            }
            if target.kind == .feed || target.kind == .editFeed {
                guard let url = URL(string: body["url"] as? String ?? ""), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else {
                    throw APIError(statusCode: 0, message: "请输入有效 HTTP/HTTPS RSS 地址")
                }
            }
            if await model.perform(app, title: target.kind.rawValue, path: ManagementAPI.qbRSS + suffix, method: method, body: body) {
                await onSaved()
                dismiss()
            }
        } catch { self.error = error.localizedDescription }
    }
}
