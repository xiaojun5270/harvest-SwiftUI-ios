import Combine
import BackgroundTasks
import Foundation
import Security
import SwiftUI
import TDLibKit
import UIKit

enum TelegramBackgroundTaskConfiguration {
    static let identifier = "com.ptools.harvest.telegram-checkin"
}
enum TelegramCheckinRunStatus: String, Codable, CaseIterable {
    case idle
    case running
    case success
    case unmatched
    case failure
    case timeout

    var label: String {
        switch self {
        case .idle: "未执行"
        case .running: "签到中"
        case .success: "成功"
        case .unmatched: "已回复"
        case .failure: "失败"
        case .timeout: "超时"
        }
    }

    var icon: String {
        switch self {
        case .idle: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .success: "checkmark.seal.fill"
        case .unmatched: "questionmark.bubble.fill"
        case .failure: "xmark.octagon.fill"
        case .timeout: "hourglass"
        }
    }

    var color: Color {
        switch self {
        case .idle: .secondary
        case .running: HarvestTheme.blue
        case .success: HarvestTheme.green
        case .unmatched: HarvestTheme.amber
        case .failure: HarvestTheme.coral
        case .timeout: HarvestTheme.orange
        }
    }

    var isSuccessful: Bool { self == .success }
}

enum TelegramCheckinTrigger: String, Codable {
    case manual
    case scheduled

    var label: String { self == .manual ? "手动" : "定时" }
}

enum TelegramCheckinStepKind: String, Codable {
    case resolveBot
    case sendCommand
    case receiveResponse
    case panelAction
    case parseResult
    case forwardNotification

    var title: String {
        switch self {
        case .resolveBot: "定位 Bot"
        case .sendCommand: "发出指令"
        case .receiveResponse: "收到回复"
        case .panelAction: "提交面板操作"
        case .parseResult: "解析结果"
        case .forwardNotification: "推送转接"
        }
    }

    var icon: String {
        switch self {
        case .resolveBot: "person.crop.circle.badge.checkmark"
        case .sendCommand: "paperplane.fill"
        case .receiveResponse: "bubble.left.and.text.bubble.right.fill"
        case .panelAction: "rectangle.and.hand.point.up.left.fill"
        case .parseResult: "checkmark.seal.fill"
        case .forwardNotification: "bell.and.waves.left.and.right.fill"
        }
    }
}

struct TelegramCheckinStep: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: TelegramCheckinStepKind
    let status: TelegramCheckinRunStatus
    let detail: String
    let rawPayload: String
    let createdAt: Foundation.Date

    init(
        id: UUID = UUID(),
        kind: TelegramCheckinStepKind,
        status: TelegramCheckinRunStatus,
        detail: String,
        rawPayload: String = "",
        createdAt: Foundation.Date = Foundation.Date()
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.detail = detail
        self.rawPayload = rawPayload
        self.createdAt = createdAt
    }
}

struct TelegramCheckinBot: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var username = ""
    var command = "/checkin"
    var additionalCommands: [String]?
    var successKeywords: [String] = []
    var failureKeywords: [String] = []
    var automaticallyPressPanelButton: Bool?
    var panelButtonKeywords: [String]?
    var isEnabled = true
    var scheduleEnabled = false
    var scheduleMinute = 8 * 60
    var weekdays = [1, 2, 3, 4, 5, 6, 7]
    var timeoutSeconds = 30
    var retryCount = 1
    var resolvedChatID: Int64?
    var resolvedTitle: String?
    var lastRunAt: Foundation.Date?
    var lastAutomaticRunAt: Foundation.Date?
    var lastStatus: TelegramCheckinRunStatus = .idle
    var lastResponse = ""

    var displayName: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? normalizedUsername : value
    }

    var commands: [String] {
        var seen = Set<String>()
        return ([command] + (additionalCommands ?? []))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var pressesPanelButton: Bool { automaticallyPressPanelButton ?? true }

    var effectivePanelButtonKeywords: [String] {
        let values = (panelButtonKeywords ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? ["签到"] : values
    }

    var normalizedUsername: String {
        var value = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), let host = url.host,
           host.lowercased() == "t.me" || host.lowercased() == "telegram.me" {
            value = url.pathComponents.dropFirst().first ?? value
        }
        value = value.replacingOccurrences(of: "https://t.me/", with: "", options: .caseInsensitive)
        value = value.replacingOccurrences(of: "http://t.me/", with: "", options: .caseInsensitive)
        value = value.replacingOccurrences(of: "t.me/", with: "", options: [.anchored, .caseInsensitive])
        value = value.replacingOccurrences(of: "telegram.me/", with: "", options: [.anchored, .caseInsensitive])
        while value.hasPrefix("@") { value.removeFirst() }
        return value.split(separator: "?", maxSplits: 1).first.map(String.init) ?? value
    }

    var scheduleText: String {
        guard scheduleEnabled else { return "未启用定时" }
        let hour = max(0, min(23, scheduleMinute / 60))
        let minute = max(0, min(59, scheduleMinute % 60))
        let selected = Set(weekdays)
        let dayText: String
        if selected.count == 7 {
            dayText = "每天"
        } else if selected == Set([2, 3, 4, 5, 6]) {
            dayText = "工作日"
        } else if selected == Set([1, 7]) {
            dayText = "周末"
        } else {
            let labels = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]
            dayText = weekdays.sorted().compactMap { labels[$0] }.map { "周\($0)" }.joined(separator: "、")
        }
        return String(format: "%@ %02d:%02d", dayText, hour, minute)
    }
}

struct TelegramCheckinHistory: Codable, Identifiable, Equatable {
    let id: UUID
    let botID: UUID
    let botName: String
    let username: String
    let command: String
    let trigger: TelegramCheckinTrigger
    let status: TelegramCheckinRunStatus
    let response: String
    let createdAt: Foundation.Date
    let duration: TimeInterval
    let attemptCount: Int
    let steps: [TelegramCheckinStep]?
}

struct TelegramCheckinCounter: Codable, Equatable {
    var runs = 0
    var attempts = 0
    var successes = 0
    var failures = 0
    var timeouts = 0
    var unmatched = 0
    var manualRuns = 0
    var scheduledRuns = 0

    var successRate: Double {
        guard runs > 0 else { return 0 }
        return Double(successes) / Double(runs)
    }

    mutating func include(_ record: TelegramCheckinHistory) {
        runs += 1
        attempts += max(1, record.attemptCount)
        switch record.status {
        case .success: successes += 1
        case .failure: failures += 1
        case .timeout: timeouts += 1
        case .unmatched: unmatched += 1
        case .idle, .running: break
        }
        switch record.trigger {
        case .manual: manualRuns += 1
        case .scheduled: scheduledRuns += 1
        }
    }
}

struct TelegramCheckinStatistics: Codable, Equatable {
    var overall = TelegramCheckinCounter()
    var bots: [String: TelegramCheckinCounter] = [:]
    var lastUpdatedAt: Foundation.Date?

    mutating func include(_ record: TelegramCheckinHistory) {
        overall.include(record)
        var counter = bots[record.botID.uuidString] ?? TelegramCheckinCounter()
        counter.include(record)
        bots[record.botID.uuidString] = counter
        lastUpdatedAt = record.createdAt
    }

    func counter(for botID: UUID) -> TelegramCheckinCounter {
        bots[botID.uuidString] ?? TelegramCheckinCounter()
    }
}

struct TelegramDiscoveredBot: Identifiable, Equatable {
    let userID: Int64
    let chatID: Int64
    let name: String
    let username: String

    var id: Int64 { userID }
}

@MainActor
final class TelegramCheckinStore: ObservableObject {
    static let shared = TelegramCheckinStore()

    @Published private(set) var bots: [TelegramCheckinBot] = []
    @Published private(set) var history: [TelegramCheckinHistory] = []
    @Published private(set) var statistics = TelegramCheckinStatistics()

    private struct Snapshot: Codable {
        var bots: [TelegramCheckinBot]
        var history: [TelegramCheckinHistory]
        var statistics: TelegramCheckinStatistics?
    }

    private let fileURL: URL?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Harvest", isDirectory: true)
            .appendingPathComponent("Telegram", isDirectory: true)
        if let base {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        fileURL = base?.appendingPathComponent("checkin-bots.json")
        load()
    }

    func bot(id: UUID) -> TelegramCheckinBot? { bots.first { $0.id == id } }

    func saveBot(_ value: TelegramCheckinBot) {
        var bot = value
        bot.name = bot.name.trimmingCharacters(in: .whitespacesAndNewlines)
        bot.username = bot.normalizedUsername
        let commands = bot.commands
        bot.command = commands.first ?? "/checkin"
        bot.additionalCommands = commands.count > 1 ? Array(commands.dropFirst()) : nil
        let panelKeywords = bot.effectivePanelButtonKeywords
        bot.panelButtonKeywords = panelKeywords
        bot.timeoutSeconds = max(5, min(120, bot.timeoutSeconds))
        bot.retryCount = max(0, min(3, bot.retryCount))
        bot.scheduleMinute = max(0, min(1_439, bot.scheduleMinute))
        bot.weekdays = Array(Set(bot.weekdays.filter { (1...7).contains($0) })).sorted()
        if let index = bots.firstIndex(where: { $0.id == bot.id }) {
            if bots[index].normalizedUsername.caseInsensitiveCompare(bot.normalizedUsername) != .orderedSame {
                bot.resolvedChatID = nil
                bot.resolvedTitle = nil
            }
            bots[index] = bot
        } else {
            bots.append(bot)
        }
        bots.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        persist()
        TelegramSessionController.scheduleBackgroundRefreshIfNeeded()
    }

    func deleteBot(id: UUID) {
        bots.removeAll { $0.id == id }
        persist()
        TelegramSessionController.scheduleBackgroundRefreshIfNeeded()
    }

    func setEnabled(id: UUID, enabled: Bool) {
        updateBot(id: id) { $0.isEnabled = enabled }
    }

    func beginRun(id: UUID) {
        updateBot(id: id, persistImmediately: false) {
            $0.lastStatus = .running
            $0.lastResponse = "正在等待 Bot 回复"
        }
    }

    func cacheResolvedChat(id: UUID, chatID: Int64, title: String) {
        updateBot(id: id) {
            $0.resolvedChatID = chatID
            $0.resolvedTitle = title
        }
    }

    func clearResolvedChat(id: UUID) {
        updateBot(id: id) {
            $0.resolvedChatID = nil
            $0.resolvedTitle = nil
        }
    }

    func markAutomaticAttempt(id: UUID, at date: Foundation.Date) {
        updateBot(id: id) { $0.lastAutomaticRunAt = date }
    }

    @discardableResult
    func finishRun(
        id: UUID,
        trigger: TelegramCheckinTrigger,
        status: TelegramCheckinRunStatus,
        response: String,
        startedAt: Foundation.Date,
        attempts: Int,
        steps: [TelegramCheckinStep]
    ) -> TelegramCheckinHistory? {
        guard var bot = bot(id: id) else { return nil }
        let finishedAt = Foundation.Date()
        bot.lastRunAt = finishedAt
        bot.lastStatus = status
        bot.lastResponse = response
        if trigger == .scheduled { bot.lastAutomaticRunAt = startedAt }
        if let index = bots.firstIndex(where: { $0.id == id }) { bots[index] = bot }
        let record = TelegramCheckinHistory(
            id: UUID(),
            botID: id,
            botName: bot.displayName,
            username: bot.normalizedUsername,
            command: bot.commands.joined(separator: " → "),
            trigger: trigger,
            status: status,
            response: response,
            createdAt: finishedAt,
            duration: max(0, finishedAt.timeIntervalSince(startedAt)),
            attemptCount: attempts,
            steps: steps
        )
        history.insert(record, at: 0)
        statistics.include(record)
        if history.count > 300 { history.removeLast(history.count - 300) }
        persist()
        return record
    }

    func history(for botID: UUID) -> [TelegramCheckinHistory] {
        history.filter { $0.botID == botID }
    }

    func statistics(for botID: UUID) -> TelegramCheckinCounter {
        statistics.counter(for: botID)
    }

    private func updateBot(
        id: UUID,
        persistImmediately: Bool = true,
        _ change: (inout TelegramCheckinBot) -> Void
    ) {
        guard let index = bots.firstIndex(where: { $0.id == id }) else { return }
        change(&bots[index])
        if persistImmediately { persist() }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        bots = snapshot.bots
        history = snapshot.history.sorted { $0.createdAt > $1.createdAt }
        if let savedStatistics = snapshot.statistics {
            statistics = savedStatistics
        } else {
            var migrated = TelegramCheckinStatistics()
            for record in history.reversed() { migrated.include(record) }
            statistics = migrated
            persist()
        }
    }

    private func persist() {
        guard let fileURL,
              let data = try? JSONEncoder().encode(
                Snapshot(bots: bots, history: history, statistics: statistics)
              ) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum TelegramAuthorizationPhase: Equatable {
    case starting
    case needsCredentials
    case configuring
    case needsPhone
    case needsCode
    case needsPassword(hint: String)
    case ready
    case loggingOut
    case unsupported(String)
    case failed(String)

    var label: String {
        switch self {
        case .starting: "正在启动"
        case .needsCredentials: "需要 API 凭据"
        case .configuring: "正在连接"
        case .needsPhone: "需要手机号"
        case .needsCode: "等待验证码"
        case .needsPassword: "需要两步验证"
        case .ready: "已登录"
        case .loggingOut: "正在退出"
        case .unsupported: "需要处理"
        case .failed: "连接失败"
        }
    }
}

enum TelegramCheckinError: LocalizedError {
    case notAuthorized
    case botNotFound
    case alreadyRunning
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "请先登录 Telegram"
        case .botNotFound: "TG Bot 配置不存在"
        case .alreadyRunning: "该 Bot 正在执行签到"
        case .invalidConfiguration(let message): message
        }
    }
}

@MainActor
final class TelegramSessionController: ObservableObject {
    private static var instance: TelegramSessionController?

    static var shared: TelegramSessionController {
        if let instance { return instance }
        let created = TelegramSessionController()
        instance = created
        return created
    }

    @Published private(set) var phase: TelegramAuthorizationPhase = .starting
    @Published private(set) var accountName = ""
    @Published private(set) var runningBotIDs: Set<UUID> = []
    @Published var lastError: String?

    private static let apiIDKey = "telegram.apiID"
    private static let apiHashKey = "telegram.apiHash"
    private static let phoneKey = "telegram.phone"
    private static let databaseKey = "telegram.databaseEncryptionKey"

    private struct PendingResponse {
        let chatID: Int64
        let afterMessageID: Int64
        let acceptsSameMessageID: Bool
        let baselineText: String?
        let baselineReplyMarkup: ReplyMarkup?
        let startedAt: Foundation.Date
        let continuation: CheckedContinuation<RecentResponse?, Never>
    }

    private struct RecentResponse {
        let messageID: Int64
        let date: Foundation.Date
        let text: String
        let replyMarkup: ReplyMarkup?
    }

    private enum PanelAction {
        case sendText(title: String, text: String)
        case callback(title: String, messageID: Int64, data: Foundation.Data)
        case unsupported(title: String, reason: String)
    }

    private let manager: TDLibClientManager
    private var client: TDLibClient?
    private var isApplyingParameters = false
    private var pendingPhone: String?
    private var schedulerTask: Task<Void, Never>?
    private var pendingResponses: [UUID: PendingResponse] = [:]
    private var recentResponses: [Int64: [RecentResponse]] = [:]
    private weak var notificationAppState: AppState?

    var isReady: Bool { phase == .ready }
    var savedAPIID: String { KeychainStore.get(Self.apiIDKey) ?? "" }
    var savedPhone: String { KeychainStore.get(Self.phoneKey) ?? "" }
    var hasSavedCredentials: Bool {
        Int(savedAPIID) != nil && !(KeychainStore.get(Self.apiHashKey) ?? "").isEmpty
    }

    private init() {
        manager = TDLibClientManager()
        client = nil
        createClient()
    }

    private func createClient() {
        guard client == nil else { return }
        phase = .starting
        client = manager.createClient { [weak self] data, client in
            guard let update = try? client.decoder.decode(Update.self, from: data) else { return }
            Task { @MainActor [weak self] in
                self?.receive(update)
            }
        }
    }

    func connect(apiIDText: String, apiHash: String, phone: String) {
        let normalizedHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiID = Int(apiIDText.trimmingCharacters(in: .whitespacesAndNewlines)), apiID > 0 else {
            lastError = "API ID 格式不正确"
            return
        }
        guard normalizedHash.count >= 16 else {
            lastError = "API Hash 格式不正确"
            return
        }
        guard !normalizedPhone.isEmpty else {
            lastError = "请输入国际格式手机号"
            return
        }
        KeychainStore.set(String(apiID), for: Self.apiIDKey)
        KeychainStore.set(normalizedHash, for: Self.apiHashKey)
        KeychainStore.set(normalizedPhone, for: Self.phoneKey)
        pendingPhone = normalizedPhone
        lastError = nil
        Task { await applyParametersIfPossible() }
    }

    func submitPhone(_ phone: String) async {
        let value = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            lastError = "请输入国际格式手机号"
            return
        }
        guard let client else { return }
        do {
            lastError = nil
            KeychainStore.set(value, for: Self.phoneKey)
            phase = .configuring
            _ = try await client.setAuthenticationPhoneNumber(phoneNumber: value, settings: nil)
        } catch {
            fail(error)
            phase = .needsPhone
        }
    }

    func submitCode(_ code: String) async {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let client else { return }
        do {
            lastError = nil
            phase = .configuring
            _ = try await client.checkAuthenticationCode(code: value)
        } catch {
            fail(error)
            phase = .needsCode
        }
    }

    func submitPassword(_ password: String) async {
        guard !password.isEmpty, let client else { return }
        do {
            lastError = nil
            phase = .configuring
            _ = try await client.checkAuthenticationPassword(password: password)
        } catch {
            fail(error)
            phase = .needsPassword(hint: "")
        }
    }

    func logOut() async {
        guard let client else { return }
        phase = .loggingOut
        schedulerTask?.cancel()
        do {
            _ = try await client.logOut()
            accountName = ""
            KeychainStore.delete(Self.phoneKey)
        } catch {
            fail(error)
            phase = .ready
        }
    }

    func clearCredentialsForRetry() {
        KeychainStore.delete(Self.apiIDKey)
        KeychainStore.delete(Self.apiHashKey)
        KeychainStore.delete(Self.phoneKey)
        pendingPhone = nil
        lastError = nil
        phase = .configuring
        guard let client else {
            createClient()
            return
        }
        Task {
            do {
                _ = try await client.destroy()
            } catch {
                fail(error)
                phase = .failed(readableError(error))
            }
        }
    }

    func isRunning(_ id: UUID) -> Bool { runningBotIDs.contains(id) }

    func configureNotificationForwarding(_ appState: AppState) {
        notificationAppState = appState
    }

    func discoverBots() async throws -> [TelegramDiscoveredBot] {
        guard isReady, let client else { throw TelegramCheckinError.notAuthorized }
        let lists: [ChatList] = [.chatListMain, .chatListArchive]
        var chatIDs = Set<Int64>()
        for list in lists {
            for _ in 0..<3 {
                do {
                    _ = try await client.loadChats(chatList: list, limit: 100)
                } catch {
                    break
                }
            }
            if let chats = try? await client.getChats(chatList: list, limit: 200) {
                chatIDs.formUnion(chats.chatIds)
            }
        }

        var discovered: [TelegramDiscoveredBot] = []
        for chatID in chatIDs {
            guard let chat = try? await client.getChat(chatId: chatID),
                  case .chatTypePrivate(let privateChat) = chat.type,
                  let user = try? await client.getUser(userId: privateChat.userId),
                  case .userTypeBot(_) = user.type else { continue }
            let usernames = user.usernames
            let normalizedUsername = (
                (usernames?.activeUsernames ?? [])
                    + [usernames?.editableUsername ?? "", usernames?.secondaryUsername ?? ""]
            )
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? ""
            guard !normalizedUsername.isEmpty else { continue }
            let fullName = [user.firstName, user.lastName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            discovered.append(
                TelegramDiscoveredBot(
                    userID: user.id,
                    chatID: chat.id,
                    name: fullName.isEmpty ? chat.title : fullName,
                    username: normalizedUsername
                )
            )
        }
        return discovered.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func refreshConfiguredBots() async {
        guard isReady, let client else { return }
        for bot in TelegramCheckinStore.shared.bots {
            do {
                let chat: Chat
                if let chatID = bot.resolvedChatID {
                    chat = try await client.getChat(chatId: chatID)
                } else {
                    chat = try await client.searchPublicChat(username: bot.normalizedUsername)
                }
                TelegramCheckinStore.shared.cacheResolvedChat(
                    id: bot.id,
                    chatID: chat.id,
                    title: chat.title
                )
            } catch {
                recordAppLog(.warning, "刷新 TG Bot \(bot.displayName) 失败：\(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func run(botID: UUID, trigger: TelegramCheckinTrigger) async throws -> TelegramCheckinHistory {
        guard isReady, let client else { throw TelegramCheckinError.notAuthorized }
        guard var bot = TelegramCheckinStore.shared.bot(id: botID) else { throw TelegramCheckinError.botNotFound }
        guard !runningBotIDs.contains(botID) else { throw TelegramCheckinError.alreadyRunning }
        guard !bot.normalizedUsername.isEmpty else {
            throw TelegramCheckinError.invalidConfiguration("Bot 用户名不能为空")
        }
        guard !bot.commands.isEmpty else {
            throw TelegramCheckinError.invalidConfiguration("至少需要一条签到命令")
        }

        let startedAt = Foundation.Date()
        runningBotIDs.insert(botID)
        TelegramCheckinStore.shared.beginRun(id: botID)
        defer { runningBotIDs.remove(botID) }

        let result: (
            status: TelegramCheckinRunStatus,
            response: String,
            attempts: Int,
            steps: [TelegramCheckinStep]
        )
        do {
            bot = TelegramCheckinStore.shared.bot(id: botID) ?? bot
            result = try await executeOnce(bot: bot, trigger: trigger, client: client)
        } catch {
            TelegramCheckinStore.shared.clearResolvedChat(id: botID)
            let message = readableError(error)
            result = (
                .failure,
                message,
                1,
                [TelegramCheckinStep(
                    kind: .resolveBot,
                    status: .failure,
                    detail: "无法连接 Bot",
                    rawPayload: message
                )]
            )
        }

        guard let record = TelegramCheckinStore.shared.finishRun(
            id: botID,
            trigger: trigger,
            status: result.status,
            response: result.response,
            startedAt: startedAt,
            attempts: result.attempts,
            steps: result.steps
        ) else {
            throw TelegramCheckinError.botNotFound
        }
        return record
    }

    func runAllEnabled(trigger: TelegramCheckinTrigger = .manual) async -> [TelegramCheckinHistory] {
        var records: [TelegramCheckinHistory] = []
        let ids = TelegramCheckinStore.shared.bots.filter(\.isEnabled).map(\.id)
        for id in ids {
            if let record = try? await run(botID: id, trigger: trigger) { records.append(record) }
        }
        return records
    }

    func resumeForegroundScheduling() {
        guard isReady else { return }
        startScheduler()
        Self.scheduleBackgroundRefreshIfNeeded()
        Task { await runDueBots() }
    }

    static func scheduleBackgroundRefreshIfNeeded() {
        guard TelegramCheckinStore.shared.bots.contains(where: { $0.isEnabled && $0.scheduleEnabled }) else { return }
        let request = BGAppRefreshTaskRequest(identifier: TelegramBackgroundTaskConfiguration.identifier)
        request.earliestBeginDate = Foundation.Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            recordAppLog(.warning, "提交 TG 后台签到任务失败：\(error.localizedDescription)")
        }
    }

    func stopForegroundScheduling() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        Self.scheduleBackgroundRefreshIfNeeded()
        let work = Task { @MainActor [weak self] in
            guard let self else { return }
            if !isReady, hasSavedCredentials {
                for _ in 0..<10 where !isReady && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            await runDueBots()
        }
        task.expirationHandler = { work.cancel() }
        Task { @MainActor in
            await work.value
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }

    private func receive(_ update: Update) {
        switch update {
        case .updateAuthorizationState(let value):
            handleAuthorizationState(value.authorizationState)
        case .updateNewMessage(let value):
            handleIncomingMessage(value.message)
        case .updateMessageContent(let value):
            handleMessageContentUpdate(value)
        case .updateMessageEdited(let value):
            handleMessageEdited(value)
        default:
            break
        }
    }

    private func handleAuthorizationState(_ state: AuthorizationState) {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            if hasSavedCredentials {
                Task { await applyParametersIfPossible() }
            } else {
                phase = .needsCredentials
            }
        case .authorizationStateWaitPhoneNumber:
            phase = .needsPhone
            if let phone = pendingPhone {
                pendingPhone = nil
                Task { await submitPhone(phone) }
            }
        case .authorizationStateWaitCode:
            phase = .needsCode
        case .authorizationStateWaitPassword(let value):
            phase = .needsPassword(hint: value.passwordHint)
        case .authorizationStateReady:
            phase = .ready
            lastError = nil
            Task { await loadAccount() }
            startScheduler()
            Self.scheduleBackgroundRefreshIfNeeded()
        case .authorizationStateLoggingOut, .authorizationStateClosing:
            phase = .loggingOut
            schedulerTask?.cancel()
        case .authorizationStateClosed:
            phase = .starting
            client = nil
            schedulerTask?.cancel()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.createClient()
            }
        case .authorizationStateWaitRegistration:
            phase = .unsupported("该手机号尚未注册 Telegram，请先在 Telegram 官方客户端完成注册")
        case .authorizationStateWaitEmailAddress, .authorizationStateWaitEmailCode:
            phase = .unsupported("该账号需要先在 Telegram 官方客户端完成邮箱验证")
        case .authorizationStateWaitOtherDeviceConfirmation:
            phase = .unsupported("该账号要求在 Telegram 官方客户端确认登录")
        case .authorizationStateWaitPremiumPurchase:
            phase = .unsupported("Telegram 要求该账号先完成 Premium 登录验证")
        }
    }

    private func applyParametersIfPossible() async {
        guard !isApplyingParameters, let client,
              let apiID = Int(KeychainStore.get(Self.apiIDKey) ?? ""),
              let apiHash = KeychainStore.get(Self.apiHashKey), !apiHash.isEmpty else {
            phase = .needsCredentials
            return
        }
        isApplyingParameters = true
        phase = .configuring
        defer { isApplyingParameters = false }
        do {
            let directories = try telegramDirectories()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            _ = try await client.setTdlibParameters(
                apiHash: apiHash,
                apiId: apiID,
                applicationVersion: version,
                databaseDirectory: directories.database.path,
                databaseEncryptionKey: databaseEncryptionKey(),
                deviceModel: UIDevice.current.model,
                filesDirectory: directories.files.path,
                systemLanguageCode: Locale.current.language.languageCode?.identifier ?? "zh-Hans",
                systemVersion: UIDevice.current.systemVersion,
                useChatInfoDatabase: true,
                useFileDatabase: true,
                useMessageDatabase: true,
                useSecretChats: false,
                useTestDc: false
            )
        } catch {
            fail(error)
            phase = .failed(readableError(error))
        }
    }

    private func telegramDirectories() throws -> (database: URL, files: URL) {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw TelegramCheckinError.invalidConfiguration("无法创建 Telegram 本地目录")
        }
        var base = applicationSupport
            .appendingPathComponent("Harvest", isDirectory: true)
            .appendingPathComponent("Telegram", isDirectory: true)
            .appendingPathComponent("TDLib", isDirectory: true)
        let database = base.appendingPathComponent("Database", isDirectory: true)
        let files = base.appendingPathComponent("Files", isDirectory: true)
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
        return (database, files)
    }

    private func databaseEncryptionKey() -> Data {
        if let saved = KeychainStore.get(Self.databaseKey), let data = Data(base64Encoded: saved), !data.isEmpty {
            return data
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = Array(UUID().uuidString.utf8) + Array(UUID().uuidString.utf8)
        }
        let data = Data(bytes.prefix(32))
        KeychainStore.set(data.base64EncodedString(), for: Self.databaseKey)
        return data
    }

    private func loadAccount() async {
        guard let client else { return }
        if let user = try? await client.getMe() {
            let fullName = [user.firstName, user.lastName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            accountName = fullName.isEmpty ? "Telegram" : fullName
        }
    }

    private func executeOnce(
        bot: TelegramCheckinBot,
        trigger: TelegramCheckinTrigger,
        client: TDLibClient
    ) async throws -> (
        status: TelegramCheckinRunStatus,
        response: String,
        attempts: Int,
        steps: [TelegramCheckinStep]
    ) {
        var steps: [TelegramCheckinStep] = []
        var chatID: Int64
        if let cached = bot.resolvedChatID {
            chatID = cached
            steps.append(TelegramCheckinStep(
                kind: .resolveBot,
                status: .success,
                detail: "使用已保存会话",
                rawPayload: "chat_id: \(cached)"
            ))
        } else {
            let chat = try await client.searchPublicChat(username: bot.normalizedUsername)
            chatID = chat.id
            TelegramCheckinStore.shared.cacheResolvedChat(id: bot.id, chatID: chat.id, title: chat.title)
            steps.append(TelegramCheckinStep(
                kind: .resolveBot,
                status: .success,
                detail: "已找到 @\(bot.normalizedUsername)",
                rawPayload: "chat_id: \(chat.id)\ntitle: \(chat.title)"
            ))
        }

        guard !bot.commands.isEmpty else {
            throw TelegramCheckinError.invalidConfiguration("至少需要一条签到命令")
        }
        var status = TelegramCheckinRunStatus.success
        var responses: [String] = []
        var totalAttempts = 0
        for command in bot.commands {
            var commandResult: (
                status: TelegramCheckinRunStatus,
                response: String,
                steps: [TelegramCheckinStep]
            )?
            var commandSteps: [TelegramCheckinStep] = []
            for attempt in 0...bot.retryCount {
                totalAttempts += 1
                do {
                    let current = try await executeCommand(command, bot: bot, chatID: chatID, client: client)
                    commandSteps.append(contentsOf: current.steps)
                    commandResult = (current.status, current.response, commandSteps)
                    if current.status != .timeout || attempt == bot.retryCount { break }
                } catch {
                    if attempt == bot.retryCount {
                        let message = readableError(error)
                        commandSteps.append(TelegramCheckinStep(
                            kind: .sendCommand,
                            status: .failure,
                            detail: "指令发送失败",
                            rawPayload: "\(command)\n\(message)"
                        ))
                        commandResult = (
                            .failure,
                            message,
                            commandSteps
                        )
                        break
                    }
                    let chat = try await client.searchPublicChat(username: bot.normalizedUsername)
                    chatID = chat.id
                    TelegramCheckinStore.shared.cacheResolvedChat(
                        id: bot.id,
                        chatID: chat.id,
                        title: chat.title
                    )
                }
            }
            guard let commandResult else {
                let message = "命令 \(command) 执行失败"
                steps.append(TelegramCheckinStep(
                    kind: .sendCommand,
                    status: .failure,
                    detail: message,
                    rawPayload: command
                ))
                return (.failure, message, totalAttempts, steps)
            }
            steps.append(contentsOf: commandResult.steps)
            responses.append(
                bot.commands.count > 1 ? "\(command)：\(commandResult.response)" : commandResult.response
            )
            if commandResult.status == .failure || commandResult.status == .timeout {
                return (commandResult.status, responses.joined(separator: "\n"), totalAttempts, steps)
            }
            if commandResult.status == .success {
                steps.append(await forwardSuccessfulCheckin(
                    bot: bot,
                    command: command,
                    response: commandResult.response,
                    trigger: trigger
                ))
            }
            if commandResult.status == .unmatched { status = .unmatched }
        }
        return (status, responses.joined(separator: "\n"), totalAttempts, steps)
    }

    private func executeCommand(
        _ command: String,
        bot: TelegramCheckinBot,
        chatID: Int64,
        client: TDLibClient
    ) async throws -> (
        status: TelegramCheckinRunStatus,
        response: String,
        steps: [TelegramCheckinStep]
    ) {
        let startedAt = Foundation.Date()
        var steps: [TelegramCheckinStep] = []
        let sentMessage: Message
        do {
            sentMessage = try await sendText(command, chatID: chatID, client: client)
        } catch {
            if bot.resolvedChatID != nil {
                TelegramCheckinStore.shared.clearResolvedChat(id: bot.id)
            }
            throw error
        }
        steps.append(TelegramCheckinStep(
            kind: .sendCommand,
            status: .success,
            detail: command,
            rawPayload: "message_id: \(sentMessage.id)\ncommand: \(command)"
        ))

        guard var response = await waitForResponse(
            chatID: chatID,
            afterMessageID: sentMessage.id,
            startedAt: startedAt,
            timeoutSeconds: bot.timeoutSeconds
        ) else {
            let message = "等待 Bot 回复超时"
            steps.append(TelegramCheckinStep(
                kind: .receiveResponse,
                status: .timeout,
                detail: message
            ))
            return (.timeout, message, steps)
        }

        steps.append(TelegramCheckinStep(
            kind: .receiveResponse,
            status: .success,
            detail: response.replyMarkup == nil ? "收到 Bot 回复" : "收到交互面板",
            rawPayload: response.text
        ))

        if responseMatchesFailure(response.text, bot: bot) {
            steps.append(TelegramCheckinStep(
                kind: .parseResult,
                status: .failure,
                detail: "命中失败关键字",
                rawPayload: response.text
            ))
            return (.failure, response.text, steps)
        }
        if responseMatchesExplicitSuccess(response.text, bot: bot) {
            steps.append(TelegramCheckinStep(
                kind: .parseResult,
                status: .success,
                detail: "已识别签到成功",
                rawPayload: response.text
            ))
            return (.success, response.text, steps)
        }
        if bot.pressesPanelButton, response.replyMarkup != nil {
            guard let action = panelAction(
                from: response,
                keywords: bot.effectivePanelButtonKeywords
            ) else {
                let message = "未找到面板按钮：\(bot.effectivePanelButtonKeywords.joined(separator: "、"))"
                steps.append(TelegramCheckinStep(
                    kind: .panelAction,
                    status: .failure,
                    detail: message,
                    rawPayload: response.text
                ))
                return (.failure, message, steps)
            }
            switch action {
            case .unsupported(let title, let reason):
                let message = "无法点击「\(title)」：\(reason)"
                steps.append(TelegramCheckinStep(
                    kind: .panelAction,
                    status: .failure,
                    detail: message,
                    rawPayload: response.text
                ))
                return (.failure, message, steps)
            case .sendText, .callback:
                let actionTitle: String
                switch action {
                case .sendText(let title, _), .callback(let title, _, _): actionTitle = title
                case .unsupported: actionTitle = ""
                }
                guard let panelResponse = try await performPanelAction(
                    action,
                    panelResponse: response,
                    chatID: chatID,
                    timeoutSeconds: bot.timeoutSeconds,
                    client: client
                ) else {
                    let message = "已点击面板按钮，但等待 Bot 最终回复超时"
                    steps.append(TelegramCheckinStep(
                        kind: .panelAction,
                        status: .timeout,
                        detail: "已提交「\(actionTitle)」",
                        rawPayload: message
                    ))
                    return (.timeout, message, steps)
                }
                steps.append(TelegramCheckinStep(
                    kind: .panelAction,
                    status: .success,
                    detail: "已提交「\(actionTitle)」",
                    rawPayload: panelResponse.text
                ))
                response = panelResponse
            }
        }
        if response.text.hasPrefix("已点击面板按钮「") {
            steps.append(TelegramCheckinStep(
                kind: .parseResult,
                status: .unmatched,
                detail: "面板操作已提交，未识别最终结果",
                rawPayload: response.text
            ))
            return (.unmatched, response.text, steps)
        }
        let evaluated = evaluatedResult(response.text, bot: bot)
        steps.append(TelegramCheckinStep(
            kind: .parseResult,
            status: evaluated.status,
            detail: evaluated.status == .success ? "已识别签到成功" : "已收到回复，未命中成功关键字",
            rawPayload: evaluated.response
        ))
        return (evaluated.status, evaluated.response, steps)
    }

    private func evaluatedResult(
        _ response: String,
        bot: TelegramCheckinBot
    ) -> (status: TelegramCheckinRunStatus, response: String) {
        let normalized = response.lowercased()
        if responseMatchesFailure(response, bot: bot) {
            return (.failure, response)
        }
        if responseMatchesExplicitSuccess(response, bot: bot) {
            return (.success, response)
        }
        if bot.successKeywords.isEmpty || bot.successKeywords.contains(where: { normalized.contains($0.lowercased()) }) {
            return (.success, response)
        }
        return (.unmatched, response)
    }

    private func responseMatchesFailure(_ response: String, bot: TelegramCheckinBot) -> Bool {
        let normalized = response.lowercased()
        if bot.failureKeywords.contains(where: { normalized.contains($0.lowercased()) }) {
            return true
        }
        return ["签到失败", "操作失败", "验证失败", "未能签到", "check-in failed"]
            .contains { normalized.contains($0) }
    }

    private func responseMatchesExplicitSuccess(_ response: String, bot: TelegramCheckinBot) -> Bool {
        let normalized = response.lowercased()
        if !bot.successKeywords.isEmpty,
           bot.successKeywords.contains(where: { normalized.contains($0.lowercased()) }) {
            return true
        }
        return [
            "签到成功", "已签到", "已经签到", "今日已签", "签到完成", "打卡成功",
            "already checked in", "check-in successful", "checked in successfully"
        ].contains { normalized.contains($0) }
    }

    private func forwardSuccessfulCheckin(
        bot: TelegramCheckinBot,
        command: String,
        response: String,
        trigger: TelegramCheckinTrigger
    ) async -> TelegramCheckinStep {
        guard let appState = await authenticatedNotificationAppState() else {
            let message = "Harvest 会话不可用，未转发企业微信"
            recordAppLog(.warning, "TG 签到成功，但\(message)")
            return TelegramCheckinStep(
                kind: .forwardNotification,
                status: .failure,
                detail: message
            )
        }
        let responseText = String(response.prefix(800))
        let content = """
        Bot：\(bot.displayName)（@\(bot.normalizedUsername)）
        命令：\(command)
        结果：\(responseText)
        方式：\(trigger.label)
        时间：\(Foundation.Date().formatted(date: .abbreviated, time: .standard))
        """
        do {
            _ = try await appState.api(
                APIPath.notifyTest,
                method: .get,
                query: [
                    "title": "TG Bot 签到成功",
                    "content": content,
                    "push_type": "wechat_work_push"
                ],
                timeoutInterval: 15
            )
            recordAppLog(.info, "TG 签到成功消息已转发企业微信：\(bot.displayName)")
            return TelegramCheckinStep(
                kind: .forwardNotification,
                status: .success,
                detail: "企业微信通知已发送",
                rawPayload: content
            )
        } catch {
            let message = error.localizedDescription
            recordAppLog(.warning, "TG 签到成功消息转发企业微信失败：\(message)")
            return TelegramCheckinStep(
                kind: .forwardNotification,
                status: .failure,
                detail: "企业微信通知发送失败",
                rawPayload: message
            )
        }
    }

    private func authenticatedNotificationAppState() async -> AppState? {
        for _ in 0..<12 {
            if let appState = notificationAppState, appState.isAuthenticated { return appState }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }

    private func sendText(_ text: String, chatID: Int64, client: TDLibClient) async throws -> Message {
        let content = InputMessageContent.inputMessageText(
            InputMessageText(
                clearDraft: true,
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: text)
            )
        )
        return try await client.sendMessage(
            chatId: chatID,
            inputMessageContent: content,
            options: nil,
            replyMarkup: nil,
            replyTo: nil,
            topicId: nil
        )
    }

    private func panelAction(from response: RecentResponse, keywords: [String]) -> PanelAction? {
        guard let replyMarkup = response.replyMarkup else { return nil }
        switch replyMarkup {
        case .replyMarkupInlineKeyboard(let keyboard):
            for button in keyboard.rows.flatMap({ $0 }) where buttonMatches(button.text, keywords: keywords) {
                switch button.type {
                case .inlineKeyboardButtonTypeCallback(let callback):
                    return .callback(title: button.text, messageID: response.messageID, data: callback.data)
                case .inlineKeyboardButtonTypeCallbackWithPassword:
                    return .unsupported(title: button.text, reason: "该按钮需要再次输入 Telegram 两步验证密码")
                default:
                    return .unsupported(title: button.text, reason: "该按钮不是可自动执行的签到回调")
                }
            }
        case .replyMarkupShowKeyboard(let keyboard):
            for button in keyboard.rows.flatMap({ $0 }) where buttonMatches(button.text, keywords: keywords) {
                switch button.type {
                case .keyboardButtonTypeText:
                    return .sendText(title: button.text, text: button.text)
                default:
                    return .unsupported(title: button.text, reason: "该按钮需要人工提供额外信息")
                }
            }
        default:
            break
        }
        return nil
    }

    private func buttonMatches(_ title: String, keywords: [String]) -> Bool {
        keywords.contains { title.localizedCaseInsensitiveContains($0) }
    }

    private func performPanelAction(
        _ action: PanelAction,
        panelResponse: RecentResponse,
        chatID: Int64,
        timeoutSeconds: Int,
        client: TDLibClient
    ) async throws -> RecentResponse? {
        switch action {
        case .unsupported:
            return nil
        case .sendText(_, let text):
            let sent = try await sendText(text, chatID: chatID, client: client)
            return await waitForResponse(
                chatID: chatID,
                afterMessageID: sent.id,
                startedAt: Foundation.Date(),
                timeoutSeconds: timeoutSeconds
            )
        case .callback(let title, let messageID, let data):
            let answer = try await client.getCallbackQueryAnswer(
                chatId: chatID,
                messageId: messageID,
                payload: .callbackQueryPayloadData(CallbackQueryPayloadData(data: data))
            )
            try? await Task.sleep(nanoseconds: 450_000_000)
            if let latest = latestResponse(
                chatID: chatID,
                afterMessageID: messageID,
                acceptsSameMessageID: true,
                baseline: panelResponse,
                startedAt: panelResponse.date
            ) {
                return latest
            }
            if let refreshed = try? await client.getMessage(chatId: chatID, messageId: messageID),
               let updated = incomingResponse(for: refreshed),
               updated.text != panelResponse.text || updated.replyMarkup != panelResponse.replyMarkup {
                return updated
            }
            let answerText = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !answerText.isEmpty {
                return RecentResponse(
                    messageID: messageID,
                    date: Foundation.Date(),
                    text: answerText,
                    replyMarkup: nil
                )
            }
            if let response = await waitForResponse(
                chatID: chatID,
                afterMessageID: messageID,
                acceptsSameMessageID: true,
                baseline: panelResponse,
                startedAt: Foundation.Date(),
                timeoutSeconds: timeoutSeconds
            ) {
                return response
            }
            return RecentResponse(
                messageID: messageID,
                date: Foundation.Date(),
                text: "已点击面板按钮「\(title)」",
                replyMarkup: nil
            )
        }
    }

    private func handleIncomingMessage(_ message: Message) {
        guard !message.isOutgoing else { return }
        guard let response = incomingResponse(for: message) else { return }
        recordResponse(response, chatID: message.chatId)
    }

    private func handleMessageContentUpdate(_ update: UpdateMessageContent) {
        guard let previous = recentResponses[update.chatId]?.last(where: { $0.messageID == update.messageId }) else { return }
        let text = messageText(from: update.newContent)
        let normalizedText = text.isEmpty ? "已收到 Bot 回复" : text
        guard normalizedText != previous.text else { return }
        recordResponse(
            RecentResponse(
                messageID: update.messageId,
                date: Foundation.Date(),
                text: normalizedText,
                replyMarkup: previous.replyMarkup
            ),
            chatID: update.chatId
        )
    }

    private func handleMessageEdited(_ update: UpdateMessageEdited) {
        guard let previous = recentResponses[update.chatId]?.last(where: { $0.messageID == update.messageId }),
              previous.replyMarkup != update.replyMarkup else { return }
        recordResponse(
            RecentResponse(
                messageID: update.messageId,
                date: Foundation.Date(),
                text: previous.text,
                replyMarkup: update.replyMarkup
            ),
            chatID: update.chatId
        )
    }

    private func recordResponse(_ response: RecentResponse, chatID: Int64) {
        var recent = recentResponses[chatID] ?? []
        recent.append(response)
        recentResponses[chatID] = Array(recent.suffix(20))

        guard let match = pendingResponses
            .filter({
                $0.value.chatID == chatID
                    && (response.messageID > $0.value.afterMessageID
                        || ($0.value.acceptsSameMessageID
                            && response.messageID == $0.value.afterMessageID
                            && (response.text != $0.value.baselineText
                                || response.replyMarkup != $0.value.baselineReplyMarkup)))
                    && response.date >= $0.value.startedAt.addingTimeInterval(-2)
            })
            .min(by: { $0.value.startedAt < $1.value.startedAt }) else { return }
        finishPendingResponse(id: match.key, response: response)
    }

    private func incomingResponse(for message: Message) -> RecentResponse? {
        guard !message.isOutgoing else { return nil }
        let text = messageText(from: message.content)
        return RecentResponse(
            messageID: message.id,
            date: Foundation.Date(timeIntervalSince1970: TimeInterval(message.date)),
            text: text.isEmpty ? "已收到 Bot 回复" : text,
            replyMarkup: message.replyMarkup
        )
    }

    private func messageText(from content: MessageContent) -> String {
        switch content {
        case .messageText(let value):
            return value.text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .messagePhoto(let value):
            return value.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .messageAnimation(let value):
            return value.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .messageAudio(let value):
            return value.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .messageDocument(let value):
            return value.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .messageVideo(let value):
            return value.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return "已收到 Bot 回复"
        }
    }

    private func waitForResponse(
        chatID: Int64,
        afterMessageID: Int64,
        acceptsSameMessageID: Bool = false,
        baseline: RecentResponse? = nil,
        startedAt: Foundation.Date,
        timeoutSeconds: Int
    ) async -> RecentResponse? {
        if let recent = latestResponse(
            chatID: chatID,
            afterMessageID: afterMessageID,
            acceptsSameMessageID: acceptsSameMessageID,
            baseline: baseline,
            startedAt: startedAt
        ) {
            return recent
        }
        let pendingID = UUID()
        return await withCheckedContinuation { continuation in
            pendingResponses[pendingID] = PendingResponse(
                chatID: chatID,
                afterMessageID: afterMessageID,
                acceptsSameMessageID: acceptsSameMessageID,
                baselineText: baseline?.text,
                baselineReplyMarkup: baseline?.replyMarkup,
                startedAt: startedAt,
                continuation: continuation
            )
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(5, timeoutSeconds)) * 1_000_000_000)
                self?.finishPendingResponse(id: pendingID, response: nil)
            }
        }
    }

    private func latestResponse(
        chatID: Int64,
        afterMessageID: Int64,
        acceptsSameMessageID: Bool = false,
        baseline: RecentResponse? = nil,
        startedAt: Foundation.Date
    ) -> RecentResponse? {
        recentResponses[chatID]?.last(where: {
            ($0.messageID > afterMessageID
                || (acceptsSameMessageID
                    && $0.messageID == afterMessageID
                    && ($0.text != baseline?.text || $0.replyMarkup != baseline?.replyMarkup)))
                && $0.date >= startedAt.addingTimeInterval(-2)
        })
    }

    private func finishPendingResponse(id: UUID, response: RecentResponse?) {
        guard let pending = pendingResponses.removeValue(forKey: id) else { return }
        pending.continuation.resume(returning: response)
    }

    private func startScheduler() {
        guard schedulerTask == nil || schedulerTask?.isCancelled == true else { return }
        schedulerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.runDueBots()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func runDueBots() async {
        guard isReady else { return }
        let now = Foundation.Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let dueIDs = TelegramCheckinStore.shared.bots.filter { bot in
            guard bot.isEnabled, bot.scheduleEnabled, bot.weekdays.contains(weekday),
                  minute >= bot.scheduleMinute, !runningBotIDs.contains(bot.id) else { return false }
            guard let lastRun = bot.lastAutomaticRunAt else { return true }
            return !calendar.isDate(lastRun, inSameDayAs: now)
        }.map(\.id)

        for id in dueIDs {
            TelegramCheckinStore.shared.markAutomaticAttempt(id: id, at: now)
            _ = try? await run(botID: id, trigger: .scheduled)
        }
    }

    private func fail(_ error: Swift.Error) {
        lastError = readableError(error)
    }

    private func readableError(_ error: Swift.Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        let value = String(describing: error)
        return value.isEmpty ? "Telegram 请求失败" : value
    }
}

struct TelegramBotsPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @ObservedObject var controller: TelegramSessionController
    @ObservedObject var store: TelegramCheckinStore

    @State private var showAccount = false
    @State private var showAdd = false
    @State private var showDiscovery = false
    @State private var editingBot: TelegramCheckinBot?
    @State private var historyBot: TelegramCheckinBot?
    @State private var deletingBot: TelegramCheckinBot?

    var body: some View {
        VStack(spacing: 0) {
            accountStrip
            if store.bots.isEmpty {
                EmptyState(
                    icon: "paperplane.circle",
                    title: controller.isReady ? "还没有 TG Bot" : "Telegram 未登录",
                    detail: controller.isReady ? "添加 Bot 后即可发送签到命令" : "需要先完成 Telegram 账号授权",
                    actionTitle: controller.isReady ? "添加 TG Bot" : "登录 Telegram"
                ) {
                    if controller.isReady { showAdd = true } else { showAccount = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.bots) { bot in
                        TelegramBotCard(
                            bot: bot,
                            statistics: store.statistics(for: bot.id),
                            canRun: controller.isReady,
                            isRunning: controller.isRunning(bot.id),
                            onRun: { Task { await run(bot) } },
                            onHistory: { historyBot = bot },
                            onOpen: { openTelegram(bot) },
                            onToggle: { store.setEnabled(id: bot.id, enabled: $0) }
                        )
                        .contextMenu {
                            Button { Task { await run(bot) } } label: {
                                Label("立即签到", systemImage: "checkmark.seal")
                            }
                            .disabled(!controller.isReady || controller.isRunning(bot.id) || !bot.isEnabled)
                            Button { editingBot = bot } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            Button { historyBot = bot } label: {
                                Label("执行记录", systemImage: "clock.arrow.circlepath")
                            }
                            Button(role: .destructive) { deletingBot = bot } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { Task { await run(bot) } } label: {
                                Label("签到", systemImage: "checkmark.seal")
                            }
                            .tint(HarvestTheme.green)
                            .disabled(!controller.isReady || controller.isRunning(bot.id) || !bot.isEnabled)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { editingBot = bot } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(HarvestTheme.amber)
                            Button(role: .destructive) { deletingBot = bot } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .listRowSpacing(0)
                .contentMargins(.vertical, 3, for: .scrollContent)
                .scrollDismissesKeyboard(.immediately)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemGroupedBackground))
                .refreshable { await controller.refreshConfiguredBots() }
            }
        }
        .onAppear { controller.resumeForegroundScheduling() }
        .onDisappear { controller.stopForegroundScheduling() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            controller.resumeForegroundScheduling()
        }
        .sheet(isPresented: $showAccount) {
            TelegramAccountSheet(controller: controller)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAdd) {
            TelegramBotEditorSheet(bot: TelegramCheckinBot()) { store.saveBot($0) }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showDiscovery) {
            TelegramBotDiscoverySheet(controller: controller, store: store)
                .presentationDetents([.large])
        }
        .sheet(item: $editingBot) { bot in
            TelegramBotEditorSheet(bot: bot) { store.saveBot($0) }
                .presentationDetents([.large])
        }
        .sheet(item: $historyBot) { bot in
            TelegramBotHistorySheet(bot: bot, records: store.history(for: bot.id))
                .presentationDetents([.large])
        }
        .confirmationDialog(
            "确定删除 TG Bot「\(deletingBot?.displayName ?? "")」？",
            isPresented: Binding(get: { deletingBot != nil }, set: { if !$0 { deletingBot = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let bot = deletingBot else { return }
                store.deleteBot(id: bot.id)
                deletingBot = nil
            }
            Button("取消", role: .cancel) { deletingBot = nil }
        }
    }

    private var accountStrip: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(controller.isReady ? HarvestTheme.green : HarvestTheme.amber)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.isReady && !controller.accountName.isEmpty ? controller.accountName : controller.phase.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(store.bots.filter(\.isEnabled).count) 个启用 · \(store.bots.filter(\.scheduleEnabled).count) 个定时")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            tgActionToolbar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var tgActionToolbar: some View {
        HStack(spacing: 0) {
            Button {
                guard controller.runningBotIDs.isEmpty else { return }
                Task { await runAll() }
            } label: {
                if controller.runningBotIDs.isEmpty {
                    tgToolbarLabel(icon: "checkmark.seal.fill", title: "签到", color: HarvestTheme.green)
                } else {
                    VStack(spacing: 2) {
                        ProgressView().controlSize(.mini).tint(HarvestTheme.green)
                        Text("执行中").font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(HarvestTheme.green)
                    .frame(width: 48, height: 40)
                }
            }
            .buttonStyle(.plain)
            .disabled(!controller.isReady || store.bots.isEmpty)
            .accessibilityLabel("全部 TG Bot 签到")

            tgToolbarDivider

            Button { showAccount = true } label: {
                tgToolbarLabel(icon: "person.crop.circle.fill", title: "账号", color: HarvestTheme.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Telegram 账号")

            tgToolbarDivider

            Menu {
                Button { showAdd = true } label: {
                    Label("手动添加", systemImage: "square.and.pencil")
                }
                Button { showDiscovery = true } label: {
                    Label("自动识别 Bot", systemImage: "magnifyingglass.circle")
                }
                .disabled(!controller.isReady)
            } label: {
                tgToolbarLabel(icon: "plus", title: "添加", color: HarvestTheme.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加 TG Bot")
        }
        .frame(height: 40)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: HarvestDesignSystem.Radius.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HarvestDesignSystem.Radius.medium, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: HarvestDesignSystem.Layout.hairline)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func tgToolbarLabel(icon: String, title: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(color)
        .frame(width: 48, height: 40)
        .contentShape(Rectangle())
    }

    private var tgToolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 22)
            .accessibilityHidden(true)
    }

    private func run(_ bot: TelegramCheckinBot) async {
        let feedbackID = appState.beginManualTask("正在向 \(bot.displayName) 发送签到命令")
        do {
            let result = try await controller.run(botID: bot.id, trigger: .manual)
            appState.finishManualTask(
                feedbackID,
                success: result.status.isSuccessful,
                message: "\(bot.displayName)：\(result.response)"
            )
        } catch {
            appState.finishManualTask(
                feedbackID,
                success: false,
                message: error.localizedDescription
            )
        }
    }

    private func runAll() async {
        let enabled = store.bots.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }
        let feedbackID = appState.beginManualTask("正在执行 \(enabled.count) 个 TG Bot 签到")
        guard controller.isReady else {
            appState.finishManualTask(feedbackID, success: false, message: "请先登录 Telegram")
            return
        }
        let records = await controller.runAllEnabled()
        let succeeded = records.filter { $0.status.isSuccessful }.count
        appState.finishManualTask(
            feedbackID,
            success: succeeded == enabled.count,
            message: "TG 签到完成：成功 \(succeeded)，失败 \(max(0, enabled.count - succeeded))"
        )
    }

    private func openTelegram(_ bot: TelegramCheckinBot) {
        guard let url = URL(string: "https://t.me/\(bot.normalizedUsername)") else { return }
        openURL(url)
    }
}

private struct TelegramBotDiscoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: TelegramSessionController
    @ObservedObject var store: TelegramCheckinStore

    @State private var bots: [TelegramDiscoveredBot] = []
    @State private var selectedIDs: Set<Int64> = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var configuredUsernames: Set<String> {
        Set(store.bots.map { $0.normalizedUsername.lowercased() })
    }

    private var filteredBots: [TelegramDiscoveredBot] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return bots }
        return bots.filter {
            $0.name.localizedCaseInsensitiveContains(value)
                || $0.username.localizedCaseInsensitiveContains(value)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("正在读取 Telegram Bot")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(HarvestTheme.coral)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重新识别") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredBots.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "未识别到 Bot" : "没有匹配 Bot",
                        systemImage: "magnifyingglass"
                    )
                } else {
                    List(filteredBots) { bot in
                        Button { toggle(bot) } label: {
                            HStack(spacing: 11) {
                                ZStack {
                                    Circle().fill(HarvestTheme.blue.opacity(0.12))
                                    Image(systemName: "paperplane.fill")
                                        .foregroundStyle(HarvestTheme.blue)
                                }
                                .frame(width: 38, height: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bot.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("@\(bot.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isConfigured(bot) {
                                    Text("已添加")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: selectedIDs.contains(bot.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedIDs.contains(bot.id) ? HarvestTheme.blue : Color.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isConfigured(bot))
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "搜索 Bot")
            .navigationTitle("自动识别 Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("重新识别")
                    Button("添加 \(selectedIDs.count)") { addSelected() }
                        .disabled(selectedIDs.isEmpty)
                }
            }
            .task { await load() }
        }
    }

    private func isConfigured(_ bot: TelegramDiscoveredBot) -> Bool {
        configuredUsernames.contains(bot.username.lowercased())
    }

    private func toggle(_ bot: TelegramDiscoveredBot) {
        guard !isConfigured(bot) else { return }
        if selectedIDs.contains(bot.id) { selectedIDs.remove(bot.id) }
        else { selectedIDs.insert(bot.id) }
    }

    private func load() async {
        guard !isLoading || bots.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            bots = try await controller.discoverBots()
            selectedIDs = selectedIDs.intersection(Set(bots.map(\.id)))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func addSelected() {
        for item in bots where selectedIDs.contains(item.id) && !isConfigured(item) {
            var bot = TelegramCheckinBot()
            bot.name = item.name
            bot.username = item.username
            bot.resolvedChatID = item.chatID
            bot.resolvedTitle = item.name
            store.saveBot(bot)
        }
        dismiss()
    }
}

private struct TelegramBotCard: View {
    let bot: TelegramCheckinBot
    let statistics: TelegramCheckinCounter
    let canRun: Bool
    let isRunning: Bool
    let onRun: () -> Void
    let onHistory: () -> Void
    let onOpen: () -> Void
    let onToggle: (Bool) -> Void

    private var status: TelegramCheckinRunStatus { isRunning ? .running : bot.lastStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.white)
                    Circle().fill(HarvestTheme.blue.opacity(0.12)).padding(2)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(HarvestTheme.blue)
                    FlowingCircleBorder(color: bot.isEnabled ? HarvestTheme.blue : Color.secondary, lineWidth: 1.8)
                }
                .frame(width: 46, height: 46)
                .opacity(bot.isEnabled ? 1 : 0.55)

                VStack(alignment: .leading, spacing: 3) {
                    Text(bot.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("@\(bot.normalizedUsername)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Label(status.label, systemImage: status.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(status.color.opacity(0.10), in: Capsule())
                Toggle("", isOn: Binding(get: { bot.isEnabled }, set: onToggle))
                    .labelsHidden()
                    .controlSize(.small)
            }

            HStack(spacing: 7) {
                Label(bot.commands.joined(separator: " → "), systemImage: "terminal")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Label(bot.scheduleText, systemImage: "calendar.badge.clock")
                    .lineLimit(1)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            botStatistics

            if !bot.lastResponse.isEmpty {
                Text(bot.lastResponse)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                if let date = bot.lastRunAt {
                    Label(date.formatted(.relative(presentation: .named)), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("暂无执行记录")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: onHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("执行记录")
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                }
                .accessibilityLabel("打开 Telegram")
                Button(action: onRun) {
                    if isRunning { ProgressView().controlSize(.small) }
                    else { Image(systemName: "checkmark.seal.fill") }
                }
                .disabled(!canRun || isRunning || !bot.isEnabled)
                .accessibilityLabel("立即签到")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(HarvestTheme.blue)
        }
        .padding(11)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(status.color.opacity(0.18), lineWidth: 0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    private var botStatistics: some View {
        HStack(spacing: 0) {
            botMetric("执行", value: "\(statistics.runs)", color: HarvestTheme.blue)
            Divider().frame(height: 25)
            botMetric("成功", value: "\(statistics.successes)", color: HarvestTheme.green)
            Divider().frame(height: 25)
            botMetric(
                "失败",
                value: "\(statistics.failures + statistics.timeouts)",
                color: HarvestTheme.coral
            )
            Divider().frame(height: 25)
            botMetric(
                "成功率",
                value: "\(Int((statistics.successRate * 100).rounded()))%",
                color: statistics.successes > 0 ? HarvestTheme.green : Color.secondary
            )
        }
        .padding(.vertical, 5)
        .overlay(alignment: .top) { Divider().opacity(0.65) }
        .overlay(alignment: .bottom) { Divider().opacity(0.65) }
        .accessibilityElement(children: .combine)
    }

    private func botMetric(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TelegramAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: TelegramSessionController

    @State private var apiID = ""
    @State private var apiHash = ""
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("账号状态") {
                    Label(controller.phase.label, systemImage: controller.isReady ? "checkmark.circle.fill" : "paperplane.circle")
                        .foregroundStyle(controller.isReady ? HarvestTheme.green : HarvestTheme.blue)
                    if controller.isReady, !controller.accountName.isEmpty {
                        LabeledContent("账号", value: controller.accountName)
                    }
                    if let error = controller.lastError, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(HarvestTheme.coral)
                    }
                }

                phaseContent
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Telegram 账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                apiID = controller.savedAPIID
                phone = controller.savedPhone
            }
        }
    }

    @ViewBuilder private var phaseContent: some View {
        switch controller.phase {
        case .needsCredentials:
            Section("Telegram API") {
                TextField("API ID", text: $apiID)
                    .keyboardType(.numberPad)
                SecureField("API Hash", text: $apiHash)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("手机号（国际格式）", text: $phone)
                    .keyboardType(.phonePad)
                Button("保存并发送验证码") {
                    controller.connect(apiIDText: apiID, apiHash: apiHash, phone: phone)
                }
                Link("获取 Telegram API 凭据", destination: URL(string: "https://my.telegram.org/apps")!)
            }
        case .needsPhone:
            Section("手机号") {
                TextField("+86...", text: $phone)
                    .keyboardType(.phonePad)
                Button("发送验证码") { Task { await controller.submitPhone(phone) } }
                Button("重新配置 API 凭据", role: .destructive) {
                    controller.clearCredentialsForRetry()
                }
            }
        case .needsCode:
            Section("验证码") {
                TextField("验证码", text: $code)
                    .keyboardType(.numberPad)
                Button("验证并登录") { Task { await controller.submitCode(code) } }
                Button("重新开始登录", role: .destructive) {
                    controller.clearCredentialsForRetry()
                }
            }
        case .needsPassword(let hint):
            Section("两步验证") {
                SecureField(hint.isEmpty ? "密码" : "密码提示：\(hint)", text: $password)
                Button("验证密码") { Task { await controller.submitPassword(password) } }
                Button("重新开始登录", role: .destructive) {
                    controller.clearCredentialsForRetry()
                }
            }
        case .ready:
            Section {
                Button("退出 Telegram", role: .destructive) { Task { await controller.logOut() } }
            } footer: {
                Text("API 凭据、手机号和 TDLib 数据库密钥保存在本机钥匙串；验证码和两步验证密码不会保存。")
            }
        case .failed(let message):
            Section {
                Text(message).foregroundStyle(HarvestTheme.coral)
                Button("重新配置 API 凭据") { controller.clearCredentialsForRetry() }
            }
        case .unsupported(let message):
            Section {
                Text(message)
                Button("返回重新配置") { controller.clearCredentialsForRetry() }
            }
        case .starting, .configuring, .loggingOut:
            Section {
                HStack {
                    ProgressView()
                    Text(controller.phase.label)
                }
            }
        }
    }
}

private struct TelegramBotEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TelegramCheckinBot
    @State private var commands: [String]
    @State private var successKeywords: String
    @State private var failureKeywords: String
    @State private var automaticallyPressPanelButton: Bool
    @State private var panelButtonKeywords: String
    @State private var validationMessage: String?
    let onSave: (TelegramCheckinBot) -> Void
    private let weekdayOptions = [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]

    init(bot: TelegramCheckinBot, onSave: @escaping (TelegramCheckinBot) -> Void) {
        _draft = State(initialValue: bot)
        _commands = State(initialValue: bot.commands.isEmpty ? ["/checkin"] : bot.commands)
        _successKeywords = State(initialValue: bot.successKeywords.joined(separator: "，"))
        _failureKeywords = State(initialValue: bot.failureKeywords.joined(separator: "，"))
        _automaticallyPressPanelButton = State(initialValue: bot.pressesPanelButton)
        _panelButtonKeywords = State(initialValue: bot.effectivePanelButtonKeywords.joined(separator: "，"))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bot") {
                    TextField("名称", text: $draft.name)
                    TextField("用户名，例如 checkin_bot", text: $draft.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("启用", isOn: $draft.isEnabled)
                }

                Section {
                    ForEach(commands.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            TextField("命令 \(index + 1)", text: commandBinding(at: index))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if commands.count > 1 {
                                Button(role: .destructive) {
                                    commands.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("删除命令 \(index + 1)")
                            }
                        }
                    }
                    Button {
                        commands.append("")
                    } label: {
                        Label("增加命令", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("签到命令")
                } footer: {
                    Text("多条命令按当前顺序逐条执行，每条命令都会等待 Bot 回复。")
                }

                Section {
                    Toggle("自动点击签到按钮", isOn: $automaticallyPressPanelButton)
                    if automaticallyPressPanelButton {
                        TextField("按钮关键词，用逗号分隔", text: $panelButtonKeywords)
                    }
                } header: {
                    Text("面板签到")
                } footer: {
                    Text("收到 Bot 键盘后自动点击匹配按钮；默认匹配包含“签到”的按钮。")
                }

                Section {
                    TextField("成功关键词，用逗号分隔", text: $successKeywords)
                    TextField("失败关键词，用逗号分隔", text: $failureKeywords)
                } header: {
                    Text("结果判断")
                } footer: {
                    Text("未填写成功关键词时，收到任意回复即记为成功；失败关键词优先。")
                }

                Section("执行策略") {
                    Stepper("等待回复：\(draft.timeoutSeconds) 秒", value: $draft.timeoutSeconds, in: 5...120, step: 5)
                    Stepper("超时重试：\(draft.retryCount) 次", value: $draft.retryCount, in: 0...3)
                }

                Section {
                    Toggle("启用定时签到", isOn: $draft.scheduleEnabled)
                    if draft.scheduleEnabled {
                        DatePicker("执行时间", selection: scheduleDate, displayedComponents: .hourAndMinute)
                        HStack(spacing: 6) {
                            ForEach(weekdayOptions, id: \.0) { value, label in
                                Button {
                                    toggleWeekday(value)
                                } label: {
                                    Text(label)
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 30)
                                        .foregroundStyle(draft.weekdays.contains(value) ? Color.white : Color.primary)
                                        .background(
                                            draft.weekdays.contains(value) ? HarvestTheme.blue : Color.secondary.opacity(0.10),
                                            in: Circle()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("定时签到")
                } footer: {
                    Text("由 App 在前台检查执行；iOS 挂起或终止 App 后不能保证准时运行。")
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HarvestTheme.coral)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(draft.name.isEmpty ? "添加 TG Bot" : "编辑 TG Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
    }

    private func commandBinding(at index: Int) -> Binding<String> {
        Binding {
            commands.indices.contains(index) ? commands[index] : ""
        } set: { value in
            guard commands.indices.contains(index) else { return }
            commands[index] = value
        }
    }

    private var scheduleDate: Binding<Foundation.Date> {
        Binding {
            let hour = draft.scheduleMinute / 60
            let minute = draft.scheduleMinute % 60
            return Calendar.current.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: Foundation.Date()
            ) ?? Foundation.Date()
        } set: { date in
            let values = Calendar.current.dateComponents([.hour, .minute], from: date)
            draft.scheduleMinute = (values.hour ?? 0) * 60 + (values.minute ?? 0)
        }
    }

    private func toggleWeekday(_ value: Int) {
        if draft.weekdays.contains(value) { draft.weekdays.removeAll { $0 == value } }
        else { draft.weekdays.append(value) }
    }

    private func save() {
        let username = draft.normalizedUsername
        guard !username.isEmpty else {
            validationMessage = "请输入 Bot 用户名"
            return
        }
        let normalizedCommands = commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedCommands.isEmpty else {
            validationMessage = "至少输入一条签到命令"
            return
        }
        guard !draft.scheduleEnabled || !draft.weekdays.isEmpty else {
            validationMessage = "启用定时签到时至少选择一天"
            return
        }
        draft.username = username
        draft.command = normalizedCommands[0]
        draft.additionalCommands = normalizedCommands.count > 1 ? Array(normalizedCommands.dropFirst()) : nil
        draft.successKeywords = keywordList(successKeywords)
        draft.failureKeywords = keywordList(failureKeywords)
        draft.automaticallyPressPanelButton = automaticallyPressPanelButton
        draft.panelButtonKeywords = keywordList(panelButtonKeywords)
        if draft.scheduleEnabled { draft.isEnabled = true }
        onSave(draft)
        dismiss()
    }

    private func keywordList(_ value: String) -> [String] {
        value
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
