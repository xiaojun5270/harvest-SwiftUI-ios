import Foundation

/// Standalone Foundation checks; no simulator, UI target or third-party runtime needed.
@main
struct AIAnswerDocumentChecks {
    static func main() {
        checkParagraphsAndHeadings()
        checkLists()
        checkCode()
        checkQuotesAndRules()
        checkTables()
        checkNumericRanges()
        checkOrdinaryText()
        checkResultDocuments()
        checkResultLocalization()
        checkProviderKeyPolicy()
        print("AI 回答、项目状态与配置回归检查通过")
    }

    private static func checkParagraphsAndHeadings() {
        let document = AIAnswerDocument("# 运维总览\n\n第一段。\n保留换行。\n\n## 二、优化建议\n\n第二段。")
        precondition(document.blocks.map(\.kind) == [.heading(1), .paragraph, .heading(2), .paragraph])
        precondition(document.blocks[1].text == "第一段。\n保留换行。")
        precondition(document.blocks[2].text == "二、优化建议")
        precondition(AIAnswerDocument("一、整体状态\n所有站点已同步。").blocks.first?.kind == .heading(2))
        precondition(AIAnswerDocument("**单下载器种子负载偏重**\n建议拆分任务。").blocks.first?.kind == .heading(3))
        precondition(AIAnswerDocument("状态报告\n===\n运行正常").blocks.first?.kind == .heading(1))
        precondition(AIAnswerDocument("第一段\r\n\r\n第二段").blocks.count == 2)
    }

    private static func checkLists() {
        let document = AIAnswerDocument("1. **调整定时任务**\n每次请求间隔 5~15 秒。\n2. 排查失效凭证\n  - 检查 Cookie\n  - 检查验证码\n\n独立说明。")
        precondition(document.blocks.count == 5)
        precondition(document.blocks[0].kind == .listItem(marker: "1.", depth: 0))
        precondition(document.blocks[0].text == "**调整定时任务**\n每次请求间隔 5~15 秒。")
        precondition(document.blocks[1].kind == .listItem(marker: "2.", depth: 0))
        precondition(document.blocks[2].kind == .listItem(marker: "•", depth: 1))
        precondition(document.blocks[4].kind == .paragraph)
    }

    private static func checkCode() {
        let source = "```swift\nlet range = \"1~2\"\n\n    # not a heading\n```\n\n后续说明。"
        let blocks = AIAnswerDocument(source).blocks
        precondition(blocks.count == 2)
        precondition(blocks[0].kind == .code(language: "swift"))
        precondition(blocks[0].text == "let range = \"1~2\"\n\n    # not a heading")
        precondition(AIAnswerDocument("~~~\n未闭合代码").blocks.first?.text == "未闭合代码")
        let longerFence = AIAnswerDocument("````text\n```\n保留短围栏\n````").blocks
        precondition(longerFence.first?.text == "```\n保留短围栏")
    }

    private static func checkQuotesAndRules() {
        let blocks = AIAnswerDocument("> 注意验证码\n> 避免重复签到\n\n---\n\n正文").blocks
        precondition(blocks.map(\.kind) == [.quote, .divider, .paragraph])
        precondition(blocks[0].text == "注意验证码\n避免重复签到")
    }

    private static func checkTables() {
        let blocks = AIAnswerDocument("| 参数 | 说明 |\n| :--- | ---: |\n| `a|b` | 上传 \\| 下载 |\n\n表格结束。").blocks
        precondition(blocks.count == 2)
        precondition(blocks[0].kind == .table)
        precondition(blocks[0].rows == [["参数", "说明"], ["`a|b`", "上传 | 下载"]])
        precondition(blocks[1].kind == .paragraph)
        precondition(AIAnswerDocument("正文 a | b\n不是分隔行").blocks.first?.kind == .paragraph)
    }

    private static func checkNumericRanges() {
        let rangeText = "新增 1~2 个下载器，控制在 2,000~3,000 以内。"
        precondition(AIAnswerDocument.inlineSource(rangeText)
            == "新增 1\\~2 个下载器，控制在 2,000\\~3,000 以内。")
        let rendered = try! AttributedString(markdown: AIAnswerDocument.inlineSource(rangeText),
                                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        precondition(String(rendered.characters) == rangeText)
        precondition(rendered.runs.allSatisfy { $0.inlinePresentationIntent?.contains(.strikethrough) != true })
        precondition(AIAnswerDocument.inlineSource("间隔 5 ~ 15 秒") == "间隔 5 \\~ 15 秒")
        precondition(AIAnswerDocument.inlineSource("~~已废弃~~ 与 `1~2`、``3~4``") == "~~已废弃~~ 与 `1~2`、``3~4``")
        precondition(AIAnswerDocument.inlineSource("已转义 1\\~2") == "已转义 1\\~2")
    }

    private static func checkOrdinaryText() {
        let source = "版本 5.1.4\n192.168.9.2\nhttps://example.com/1.2\n磁盘 #1\n未闭合 **标记"
        let blocks = AIAnswerDocument(source).blocks
        precondition(blocks.count == 1 && blocks[0].text == source)
        precondition(AIAnswerDocument("").blocks.isEmpty)
        precondition(AIAnswerDocument("\n\n").blocks.isEmpty)
        let many = AIAnswerDocument((1...500).map { "\($0). 建议内容" }.joined(separator: "\n"))
        precondition(many.blocks.count == 500)
        precondition(many.blocks.last?.kind == .listItem(marker: "500.", depth: 0))
    }

    private static func checkResultDocuments() {
        let context: [String: Any] = [
            "sites_total": 172, "sites_enabled": 169,
            "downloaders_total": 2, "downloaders_active": 1,
            "schedule_tasks": 7, "rss_feeds": 0, "rss_subscriptions": 0, "recent_results": 1
        ]
        let document = ManagementResultDocument(context)
        precondition(document.sections.count == 1)
        let fields = document.sections[0].fields
        precondition(fields.count == 8)
        precondition(fields[0].key == "sites_total" && fields[0].value == "172")
        precondition(fields.first(where: { $0.key == "downloaders_active" })?.value == "1")
        precondition(fields.first(where: { $0.key == "rss_feeds" })?.value == "0")

        let nested: [String: Any] = ["context": context, "findings": [["message": "请更新 Cookie", "code": "site_cookie"]]]
        let nestedDocument = ManagementResultDocument(nested)
        precondition(nestedDocument.sections.count == 2)
        precondition(nestedDocument.sections[0].titleKeys == ["context"])
        precondition(nestedDocument.sections[1].titleKeys == ["findings", "第 1 项"])
        precondition(nestedDocument == ManagementResultDocument(nested))
        precondition(Set(nestedDocument.sections.map(\.id)).count == nestedDocument.sections.count)

        let flags = ManagementResultDocument(["enabled": true, "disabled": false, "unknown": NSNull()])
        precondition(flags.sections[0].fields.first(where: { $0.key == "enabled" })?.value == "是")
        precondition(flags.sections[0].fields.first(where: { $0.key == "disabled" })?.value == "否")
        precondition(flags.sections[0].fields.first(where: { $0.key == "unknown" })?.value == "—")
        let privateValues = ManagementResultDocument(["api_key": "secret", "context": context])
        precondition(privateValues.sections.flatMap(\.fields).allSatisfy { $0.key != "api_key" })
        precondition(ManagementResultDocument([String: Any]()).sections.isEmpty)
        precondition(ManagementResultDocument([Any]()).isEmptyCollection)
        let strings = ManagementResultDocument(["提示一", "提示二"])
        precondition(strings.sections.map { $0.fields[0].value } == ["提示一", "提示二"])
    }

    private static func checkResultLocalization() {
        precondition(ManagementResultLocalization.fieldTitle("sites_total") == "站点总数")
        precondition(ManagementResultLocalization.fieldTitle("sitesTotal") == "站点总数")
        precondition(ManagementResultLocalization.fieldTitle("downloaders") == "下载器")
        precondition(ManagementResultLocalization.fieldTitle("downloadersActive") == "活跃下载器")
        precondition(ManagementResultLocalization.fieldTitle("RSSFeeds") == "订阅源")
        precondition(ManagementResultLocalization.fieldTitle("isRead") == "是否已读")
        precondition(ManagementResultLocalization.fieldTitle("recent_results") == "近期执行记录")
        precondition(ManagementResultLocalization.fieldTitle("第 1 项") == "第 1 项")
        precondition(ManagementResultLocalization.fieldTitle("unrecognized_backend_key") == "其他信息")
        precondition(ManagementResultLocalization.displayValue("success", for: "status") == "成功")
        precondition(ManagementResultLocalization.displayValue("warning", for: "level") == "警告")
        precondition(ManagementResultLocalization.displayValue("offline", for: "connectionStatus") == "离线")
        precondition(ManagementResultLocalization.displayValue("false", for: "enabled") == "否")
        precondition(ManagementResultLocalization.displayValue("0", for: "rss_feeds") == "0")
        precondition(ManagementResultLocalization.displayValue("1", for: "downloaders_active") == "1")
        precondition(ManagementResultLocalization.displayValue("success", for: "name") == "success")
        precondition(ManagementResultLocalization.displayValue("qBittorrent", for: "name") == "qBittorrent")
        precondition(ManagementResultLocalization.displayValue("gpt-4.1", for: "model") == "gpt-4.1")
    }

    private static func checkProviderKeyPolicy() {
        let update = AIProviderCredentialPolicy.preservingSavedKey(in: ["api_key": " \n", "model": "local-model"])
        precondition(update["api_key"] == nil)
        precondition(update["model"] as? String == "local-model")
        precondition(AIProviderCredentialPolicy.preservingSavedKey(in: ["api_key": NSNull()])["api_key"] == nil)
        let replacement = AIProviderCredentialPolicy.preservingSavedKey(in: ["api_key": " test-key \n"])
        precondition(replacement["api_key"] as? String == "test-key")
        precondition(AIProviderCredentialPolicy.configuredState(in: ["api_key": "***masked***"]) == true)
        precondition(AIProviderCredentialPolicy.configuredState(in: ["has_api_key": true]) == true)
        precondition(AIProviderCredentialPolicy.configuredState(in: ["hasApiKey": "false"], previous: true) == false)
        precondition(AIProviderCredentialPolicy.configuredState(in: ["api_key": ""]) == nil)
        precondition(AIProviderCredentialPolicy.configuredState(in: ["api_key": ""], previous: true) == true)
        precondition(AIProviderCredentialPolicy.configuredState(in: [:], submittedKey: "test-key") == true)
        precondition(AIProviderCredentialPolicy.configuredState(in: ["has_api_key": false], submittedKey: "test-key") == false)
        precondition(AIProviderCredentialPolicy.configuredState(in: [:], submittedKey: " \n") == nil)
    }
}
