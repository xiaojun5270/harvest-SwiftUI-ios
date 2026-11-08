import Foundation

/// Distinguishes returning from the background from first appearance or a brief inactive scene.
struct ForegroundRecoveryState {
    private(set) var isVisible = false
    private var backgroundedAt: Date?

    mutating func appear() {
        isVisible = true
    }

    mutating func disappear() {
        isVisible = false
        backgroundedAt = nil
    }

    mutating func enterBackground(at date: Date) -> Bool {
        guard isVisible, backgroundedAt == nil else { return false }
        backgroundedAt = date
        return true
    }

    mutating func enterForeground(at date: Date) -> TimeInterval? {
        guard let backgroundedAt else { return nil }
        self.backgroundedAt = nil
        guard isVisible else { return nil }
        return max(0, date.timeIntervalSince(backgroundedAt))
    }
}

enum RealtimeTokenPolicy {
    static func needsRefresh(_ token: String, at date: Date = Date()) -> Bool {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return false }
        var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = (values["exp"] as? NSNumber)?.doubleValue
                ?? (values["exp"] as? String).flatMap(Double.init) else { return false }
        return expiry <= date.timeIntervalSince1970 + 30
    }
}
