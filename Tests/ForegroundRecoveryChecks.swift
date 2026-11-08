import Foundation

@main
struct ForegroundRecoveryChecks {
    static func main() {
        checkFirstAppearance()
        checkLongBackground()
        checkRepeatedTransitions()
        checkHiddenPages()
        checkAppearanceInBackground()
        checkClockChange()
        checkTokenExpiry()
        print("前后台数据恢复与实时令牌检查通过")
    }

    private static let start = Date(timeIntervalSince1970: 1_794_096_000)

    private static func checkFirstAppearance() {
        var state = ForegroundRecoveryState()
        state.appear()
        precondition(state.isVisible)
        precondition(state.enterForeground(at: start) == nil, "首次进入不能重复触发恢复加载")
        // An inactive scene (control centre, permission prompt) does not enter background.
        precondition(state.enterForeground(at: start.addingTimeInterval(2)) == nil)
        state.disappear()
        state.appear()
        precondition(state.enterForeground(at: start.addingTimeInterval(5)) == nil, "切换 Dock 不触发后台恢复")
    }

    private static func checkLongBackground() {
        var state = ForegroundRecoveryState()
        state.appear()
        precondition(state.enterBackground(at: start))
        let duration = state.enterForeground(at: start.addingTimeInterval(3_600))
        precondition(duration == 3_600, "在后台超过刷新时长也必须恢复可见页面")
        precondition(state.enterForeground(at: start.addingTimeInterval(3_601)) == nil)
    }

    private static func checkRepeatedTransitions() {
        var state = ForegroundRecoveryState()
        state.appear()
        for index in 0..<20 {
            let date = start.addingTimeInterval(Double(index) * 10)
            precondition(state.enterBackground(at: date))
            precondition(!state.enterBackground(at: date.addingTimeInterval(1)), "重复后台事件只停止一次")
            precondition(state.enterForeground(at: date.addingTimeInterval(3)) == 3)
            precondition(state.enterForeground(at: date.addingTimeInterval(4)) == nil, "同一轮只恢复一次")
        }
    }

    private static func checkHiddenPages() {
        var state = ForegroundRecoveryState()
        precondition(!state.enterBackground(at: start))
        precondition(state.enterForeground(at: start.addingTimeInterval(60)) == nil)
        state.appear()
        precondition(state.enterBackground(at: start))
        state.disappear()
        precondition(!state.isVisible)
        precondition(state.enterForeground(at: start.addingTimeInterval(60)) == nil, "隐藏页面不能在恢复时重连")
        state.appear()
        precondition(state.enterForeground(at: start.addingTimeInterval(61)) == nil)
    }

    private static func checkAppearanceInBackground() {
        var state = ForegroundRecoveryState()
        state.appear()
        precondition(state.enterBackground(at: start))
        precondition(state.enterForeground(at: start.addingTimeInterval(60)) == 60)
    }

    private static func checkClockChange() {
        var state = ForegroundRecoveryState()
        state.appear()
        precondition(state.enterBackground(at: start))
        precondition(state.enterForeground(at: start.addingTimeInterval(-60)) == 0)
    }

    private static func token(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    private static func checkTokenExpiry() {
        let now = start.timeIntervalSince1970
        precondition(RealtimeTokenPolicy.needsRefresh(token(["exp": now - 3_600]), at: start))
        precondition(RealtimeTokenPolicy.needsRefresh(token(["exp": now + 30]), at: start))
        precondition(!RealtimeTokenPolicy.needsRefresh(token(["exp": now + 31]), at: start))
        precondition(!RealtimeTokenPolicy.needsRefresh(token(["exp": now + 3_600]), at: start))
        precondition(RealtimeTokenPolicy.needsRefresh(token(["exp": String(now - 1)]), at: start))
        precondition(!RealtimeTokenPolicy.needsRefresh(token(["name": "仅用于测试"]), at: start))
        precondition(!RealtimeTokenPolicy.needsRefresh("opaque-token", at: start))
        precondition(!RealtimeTokenPolicy.needsRefresh("header.invalid.signature", at: start))
        precondition(!RealtimeTokenPolicy.needsRefresh("header..signature", at: start))
    }
}
