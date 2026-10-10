import Combine
import Foundation
import Security
import SwiftUI
import TDLibKit
import UIKit

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

struct TelegramCheckinBot: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var username = ""
    var command = "/checkin"
    var successKeywords: [String] = []
    var failureKeywords: [String] = []
    var isEnabled = true
    var scheduleEnabled = false
    var scheduleMinute = 8 * 60
    var weekdays = [1, 2, 3, 4, 5, 6, 7]
    var timeoutSeconds = 30
    var retryCount = 1
    var resolvedChatID: Int64?
    var resolvedTitle: String?
    var lastRunAt: Date?
    var lastAutomaticRunAt: Date?
    var lastStatus: TelegramCheckinRunStatus = .idle
    var lastResponse = ""

    var displayName: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? normalizedUsername : value
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
    let createdAt: Date
    let duration: TimeInterval
    let attemptCount: Int
}

@MainActor
final class TelegramCheckinStore: ObservableObject {
    static let shared = TelegramCheckinStore()

    @Published private(set) var bots: [TelegramCheckinBot] = []
    @Published private(set) var history: [TelegramCheckinHistory] = []

    private struct Snapshot: Codable {
        var bots: [TelegramCheckinBot]
        var history: [TelegramCheckinHistory]
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
        bot.command = bot.command.trimmingCharacters(in: .whitespacesAndNewlines)
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
    }

    func deleteBot(id: UUID) {
        bots.removeAll { $0.id == id }
        persist()
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

    func markAutomaticAttempt(id: UUID, at date: Date) {
        updateBot(id: id) { $0.lastAutomaticRunAt = date }
    }

    @discardableResult
    func finishRun(
        id: UUID,
        trigger: TelegramCheckinTrigger,
        status: TelegramCheckinRunStatus,
        response: String,
        startedAt: Date,
        attempts: Int
    ) -> TelegramCheckinHistory? {
        guard var bot = bot(id: id) else { return nil }
        let finishedAt = Date()
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
            command: bot.command,
            trigger: trigger,
            status: status,
            response: response,
            createdAt: finishedAt,
            duration: max(0, finishedAt.timeIntervalSince(startedAt)),
            attemptCount: attempts
        )
        history.insert(record, at: 0)
        if history.count > 300 { history.removeLast(history.count - 300) }
        persist()
        return record
    }

    func history(for botID: UUID) -> [TelegramCheckinHistory] {
        history.filter { $0.botID == botID }
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
    }

    private func persist() {
        guard let fileURL,
              let data = try? JSONEncoder().encode(Snapshot(bots: bots, history: history)) else { return }
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
    static let shared = TelegramSessionController()

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
        let startedAt: Date
        let continuation: CheckedContinuation<String?, Never>
    }

    private struct RecentResponse {
        let messageID: Int64
        let date: Date
        let text: String
    }

    private let manager: TDLibClientManager
    private var client: TDLibClient?
    private var isApplyingParameters = false
    private var pendingPhone: String?
    private var schedulerTask: Task<Void, Never>?
    private var pendingResponses: [UUID: PendingResponse] = [:]
    private var recentResponses: [Int64: [RecentResponse]] = [:]

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

    @discardableResult
    func run(botID: UUID, trigger: TelegramCheckinTrigger) async throws -> TelegramCheckinHistory {
        guard isReady, let client else { throw TelegramCheckinError.notAuthorized }
        guard var bot = TelegramCheckinStore.shared.bot(id: botID) else { throw TelegramCheckinError.botNotFound }
        guard !runningBotIDs.contains(botID) else { throw TelegramCheckinError.alreadyRunning }
        guard !bot.normalizedUsername.isEmpty else {
            throw TelegramCheckinError.invalidConfiguration("Bot 用户名不能为空")
        }
        guard !bot.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TelegramCheckinError.invalidConfiguration("签到命令不能为空")
        }

        let startedAt = Date()
        runningBotIDs.insert(botID)
        TelegramCheckinStore.shared.beginRun(id: botID)
        defer { runningBotIDs.remove(botID) }

        var finalStatus: TelegramCheckinRunStatus = .failure
        var finalResponse = "执行失败"
        var attempts = 0

        for attempt in 0...bot.retryCount {
            attempts = attempt + 1
            do {
                bot = TelegramCheckinStore.shared.bot(id: botID) ?? bot
                let result = try await executeOnce(bot: bot, client: client)
                finalStatus = result.status
                finalResponse = result.response
                if result.status != .timeout || attempt == bot.retryCount { break }
            } catch {
                finalStatus = .failure
                finalResponse = readableError(error)
                TelegramCheckinStore.shared.clearResolvedChat(id: botID)
                if attempt == bot.retryCount { break }
            }
        }

        guard let record = TelegramCheckinStore.shared.finishRun(
            id: botID,
            trigger: trigger,
            status: finalStatus,
            response: finalResponse,
            startedAt: startedAt,
            attempts: attempts
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
        Task { await runDueBots() }
    }

    private func receive(_ update: Update) {
        switch update {
        case .updateAuthorizationState(let value):
            handleAuthorizationState(value.authorizationState)
        case .updateNewMessage(let value):
            handleIncomingMessage(value.message)
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

    private func executeOnce(bot: TelegramCheckinBot, client: TDLibClient) async throws -> (status: TelegramCheckinRunStatus, response: String) {
        let chatID: Int64
        if let cached = bot.resolvedChatID {
            chatID = cached
        } else {
            let chat = try await client.searchPublicChat(username: bot.normalizedUsername)
            chatID = chat.id
            TelegramCheckinStore.shared.cacheResolvedChat(id: bot.id, chatID: chat.id, title: chat.title)
        }

        let startedAt = Date()
        let content = InputMessageContent.inputMessageText(
            InputMessageText(
                clearDraft: true,
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: bot.command)
            )
        )
        let sentMessage: Message
        do {
            sentMessage = try await client.sendMessage(
                chatId: chatID,
                inputMessageContent: content,
                options: nil,
                replyMarkup: nil,
                replyTo: nil,
                topicId: nil
            )
        } catch {
            if bot.resolvedChatID != nil {
                TelegramCheckinStore.shared.clearResolvedChat(id: bot.id)
            }
            throw error
        }

        guard let response = await waitForResponse(
            chatID: chatID,
            afterMessageID: sentMessage.id,
            startedAt: startedAt,
            timeoutSeconds: bot.timeoutSeconds
        ) else {
            return (.timeout, "等待 Bot 回复超时")
        }
        let normalized = response.lowercased()
        if bot.failureKeywords.contains(where: { normalized.contains($0.lowercased()) }) {
            return (.failure, response)
        }
        if bot.successKeywords.isEmpty || bot.successKeywords.contains(where: { normalized.contains($0.lowercased()) }) {
            return (.success, response)
        }
        return (.unmatched, response)
    }

    private func handleIncomingMessage(_ message: Message) {
        guard !message.isOutgoing else { return }
        let text: String
        switch message.content {
        case .messageText(let value):
            text = value.text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .messagePhoto(let value):
            text = value.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .messageAnimation(let value):
            text = value.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .messageAudio(let value):
            text = value.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .messageDocument(let value):
            text = value.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .messageVideo(let value):
            text = value.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            text = "已收到 Bot 回复"
        }
        let response = text.isEmpty ? "已收到 Bot 回复" : text
        let receivedAt = Date(timeIntervalSince1970: TimeInterval(message.date))
        var recent = recentResponses[message.chatId] ?? []
        recent.append(RecentResponse(messageID: message.id, date: receivedAt, text: response))
        recentResponses[message.chatId] = Array(recent.suffix(12))

        guard let match = pendingResponses
            .filter({
                $0.value.chatID == message.chatId
                    && message.id > $0.value.afterMessageID
                    && receivedAt >= $0.value.startedAt.addingTimeInterval(-2)
            })
            .min(by: { $0.value.startedAt < $1.value.startedAt }) else { return }
        finishPendingResponse(id: match.key, text: response)
    }

    private func waitForResponse(
        chatID: Int64,
        afterMessageID: Int64,
        startedAt: Date,
        timeoutSeconds: Int
    ) async -> String? {
        if let recent = recentResponses[chatID]?.last(where: {
            $0.messageID > afterMessageID && $0.date >= startedAt.addingTimeInterval(-2)
        }) {
            return recent.text
        }
        let pendingID = UUID()
        return await withCheckedContinuation { continuation in
            pendingResponses[pendingID] = PendingResponse(
                chatID: chatID,
                afterMessageID: afterMessageID,
                startedAt: startedAt,
                continuation: continuation
            )
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(5, timeoutSeconds)) * 1_000_000_000)
                self?.finishPendingResponse(id: pendingID, text: nil)
            }
        }
    }

    private func finishPendingResponse(id: UUID, text: String?) {
        guard let pending = pendingResponses.removeValue(forKey: id) else { return }
        pending.continuation.resume(returning: text)
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
        let now = Date()
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
                .refreshable { await runAll() }
            }
        }
        .onAppear { controller.resumeForegroundScheduling() }
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
            Spacer(minLength: 4)
            Button { Task { await runAll() } } label: {
                Image(systemName: "checkmark.seal")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .disabled(!controller.isReady || store.bots.isEmpty)
            .accessibilityLabel("全部 TG Bot 签到")
            Button { showAccount = true } label: {
                Image(systemName: "person.crop.circle.badge.gearshape")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityLabel("Telegram 账号")
            Button { showAdd = true } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityLabel("添加 TG Bot")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
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

private struct TelegramBotCard: View {
    let bot: TelegramCheckinBot
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
                Label(bot.command, systemImage: "terminal")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Label(bot.scheduleText, systemImage: "calendar.badge.clock")
                    .lineLimit(1)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

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
    @State private var successKeywords: String
    @State private var failureKeywords: String
    @State private var validationMessage: String?
    let onSave: (TelegramCheckinBot) -> Void

    private let weekdayOptions = [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]

    init(bot: TelegramCheckinBot, onSave: @escaping (TelegramCheckinBot) -> Void) {
        _draft = State(initialValue: bot)
        _successKeywords = State(initialValue: bot.successKeywords.joined(separator: "，"))
        _failureKeywords = State(initialValue: bot.failureKeywords.joined(separator: "，"))
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
                    TextField("签到命令", text: $draft.command)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("启用", isOn: $draft.isEnabled)
                }

                Section("结果判断") {
                    TextField("成功关键词，用逗号分隔", text: $successKeywords)
                    TextField("失败关键词，用逗号分隔", text: $failureKeywords)
                } footer: {
                    Text("未填写成功关键词时，收到任意回复即记为成功；失败关键词优先。")
                }

                Section("定时签到") {
                    Toggle("启用定时", isOn: $draft.scheduleEnabled)
                    if draft.scheduleEnabled {
                        DatePicker("执行时间", selection: scheduleDate, displayedComponents: .hourAndMinute)
                        HStack(spacing: 6) {
                            ForEach(weekdayOptions, id: \.0) { value, label in
                                Button {
                                    if draft.weekdays.contains(value) {
                                        draft.weekdays.removeAll { $0 == value }
                                    } else {
                                        draft.weekdays.append(value)
                                    }
                                } label: {
                                    Text(label)
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 28)
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
                } footer: {
                    Text("定时任务在 App 前台运行；iOS 挂起或终止 App 后不能保证准时执行。")
                }

                Section("执行策略") {
                    Stepper("等待回复：\(draft.timeoutSeconds) 秒", value: $draft.timeoutSeconds, in: 5...120, step: 5)
                    Stepper("超时重试：\(draft.retryCount) 次", value: $draft.retryCount, in: 0...3)
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

    private var scheduleDate: Binding<Date> {
        Binding {
            let hour = draft.scheduleMinute / 60
            let minute = draft.scheduleMinute % 60
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        } set: { date in
            let values = Calendar.current.dateComponents([.hour, .minute], from: date)
            draft.scheduleMinute = (values.hour ?? 0) * 60 + (values.minute ?? 0)
        }
    }

    private func save() {
        let username = draft.normalizedUsername
        guard !username.isEmpty else {
            validationMessage = "请输入 Bot 用户名"
            return
        }
        guard !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "请输入签到命令"
            return
        }
        guard !draft.scheduleEnabled || !draft.weekdays.isEmpty else {
            validationMessage = "定时签到至少选择一天"
            return
        }
        draft.username = username
        draft.successKeywords = keywordList(successKeywords)
        draft.failureKeywords = keywordList(failureKeywords)
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

private struct TelegramBotHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let bot: TelegramCheckinBot
    let records: [TelegramCheckinHistory]

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("暂无执行记录", systemImage: "clock.arrow.circlepath")
                } else {
                    List(records) { record in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Label(record.status.label, systemImage: record.status.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(record.status.color)
                                Spacer()
                                Text(record.trigger.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(record.response)
                                .font(.subheadline)
                                .textSelection(.enabled)
                            HStack {
                                Text(record.createdAt.formatted(date: .abbreviated, time: .standard))
                                Spacer()
                                Text(String(format: "%.1f 秒 · %d 次", record.duration, record.attemptCount))
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(bot.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
