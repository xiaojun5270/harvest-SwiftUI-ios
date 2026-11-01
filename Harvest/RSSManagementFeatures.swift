import SwiftUI

enum RSSSection: String, CaseIterable, Identifiable {
    case subscriptions = "订阅", feeds = "RSS 源", tags = "标签", plans = "方案", history = "历史"
    var id: String { rawValue }
    var path: String {
        switch self {
        case .subscriptions: ManagementAPI.rssSubscriptions
        case .feeds: ManagementAPI.rssFeeds
        case .tags: ManagementAPI.rssTags
        case .plans: ManagementAPI.rssPlans
        case .history: ManagementAPI.rssHistory
        }
    }
    var fields: [ManagementField] {
        switch self {
        case .feeds:
            return [
                .init(key: "name", label: "源名称", required: true),
                .init(key: "rss", label: "RSS 地址", required: true),
                .init(key: "sort", label: "优先级", kind: .integer, defaultValue: 1),
                .init(key: "available", label: "启用", kind: .toggle, defaultValue: true)
            ]
        case .tags:
            return [.init(key: "name", label: "标签名称", required: true),
                    .init(key: "enabled", label: "启用", kind: .toggle, defaultValue: true)]
        case .subscriptions:
            return [
                .init(key: "name", label: "订阅名称", required: true),
                .init(key: "enabled", label: "启用", kind: .toggle, defaultValue: true),
                .init(key: "keyword", label: "包含关键字"),
                .init(key: "excludes", label: "排除关键字", kind: .strings),
                .init(key: "season", label: "季数"),
                .init(key: "publish_year", label: "发布年份", kind: .strings),
                .init(key: "douban_id", label: "豆瓣 ID"),
                .init(key: "imdb_id", label: "IMDb ID"),
                .init(key: "tmdb_id", label: "TMDB ID")
            ]
        case .plans:
            return [
                .init(key: "name", label: "方案名称", required: true),
                .init(key: "enabled", label: "启用", kind: .toggle, defaultValue: true),
                .init(key: "start_download", label: "添加后开始下载", kind: .toggle, defaultValue: true),
                .init(key: "min_size_mb", label: "最小大小（MB）", kind: .integer, defaultValue: 1024),
                .init(key: "max_size_mb", label: "最大大小（MB）", kind: .integer, defaultValue: 20480),
                .init(key: "category", label: "内容分类"),
                .init(key: "resolution", label: "分辨率", kind: .strings),
                .init(key: "video_codec", label: "视频编码", kind: .strings),
                .init(key: "audio_codec", label: "音频编码", kind: .strings),
                .init(key: "source", label: "来源媒介", kind: .strings),
                .init(key: "publisher", label: "制作组", kind: .strings),
                .init(key: "discount", label: "优惠关键字", kind: .strings),
                .init(key: "tags", label: "其他标签", kind: .strings),
                .init(key: "excludes", label: "排除关键字", kind: .strings)
            ]
        case .history: return []
        }
    }
}

let rssTagCategories: [(String, String)] = [
    ("resolution", "分辨率"), ("video_quality", "画质"), ("video_codec", "视频编码"),
    ("audio_codec", "音频编码"), ("source", "来源媒介"), ("publisher", "制作组"),
    ("season", "季数"), ("publish_year", "发布年份"), ("category", "分类"),
    ("discount", "优惠"), ("tags", "其他标签")
]

@MainActor
final class RSSManagementModel: ObservableObject {
    @Published var records: [RSSSection: [ManagementRecord]] = [:]
    @Published var loading = false
    @Published var working = false
    @Published var error = ""
    @Published var result: ManagementResult?
    @Published var downloaders: [DownloaderItem] = []
    @Published var sites: [SiteItem] = []

    func load(_ app: AppState, section: RSSSection, force: Bool = false) async {
        guard force || records[section] == nil else { return }
        loading = true
        error = ""
        defer { loading = false }
        do {
            records[section] = managementRows(try await app.api(section.path)).map(ManagementRecord.init)
        } catch {
            if !isRequestCancellation(error) { self.error = error.localizedDescription }
        }
    }

    func references(_ app: AppState, section: RSSSection) async {
        if section == .subscriptions { await load(app, section: .plans) }
        if section == .plans {
            async let feeds: Void = load(app, section: .feeds)
            async let tags: Void = load(app, section: .tags)
            _ = await (feeds, tags)
        }
        do {
            if section == .plans, downloaders.isEmpty {
                downloaders = jsonRows(try await app.api(APIPath.downloaders)).map(DownloaderItem.init)
            }
            if section == .feeds, sites.isEmpty { sites = jsonRows(try await app.api(APIPath.sites)).map(SiteItem.init) }
        } catch {
            if !isRequestCancellation(error) { self.error = error.localizedDescription }
        }
    }

    func action(_ app: AppState, title: String, path: String, method: HTTPMethod = .post,
                query: [String: Any] = [:], body: Any? = nil, showResult: Bool = true) async -> Bool {
        guard !working else { return false }
        working = true
        error = ""
        let feedback = app.beginManualTask(title)
        defer { working = false }
        do {
            let raw = try await app.api(path, method: method, query: query, body: body)
            if showResult { result = ManagementResult(title: title, values: raw) }
            app.finishManualTask(feedback, success: true, message: jsonMessage(raw) ?? "操作完成")
            return true
        } catch {
            if isRequestCancellation(error) { app.cancelManualTask(feedback) }
            else {
                self.error = error.localizedDescription
                app.finishManualTask(feedback, success: false, message: error.localizedDescription)
            }
            return false
        }
    }
}

struct RSSManagementView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var model = RSSManagementModel()
    @State private var section = RSSSection.subscriptions
    @State private var editor: RSSEditTarget?
    @State private var deletion: ManagementRecord?
    @State private var confirmClear = false
    @State private var query = ""

    private var visible: [ManagementRecord] {
        let rows = model.records[section] ?? []
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.name.localizedCaseInsensitiveContains(query) || summary($0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section {
                Picker("管理类型", selection: $section) {
                    ForEach(RSSSection.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(HarvestTheme.coral) }
            if model.loading && model.records[section] == nil { ProgressView("正在加载") }
            else if visible.isEmpty { ContentUnavailableView("暂无\(section.rawValue)", systemImage: "dot.radiowaves.left.and.right") }
            ForEach(visible) { row in recordRow(row) }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(8)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("RSS 订阅")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索\(section.rawValue)")
        .toolbar { toolbar }
        .task(id: section) { await model.load(app, section: section) }
        .refreshable { await model.load(app, section: section, force: true) }
        .sheet(item: $editor) { target in
            RSSEditorSheet(target: target, model: model).environmentObject(app)
        }
        .sheet(item: $model.result) { ManagementResultView(result: $0) }
        .confirmationDialog("删除这条\(section.rawValue)？", isPresented: Binding(
            get: { deletion != nil }, set: { if !$0 { deletion = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                guard let row = deletion else { return }
                deletion = nil
                Task {
                    if await model.action(app, title: "删除\(section.rawValue)", path: "\(section.path)/\(row.id)", method: .delete, showResult: false) {
                        await model.load(app, section: section, force: true)
                    }
                }
            }
        }
        .confirmationDialog("清空全部推送历史？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) {
                Task {
                    if await model.action(app, title: "清空历史", path: ManagementAPI.rssHistory, method: .delete, showResult: false) {
                        await model.load(app, section: .history, force: true)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if section != .history {
                Button { editor = RSSEditTarget(section: section, record: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加\(section.rawValue)")
            }
            Menu {
                Button("刷新", systemImage: "arrow.clockwise") { Task { await model.load(app, section: section, force: true) } }
                if section == .tags {
                    Button("导入默认标签", systemImage: "square.and.arrow.down") {
                        Task {
                            if await model.action(app, title: "导入默认标签", path: ManagementAPI.rssTags + "/import", method: .get) {
                                await model.load(app, section: .tags, force: true)
                            }
                        }
                    }
                }
                if section == .history { Button("清空历史", role: .destructive) { confirmClear = true } }
                Button("执行全部订阅", systemImage: "play.fill") {
                    Task {
                        if await model.action(app, title: "执行全部订阅", path: ManagementAPI.rssRun) {
                            await model.load(app, section: .history, force: true)
                        }
                    }
                }
                NavigationLink("qBittorrent RSS") { QBRSSManagementView() }
            } label: { Image(systemName: "ellipsis.circle") }
            .disabled(model.working)
        }
    }

    private func recordRow(_ row: ManagementRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.name).font(.subheadline.weight(.semibold))
                Spacer()
                if let enabled = row.values.bool("enabled", "available") {
                    Text(enabled ? "启用" : "停用").font(.caption2).foregroundStyle(enabled ? HarvestTheme.green : .secondary)
                }
                Menu { rowActions(row) } label: { Image(systemName: "ellipsis") }
                    .disabled(model.working)
            }
            Text(summary(row)).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            if section == .history {
                Text(row.values.bool("pushed") == true ? "已推送" : "未推送")
                    .font(.caption2).foregroundStyle(HarvestTheme.blue)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private func rowActions(_ row: ManagementRecord) -> some View {
        if section != .history { Button("编辑") { editor = RSSEditTarget(section: section, record: row) } }
        if section == .feeds {
            Button("预览条目") { perform("RSS 源预览", path: "\(section.path)/\(row.id)/preview", method: .get) }
            Button("刷新 RSS 源") { perform("刷新 RSS 源", path: "\(section.path)/\(row.id)/refresh") }
        }
        if section == .subscriptions {
            Button("预览匹配") { perform("预览匹配", path: "\(section.path)/\(row.id)/preview", method: .get, query: ["limit": 20]) }
            Button("执行订阅") { perform("执行订阅", path: "\(ManagementAPI.rssRun)/\(row.id)") }
        }
        if section == .history {
            Button("重新推送") { perform("推送历史条目", path: "\(section.path)/\(row.id)/push", method: .put) }
        }
        Button("删除", role: .destructive) { deletion = row }
    }

    private func perform(_ title: String, path: String, method: HTTPMethod = .post, query: [String: Any] = [:]) {
        Task {
            if await model.action(app, title: title, path: path, method: method, query: query) {
                if section == .history { await model.load(app, section: .history, force: true) }
            }
        }
    }

    private func summary(_ row: ManagementRecord) -> String {
        let keys: [String]
        switch section {
        case .subscriptions: keys = ["keyword", "season", "excludes", "douban_id", "imdb_id", "tmdb_id"]
        case .feeds: keys = ["sort", "site_id"]
        case .tags:
            return rssTagCategories.first { $0.0 == row.values.string("category") }?.1 ?? "未分类"
        case .plans: keys = ["min_size_mb", "max_size_mb", "downloader_category", "downloader_save_path", "resolution", "video_codec"]
        case .history: keys = ["subscription_name", "feed_name", "message", "created_at"]
        }
        return keys.compactMap { key in
            if let list = row.values[key] as? [String], !list.isEmpty { return list.joined(separator: " / ") }
            return row.values.string(key).flatMap { $0.isEmpty ? nil : $0 }
        }.joined(separator: " · ")
    }
}

struct RSSEditTarget: Identifiable {
    let id = UUID()
    let section: RSSSection
    let record: ManagementRecord?
}

private struct RSSEditorSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let target: RSSEditTarget
    @ObservedObject var model: RSSManagementModel
    @State private var values: [String: Any]
    @State private var planID: Int
    @State private var downloaderID: Int
    @State private var siteID: Int
    @State private var feedIDs: Set<Int>
    @State private var tagCategory: String
    @State private var savePath: String
    @State private var downloaderCategory: String
    @State private var categoryPaths: [String: String] = [:]
    @State private var categoriesLoading = false
    @State private var validationError = ""

    init(target: RSSEditTarget, model: RSSManagementModel) {
        self.target = target
        self.model = model
        var row = target.record?.values ?? [:]
        if row["rss"] == nil { row["rss"] = row["url"] }
        if row["excludes"] == nil { row["excludes"] = row["exclude"] }
        if row["enabled"] == nil { row["enabled"] = row["available"] }
        if row["start_download"] == nil { row["start_download"] = row["start"] }
        for key in ["douban", "imdb", "tmdb"] {
            if row[key + "_id"] == nil { row[key + "_id"] = row[key] }
        }
        _values = State(initialValue: row)
        _planID = State(initialValue: row.int("plan_id") ?? 0)
        _downloaderID = State(initialValue: row.int("downloader_id") ?? 0)
        _siteID = State(initialValue: row.int("site_id") ?? 0)
        _feedIDs = State(initialValue: Set(row.strings("rss_feed_ids", "rss_list").compactMap(Int.init)))
        _tagCategory = State(initialValue: row.string("category") ?? "resolution")
        _savePath = State(initialValue: row.string("downloader_save_path") ?? "")
        _downloaderCategory = State(initialValue: row.string("downloader_category") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本配置") {
                    ForEach(target.section.fields) { field in ManagementFieldInput(field: field, values: $values) }
                }
                referenceFields
                if target.section == .plans { planFields }
                if !validationError.isEmpty { Text(validationError).foregroundStyle(HarvestTheme.coral) }
                if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(HarvestTheme.coral) }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle((target.record == nil ? "添加" : "编辑") + target.section.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }.disabled(model.working || categoriesLoading)
                }
            }
            .task { await model.references(app, section: target.section) }
            .task(id: downloaderID) { if target.section == .plans { await loadCategories() } }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private var referenceFields: some View {
        if target.section == .feeds {
            Section("关联站点") {
                Picker("站点", selection: $siteID) {
                    Text("不关联").tag(0)
                    ForEach(model.sites) { site in Text(site.name).tag(site.id) }
                }
            }
        }
        if target.section == .tags {
            Section("标签分类") {
                Picker("分类", selection: $tagCategory) {
                    ForEach(rssTagCategories, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
        }
        if target.section == .subscriptions {
            Section("订阅方案") {
                Picker("方案", selection: $planID) {
                    Text("请选择方案").tag(0)
                    ForEach(model.records[.plans] ?? []) { Text($0.name).tag($0.id) }
                }
            }
        }
    }

    private var planFields: some View {
        Group {
            Section("下载目标") {
                Picker("下载器", selection: $downloaderID) {
                    Text("请选择下载器").tag(0)
                    ForEach(model.downloaders) { Text($0.name).tag($0.id) }
                }
                if !categoryPaths.isEmpty {
                    Picker("下载器分类", selection: $downloaderCategory) {
                        Text("不指定").tag("")
                        if !downloaderCategory.isEmpty, categoryPaths[downloaderCategory] == nil {
                            Text(downloaderCategory).tag(downloaderCategory)
                        }
                        ForEach(categoryPaths.keys.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: downloaderCategory) { _, name in
                        if let path = categoryPaths[name], !path.isEmpty { savePath = path }
                    }
                } else { TextField("下载器分类", text: $downloaderCategory) }
                TextField("保存路径", text: $savePath).textInputAutocapitalization(.never)
                if categoriesLoading { ProgressView("正在读取分类") }
            }
            Section("RSS 源") {
                ForEach(model.records[.feeds] ?? []) { feed in
                    Toggle(feed.name, isOn: Binding(get: { feedIDs.contains(feed.id) }, set: {
                        if $0 { feedIDs.insert(feed.id) } else { feedIDs.remove(feed.id) }
                    }))
                }
            }
            Section("可用标签") {
                ForEach(model.records[.tags] ?? []) { tag in
                    let category = tag.values.string("category") ?? "tags"
                    Button {
                        if category == "category" { values[category] = tag.name }
                        else {
                            var list = values[category] as? [String] ?? (values.string(category) ?? "").components(separatedBy: ",").filter { !$0.isEmpty }
                            if list.contains(tag.name) { list.removeAll { $0 == tag.name } } else { list.append(tag.name) }
                            values[category] = list
                        }
                    } label: {
                        HStack { Text(tag.name); Spacer(); Text(rssTagCategories.first { $0.0 == category }?.1 ?? category).foregroundStyle(.secondary) }
                    }
                    .disabled(!target.section.fields.contains { $0.key == category })
                }
            }
        }
    }

    @MainActor private func loadCategories() async {
        categoryPaths = [:]
        guard downloaderID > 0 else { return }
        let id = downloaderID
        categoriesLoading = true
        defer { if id == downloaderID { categoriesLoading = false } }
        do {
            let raw = managementPayload(try await app.api(APIPath.downloaderCategories + "\(id)"))
            guard id == downloaderID, !Task.isCancelled else { return }
            if let dictionary = raw as? [String: Any] {
                for (name, value) in dictionary {
                    categoryPaths[name] = (value as? [String: Any])?.string("savePath", "save_path", "path") ?? ""
                }
            } else {
                for row in managementRows(raw) {
                    if let name = row.string("name", "category") { categoryPaths[name] = row.string("savePath", "save_path", "path") ?? "" }
                }
            }
        } catch {
            if !isRequestCancellation(error) { validationError = "分类读取失败，可手动填写：\(error.localizedDescription)" }
        }
    }

    @MainActor private func save() async {
        do {
            var body = try managementFormPayload(values, fields: target.section.fields)
            switch target.section {
            case .feeds:
                body["site_id"] = siteID
                guard let url = URL(string: body["rss"] as? String ?? ""), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                    throw APIError(statusCode: 0, message: "RSS 地址应为有效的 HTTP/HTTPS 地址")
                }
            case .tags: body["category"] = tagCategory
            case .subscriptions:
                guard planID > 0 else { throw APIError(statusCode: 0, message: "请选择订阅方案") }
                body["plan_id"] = planID
            case .plans:
                guard downloaderID > 0 else { throw APIError(statusCode: 0, message: "请选择下载器") }
                let minimum = body["min_size_mb"] as? Int ?? 0
                let maximum = body["max_size_mb"] as? Int ?? 0
                guard minimum >= 0, maximum >= minimum else { throw APIError(statusCode: 0, message: "大小范围无效") }
                body["downloader_id"] = downloaderID
                body["downloader_category"] = downloaderCategory
                body["downloader_save_path"] = savePath
                body["rss_feed_ids"] = feedIDs.sorted()
            case .history: return
            }
            let path = target.section.path + (target.record.map { "/\($0.id)" } ?? "")
            if await model.action(app, title: "保存\(target.section.rawValue)", path: path,
                                  method: target.record == nil ? .post : .put, body: body, showResult: false) {
                await model.load(app, section: target.section, force: true)
                dismiss()
            }
        } catch { validationError = error.localizedDescription }
    }
}
