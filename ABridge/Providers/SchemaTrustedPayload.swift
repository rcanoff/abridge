import Foundation

/// Helpers for mapping MCP payloads **after** Rust `inputSchema` validation.
///
/// Pure schema shape (required keys, non-empty strings, priority ranges, top-level types) is
/// enforced in `abridge_core::arg_validation` before `ProviderBridge` runs. These helpers must
/// not re-validate that shape; they only extract values for Apple frameworks. Offline unit tests
/// that call providers without MCP may receive empty defaults for missing schema-owned fields.
///
/// Nested **element** mappers (alarm entries, coordinate fields, enum strings) may still throw
/// mapping errors; top-level required keys must go through these helpers so missing/null never
/// surfaces as `must be an array` / `must be an object` dual-validation.
enum SchemaTrustedPayload {
    /// Schema-required string field (may use `non_whitespace_string` / `minLength` on the Rust side).
    /// Does **not** trim: Apple identifiers must round-trip exactly; whitespace-only values are
    /// rejected by Rust schema before the MCP hop.
    static func requiredString(_ dictionary: [String: Any], _ key: String) -> String {
        dictionary[key] as? String ?? ""
    }

    /// Schema-required array; missing / null / wrong type → `[]` (never throws).
    static func requiredArray(_ dictionary: [String: Any], _ key: String) -> [Any] {
        dictionary[key] as? [Any] ?? []
    }

    /// Schema-required object; missing / null / wrong type → `[:]` (never throws).
    static func requiredObject(_ dictionary: [String: Any], _ key: String) -> [String: Any] {
        dictionary[key] as? [String: Any] ?? [:]
    }

    /// Schema-optional string; `null` / missing → `nil`.
    static func optionalString(_ dictionary: [String: Any], _ key: String) -> String? {
        guard dictionary.keys.contains(key), !(dictionary[key] is NSNull) else {
            return nil
        }
        guard let value = dictionary[key] as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Schema-optional array; missing / null / wrong type → `nil`.
    static func optionalArray(_ dictionary: [String: Any], _ key: String) -> [Any]? {
        guard dictionary.keys.contains(key), !(dictionary[key] is NSNull) else {
            return nil
        }
        return dictionary[key] as? [Any]
    }

    /// Schema-optional object; missing / null / wrong type → `nil`.
    static func optionalObject(_ dictionary: [String: Any], _ key: String) -> [String: Any]? {
        guard dictionary.keys.contains(key), !(dictionary[key] is NSNull) else {
            return nil
        }
        return dictionary[key] as? [String: Any]
    }
}
