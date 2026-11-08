import Foundation

enum TelegramCheckinSchedulePolicy {
    static func isDue(
        isEnabled: Bool,
        scheduleEnabled: Bool,
        scheduleMinute: Int,
        weekdays: [Int],
        lastAutomaticRunAt: Date?,
        lastSuccessfulRunAt: Date?,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard isEnabled, scheduleEnabled,
              weekdays.contains(calendar.component(.weekday, from: now)) else { return false }
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard minute >= max(0, min(1_439, scheduleMinute)) else { return false }

        // An automatic attempt is consumed before sending. Manual success also satisfies today's schedule.
        return ![lastAutomaticRunAt, lastSuccessfulRunAt].compactMap { $0 }.contains {
            calendar.isDate($0, inSameDayAs: now)
        }
    }
}
