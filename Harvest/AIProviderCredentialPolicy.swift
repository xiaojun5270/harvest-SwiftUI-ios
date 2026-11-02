import Foundation

/// A blank edit means retain the credential held by the backend.
/// Only configuration state is retained in the UI; no provider secret is cached.
enum AIProviderCredentialPolicy {
    static func preservingSavedKey(in payload: [String: Any]) -> [String: Any] {
        var result = payload
        if let key = result["api_key"] as? String {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { result.removeValue(forKey: "api_key") }
            else { result["api_key"] = trimmed }
        } else { result.removeValue(forKey: "api_key") }
        return result
    }

    static func configuredState(in response: [String: Any], submittedKey: String? = nil,
                                previous: Bool? = nil) -> Bool? {
        for key in ["has_api_key", "hasApiKey", "api_key_configured", "apiKeyConfigured", "key_configured", "has_key"] {
            if let value = response[key] as? Bool { return value }
            if let value = response[key] as? NSNumber { return value.boolValue }
            if let value = response[key] as? String {
                if ["true", "1", "yes"].contains(value.lowercased()) { return true }
                if ["false", "0", "no"].contains(value.lowercased()) { return false }
            }
        }
        if let key = response["api_key"] as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let submittedKey, !submittedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        // An empty/redacted field without a presence flag does not prove that
        // the server has removed its stored secret.
        return previous
    }
}
