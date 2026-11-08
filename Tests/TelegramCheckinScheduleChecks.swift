import Foundation

@main
struct TelegramCheckinScheduleChecks {
    static func main() {
        checkScheduledTime()
        checkRepeatedLaunches()
        checkManualSuccess()
        checkStalePendingList()
        checkNextDay()
        checkDisabledSchedules()
        checkLocalDateBoundary()
        print("TG 定时签到每日去重检查通过")
    }

    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return value
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func due(
        _ now: String,
        automatic: Date? = nil,
        success: Date? = nil,
        enabled: Bool = true,
        scheduled: Bool = true,
        weekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    ) -> Bool {
        TelegramCheckinSchedulePolicy.isDue(
            isEnabled: enabled,
            scheduleEnabled: scheduled,
            scheduleMinute: 8 * 60,
            weekdays: weekdays,
            lastAutomaticRunAt: automatic,
            lastSuccessfulRunAt: success,
            now: date(now),
            calendar: calendar
        )
    }

    private static func checkScheduledTime() {
        precondition(!due("2026-11-08T07:59:59+08:00"))
        precondition(due("2026-11-08T08:00:00+08:00"))
        precondition(due("2026-11-08T22:00:00+08:00"), "错过 8 点后可补签一次")
    }

    private static func checkRepeatedLaunches() {
        let claimedAt = date("2026-11-08T08:00:00+08:00")
        // Rehydrate the on-disk date as on an app restart, including an interrupted/failed run.
        let restoredAt = try! JSONDecoder().decode(Date.self, from: JSONEncoder().encode(claimedAt))
        for now in ["2026-11-08T08:00:01+08:00", "2026-11-08T12:00:00+08:00", "2026-11-08T23:59:59+08:00"] {
            precondition(!due(now, automatic: restoredAt), "已尝试的定时任务不能随重新打开而重复执行")
        }
    }

    private static func checkManualSuccess() {
        let success = date("2026-11-08T07:30:00+08:00")
        precondition(!due("2026-11-08T08:00:00+08:00", success: success))
        precondition(!due("2026-11-08T18:00:00+08:00", success: success))
        precondition(due("2026-11-08T08:00:00+08:00"), "手动失败且未自动执行时仍可按时签到")
        precondition(due("2026-11-09T08:00:00+08:00", success: success))
    }

    private static func checkStalePendingList() {
        let now = "2026-11-08T08:00:00+08:00"
        precondition(due(now)) // An earlier check placed Bot B in its pending list.
        let claimedByAnotherTrigger = date(now)
        precondition(!due(now, automatic: claimedByAnotherTrigger), "等待 Bot A 后必须重新检查 Bot B")
        precondition(due(now), "Bot B 的记录不能阻止尚未执行的 Bot C")
        precondition(!due(now, success: date("2026-11-08T07:59:59+08:00")))
    }

    private static func checkNextDay() {
        let automatic = date("2026-11-08T08:00:00+08:00")
        let success = date("2026-11-08T08:00:30+08:00")
        precondition(!due("2026-11-09T07:59:59+08:00", automatic: automatic, success: success))
        precondition(due("2026-11-09T08:00:00+08:00", automatic: automatic, success: success))
        precondition(!due("2026-11-09T08:00:00+08:00", automatic: automatic,
                          success: date("2026-11-09T00:00:01+08:00")), "跨午夜完成的成功签到计入完成当天")
    }

    private static func checkDisabledSchedules() {
        let now = "2026-11-08T08:00:00+08:00" // Sunday
        precondition(!due(now, enabled: false))
        precondition(!due(now, scheduled: false))
        precondition(!due(now, weekdays: []))
        precondition(!due(now, weekdays: [2, 3, 4, 5, 6]))
        precondition(due("2026-11-09T08:00:00+08:00", weekdays: [2, 3, 4, 5, 6]))
    }

    private static func checkLocalDateBoundary() {
        let lateAttempt = date("2026-11-08T23:30:00+08:00")
        precondition(due("2026-11-09T00:00:00Z", automatic: lateAttempt), "使用本机日期，而非 UTC 日期去重")
        let sameLocalDay = date("2026-11-08T23:30:00Z") // 11/9 07:30 local
        precondition(!due("2026-11-09T00:00:00Z", success: sameLocalDay))
    }
}
