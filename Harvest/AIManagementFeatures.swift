import SwiftUI

struct AIServicePreset: Decodable, Identifiable {
    let name: String
    let provider: String
    let baseURL: String
    let category: String
    let models: [String]
    var id: String { name }

    static func bundled() -> [AIServicePreset] {
        guard let url = Bundle.main.url(forResource: "AIServicePresets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([AIServicePreset].self, from: data) else { return [] }
        return values
    }
}

struct AIQuickCommand: Identifiable {
    let name: String
    let prompt: String
    var id: String { name }
    static let all: [AIQuickCommand] = [
        .init(name: "站点状态", prompt: "请分析当前站点的整体状态，列出异常站点及可能原因。"),
        .init(name: "签到检查", prompt: "今天有哪些站点签到失败？失败原因分别是什么？"),
        .init(name: "下载器", prompt: "下载器当前运行状态如何？有哪些异常或离线的下载器？"),
        .init(name: "任务", prompt: "最近的计划任务执行情况如何？有哪些失败记录？"),
        .init(name: "RSS", prompt: "RSS 订阅当前状态如何？有哪些 RSS 源或订阅存在异常？"),
        .init(name: "总结", prompt: "请根据当前项目状态生成一份简要的运行总结。"),
        .init(name: "优化", prompt: "根据当前项目状态给出运维优化建议。"),
        .init(name: "安全", prompt: "检查当前配置是否存在安全风险或薄弱项。")
    ]
}

struct AIChatMessage: Identifiable {
    let id: String
    let role: String
    let content: String
    let failed: Bool
    let createdAt: String
    let context: [String: Any]
    let formattedAnswer: AIAnswerDocument?

    init(id: String = UUID().uuidString, role: String, content: String, failed: Bool = false,
         createdAt: String = "", context: [String: Any] = [:]) {
        self.id = id
        self.role = role
        self.content = content
        self.failed = failed
        self.createdAt = createdAt
        self.context = context
        self.formattedAnswer = role == "assistant" && !failed ? AIAnswerDocument(content) : nil
    }
    init(_ row: [String: Any]) {
        self.init(id: String(row.int("id") ?? stableIdentifier(row.string("created_at") ?? "", row.string("content") ?? "")),
                  role: row.string("role") ?? "assistant", content: row.string("content") ?? "",
                  failed: row.string("status") == "error", createdAt: row.string("created_at") ?? "",
                  context: row.dict("context") ?? [:])
    }
}

@MainActor
final class AIManagementModel: ObservableObject {
    @Published var messages: [AIChatMessage] = []
    @Published var dates: [String] = []
    @Published var selectedDate = ""
    @Published var hasMore = false
    @Published var loading = false
    @Published var sending = false
    @Published var working = false
    @Published var error = ""
    @Published var usage: [String: Any] = [:]
    @Published var diagnosis: [String: Any]?
    @Published var result: ManagementResult?
    private var cursor = 0
    private var cursorDate = ""
    private var initialized = false

    var totalTokens: Int { (usage.int("prompt_tokens") ?? 0) + (usage.int("completion_tokens") ?? 0) }
    var quotaExhausted: Bool {
        let limit = usage.int("daily_limit") ?? 0
        return limit > 0 && totalTokens >= limit
    }

    func request(_ app: AppState, path: String, method: HTTPMethod = .get, query: [String: Any] = [:],
                 body: Any? = nil, slow: Bool = false) async throws -> [String: Any] {
        let raw = try await app.api(path, method: method, query: query, body: body,
                                    timeoutInterval: slow ? 120 : nil)
        guard let payload = managementPayload(raw) as? [String: Any], !payload.isEmpty else {
            throw APIError(statusCode: 0, message: "服务端未返回有效数据，请检查 AI 配置、模型与额度")
        }
        return payload
    }

    func initialize(_ app: AppState) async {
        guard !initialized else { return }
        initialized = true
        do { dates = try await request(app, path: ManagementAPI.aiHistoryDates, query: ["limit": 100]).strings("dates") }
        catch { if !isRequestCancellation(error) { self.error = error.localizedDescription } }
        await loadHistory(app)
        await loadUsage(app)
    }

    func loadHistory(_ app: AppState, date: String = "", older: Bool = false) async {
        guard !loading, !sending else { return }
        loading = true
        error = ""
        defer { loading = false }
        do {
            var targetDate = older ? cursorDate : date
            var targetCursor = older ? cursor : 0
            if older && !hasMore {
                guard let previousDate = dates.sorted(by: >).first(where: { $0 < cursorDate }) else { return }
                targetDate = previousDate
                targetCursor = 0
            }
            var query: [String: Any] = ["cursor": targetCursor, "limit": 20]
            if !targetDate.isEmpty { query["date"] = targetDate }
            let page = try await request(app, path: ManagementAPI.aiHistory, query: query)
            let rows = page.rows("items").reversed().map(AIChatMessage.init)
            if older {
                let known = Set(messages.map(\.id))
                messages.insert(contentsOf: rows.filter { !known.contains($0.id) }, at: 0)
            } else { messages = rows }
            cursor = page.int("next_cursor") ?? 0
            cursorDate = page.string("date") ?? targetDate
            selectedDate = cursorDate
            hasMore = page.bool("has_more") ?? false
        } catch {
            if !isRequestCancellation(error) { self.error = error.localizedDescription }
        }
    }

    var canLoadOlder: Bool { hasMore || dates.contains { $0 < cursorDate } }

    func loadUsage(_ app: AppState) async {
        do { usage = try await request(app, path: ManagementAPI.aiUsage) }
        catch { if !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }

    func send(_ app: AppState, message: String, system: String) async {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, !loading else { return }
        guard text.count <= 4000 else { error = "输入不能超过 4000 字"; return }
        guard !quotaExhausted else { error = "今日 Token 额度已用尽"; return }
        sending = true
        error = ""
        messages.append(AIChatMessage(role: "user", content: text))
        defer { sending = false }
        do {
            var body = ["message": text]
            if !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["system"] = system }
            let response = try await request(app, path: ManagementAPI.aiChat, method: .post, body: body, slow: true)
            guard let answer = response.string("text"), !answer.isEmpty else {
                throw APIError(statusCode: 0, message: "AI 未返回回答，请检查模型配置")
            }
            messages.append(AIChatMessage(role: "assistant", content: answer, context: response.dict("context") ?? [:]))
            await loadUsage(app)
        } catch {
            guard !isRequestCancellation(error) else { return }
            self.error = error.localizedDescription
            messages.append(AIChatMessage(role: "assistant", content: error.localizedDescription, failed: true))
        }
    }

    func operation(_ app: AppState, title: String, path: String, method: HTTPMethod = .post,
                   body: Any? = nil, showResult: Bool = true) async -> [String: Any]? {
        guard !working else { return nil }
        working = true
        error = ""
        let feedback = app.beginManualTask(title)
        defer { working = false }
        do {
            let value = try await request(app, path: path, method: method, body: body, slow: true)
            if showResult { result = ManagementResult(title: title, values: value) }
            app.finishManualTask(feedback, success: true, message: "\(title)完成")
            return value
        } catch {
            if isRequestCancellation(error) { app.cancelManualTask(feedback) }
            else { self.error = error.localizedDescription; app.finishManualTask(feedback, success: false, message: error.localizedDescription) }
            return nil
        }
    }
}

struct AIManagementView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var model = AIManagementModel()
    @State private var page = "助手"
    @State private var input = ""
    @State private var system = ""
    @State private var showSystemPrompt = false
    @State private var confirmClear = false
    private let pages = ["助手", "配置", "诊断", "用量"]

    var body: some View {
        VStack(spacing: 8) {
            Picker("AI 管理", selection: $page) {
                ForEach(pages, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 12)
            if !model.error.isEmpty {
                Text(model.error).font(.caption).foregroundStyle(HarvestTheme.coral).padding(.horizontal, 12)
            }
            switch page {
            case "配置": AIConfigurationView(model: model)
            case "诊断": diagnostics
            case "用量": usage
            default: assistant
            }
        }
        .navigationTitle("AI 管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.initialize(app) }
        .sheet(item: $model.result) { ManagementResultView(result: $0) }
        .sheet(isPresented: $showSystemPrompt) {
            NavigationStack {
                Form { TextField("系统提示（可选）", text: $system, axis: .vertical).lineLimit(5...12) }
                    .navigationTitle("系统提示")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showSystemPrompt = false } } }
            }.presentationDetents([.large])
        }
    }

    private var assistant: some View {
        VStack(spacing: 6) {
            HStack {
                Menu {
                    Button("最新记录") { Task { await model.loadHistory(app) } }
                    ForEach(model.dates, id: \.self) { date in
                        Button(date) { Task { await model.loadHistory(app, date: date) } }
                    }
                } label: { Label(model.selectedDate.isEmpty ? "聊天历史" : model.selectedDate, systemImage: "clock") }
                Spacer()
                Button("清空当前对话", systemImage: "trash") { confirmClear = true }.labelStyle(.iconOnly)
            }
            .font(.caption).padding(.horizontal, 12).disabled(model.loading || model.sending)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if model.canLoadOlder {
                            Button("加载更早记录") { Task { await model.loadHistory(app, older: true) } }.disabled(model.loading)
                        }
                        ForEach(model.messages) { message in messageRow(message).id(message.id) }
                        if model.loading || model.sending { ProgressView(model.sending ? "正在回答" : "正在加载") }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.last?.id) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
            }
            commandPicker
            HStack(alignment: .bottom, spacing: 8) {
                TextField("输入问题，或 / 选择指令", text: $input, axis: .vertical).lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                Button { sendInput() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.sending || model.loading || model.quotaExhausted)
                    .accessibilityLabel("发送问题")
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
        .confirmationDialog("清空当前显示的对话？服务器历史仍保留。", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空当前对话", role: .destructive) { model.messages = [] }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("系统提示") { showSystemPrompt = true }
                    Button("刷新历史") { Task { await model.loadHistory(app) } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private var commandPicker: some View {
        let term = input.hasPrefix("/") ? String(input.dropFirst()).lowercased() : ""
        let commands = AIQuickCommand.all.filter { term.isEmpty || $0.name.lowercased().contains(term) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(commands) { command in
                    Button(command.name) { input = command.prompt }
                        .font(.caption).buttonStyle(.bordered)
                }
            }.padding(.horizontal, 12)
        }
    }

    private func messageRow(_ message: AIChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(message.role == "user" ? "我" : "AI 助手", systemImage: message.role == "user" ? "person.crop.circle" : "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.role == "user" ? HarvestTheme.blue : HarvestTheme.purple)
                Spacer()
                if !message.createdAt.isEmpty { Text(message.createdAt).font(.caption2).foregroundStyle(.secondary) }
                Button { copyPrivateText(message.content) } label: {
                    Image(systemName: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("复制回答原文")
            }
            if let document = message.formattedAnswer {
                AIAnswerView(document: document)
            } else {
                Text(message.content).font(.subheadline).lineSpacing(4).textSelection(.enabled)
                    .foregroundStyle(message.failed ? HarvestTheme.coral : Color.primary)
            }
            if !message.context.isEmpty {
                Divider()
                Button {
                    model.result = ManagementResult(title: "本次项目状态", values: message.context)
                } label: {
                    Label("查看本次项目状态", systemImage: "chart.bar.doc.horizontal")
                        .font(.caption)
                }
            }
            if message.failed, let prompt = retryPrompt(for: message) {
                Button("重试") { Task { await model.send(app, message: prompt, system: system) } }.disabled(model.sending)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == "user" ? HarvestTheme.blue.opacity(0.07) : Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func sendInput() {
        let text = input
        input = ""
        Task { await model.send(app, message: text, system: system) }
    }

    private func retryPrompt(for message: AIChatMessage) -> String? {
        guard let index = model.messages.firstIndex(where: { $0.id == message.id }) else { return nil }
        return model.messages[..<index].last(where: { $0.role == "user" })?.content
    }

    private var diagnostics: some View {
        List {
            Button("运行状态诊断", systemImage: "stethoscope") {
                Task { model.diagnosis = await model.operation(app, title: "AI 状态诊断", path: ManagementAPI.aiDiagnostics, showResult: false) }
            }.disabled(model.working)
            if model.working { ProgressView("正在诊断") }
            if let report = model.diagnosis {
                if let context = report.dict("context") {
                    Section("项目状态") {
                        ForEach(context.keys.sorted(), id: \.self) { key in
                            LabeledContent(managementFieldLabel(key), value: context.string(key) ?? "0")
                        }
                    }
                }
                Section("诊断结果") {
                    if report.rows("findings").isEmpty { Label("未发现异常", systemImage: "checkmark.shield") }
                    ForEach(Array(report.rows("findings").enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.string("message") ?? "").font(.subheadline)
                            Text(row.string("code") ?? "").font(.caption2).foregroundStyle(.secondary)
                        }.foregroundStyle(row.string("level") == "error" ? HarvestTheme.coral : Color.primary)
                    }
                }
                Button("复制诊断结果", systemImage: "doc.on.doc") {
                    let lines = report.rows("findings").compactMap { $0.string("message") }
                    copyPrivateText(lines.isEmpty ? "未发现异常" : lines.joined(separator: "\n"))
                }
            }
        }.listStyle(.insetGrouped)
    }

    private var usage: some View {
        List {
            Section("今日 Token 用量") {
                LabeledContent("日期", value: model.usage.string("day") ?? "—")
                LabeledContent("输入 Token", value: model.usage.string("prompt_tokens") ?? "0")
                LabeledContent("输出 Token", value: model.usage.string("completion_tokens") ?? "0")
                LabeledContent("总 Token", value: "\(model.totalTokens)")
                LabeledContent("每日额度", value: model.usage.string("daily_limit") ?? "—")
                let limit = model.usage.double("daily_limit") ?? 0
                ProgressView(value: limit > 0 ? min(Double(model.totalTokens) / limit, 1) : 0)
                if model.quotaExhausted { Text("额度已用尽，次日恢复").foregroundStyle(HarvestTheme.coral) }
                else if limit > 0, Double(model.totalTokens) / limit >= 0.8 { Text("已使用超过 80% 额度").foregroundStyle(HarvestTheme.amber) }
            }
        }
        .refreshable { await model.loadUsage(app) }
        .task { await model.loadUsage(app) }
    }
}

private struct AIConfigurationView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var model: AIManagementModel
    @State private var values: [String: Any] = [:]
    @State private var loaded = false
    @State private var showPresets = false
    @State private var confirmRestore = false
    @State private var selectedPreset: AIServicePreset?
    @State private var validationError = ""
    private let fields: [ManagementField] = [
        .init(key: "enabled", label: "启用 AI", kind: .toggle, defaultValue: false),
        .init(key: "provider", label: "服务类型", defaultValue: "openai", required: true),
        .init(key: "base_url", label: "服务地址"),
        .init(key: "api_key", label: "API Key（留空保留现有密钥）", kind: .secret),
        .init(key: "model", label: "模型名称"),
        .init(key: "temperature", label: "温度（0～2）", kind: .decimal, defaultValue: 0.2),
        .init(key: "max_tokens", label: "最大输出 Token", kind: .integer, defaultValue: 2048),
        .init(key: "timeout_seconds", label: "推理超时（秒）", kind: .integer, defaultValue: 60),
        .init(key: "daily_token_limit", label: "每日 Token 额度", kind: .integer, defaultValue: 100000),
        .init(key: "concurrency", label: "并发数", kind: .integer, defaultValue: 3),
        .init(key: "allow_write_actions", label: "允许写操作", kind: .toggle, defaultValue: false)
    ]

    var body: some View {
        Form {
            if !loaded { ProgressView("正在读取配置") }
            Section {
                Button("选择服务预设") { showPresets = true }
                if let preset = selectedPreset, !preset.models.isEmpty {
                    Menu("预设模型") { ForEach(preset.models, id: \.self) { name in Button(name) { values["model"] = name } } }
                }
            }
            Section("服务配置") { ForEach(fields) { ManagementFieldInput(field: $0, values: $values) } }
            if !validationError.isEmpty { Text(validationError).foregroundStyle(HarvestTheme.coral) }
            Section {
                Button("保存配置") { Task { await save() } }
                Button("测试已保存的服务") { Task { _ = await model.operation(app, title: "测试 AI 服务", path: ManagementAPI.aiTest) } }
                Button("恢复默认配置", role: .destructive) { confirmRestore = true }
            }.disabled(!loaded || model.working)
            if model.working { ProgressView("正在处理") }
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
        .sheet(isPresented: $showPresets) {
            AIServicePresetPicker { preset in
                selectedPreset = preset
                values["provider"] = preset.provider
                values["base_url"] = preset.baseURL
                if let name = preset.models.first { values["model"] = name }
            }
        }
        .confirmationDialog("恢复默认配置？", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) {
                Task {
                    let defaults = try? managementFormPayload([:], fields: fields.filter { !$0.required })
                    var body = defaults ?? [:]
                    body["provider"] = "openai"
                    if await model.operation(app, title: "恢复默认配置", path: ManagementAPI.aiProviders, method: .put, body: body, showResult: false) != nil { await load(force: true) }
                }
            }
        }
    }

    @MainActor private func load(force: Bool = false) async {
        guard force || !loaded else { return }
        do {
            values = try await model.request(app, path: ManagementAPI.aiProviders)
            values["api_key"] = ""
            loaded = true
        } catch { model.error = error.localizedDescription }
    }

    @MainActor private func save() async {
        do {
            let body = try managementFormPayload(values, fields: fields)
            let temperature = body["temperature"] as? Double ?? 0
            let timeout = body["timeout_seconds"] as? Int ?? 0
            guard (0...2).contains(temperature), (1...120).contains(timeout),
                  (body["max_tokens"] as? Int ?? 0) > 0, (body["concurrency"] as? Int ?? 0) > 0,
                  (body["daily_token_limit"] as? Int ?? 0) >= 0 else {
                throw APIError(statusCode: 0, message: "请检查温度、超时、Token 额度和并发数范围")
            }
            if !((body["base_url"] as? String) ?? "").isEmpty {
                guard let url = URL(string: body["base_url"] as? String ?? ""), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                    throw APIError(statusCode: 0, message: "请输入有效 HTTP/HTTPS 服务地址")
                }
            }
            if let saved = await model.operation(app, title: "保存 AI 配置", path: ManagementAPI.aiProviders, method: .put, body: body, showResult: false) {
                values = saved
                values["api_key"] = ""
                validationError = ""
            }
        } catch { validationError = error.localizedDescription }
    }
}

private struct AIServicePresetPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var presets = AIServicePreset.bundled()
    let onPick: (AIServicePreset) -> Void
    var body: some View {
        NavigationStack {
            List {
                ForEach(["模型厂商", "第三方平台", "云服务商", "本地"], id: \.self) { category in
                    Section(category) {
                        ForEach(presets.filter { $0.category == category && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { preset in
                            Button { onPick(preset); dismiss() } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.name).foregroundStyle(.primary)
                                    Text(preset.baseURL).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索服务商")
            .navigationTitle("服务预设")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationDetents([.large])
    }
}
