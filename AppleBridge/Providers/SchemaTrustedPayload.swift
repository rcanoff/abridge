import Foundation

/// Helpers for mapping MCP payloads **after** Rust `inputSchema` validation.
///
/// Pure schema shape (required keys, non-empty strings, priority ranges, types) is enforced in
/// `apple_bridge_core::arg_validation` before `ProviderBridge` runs. These helpers must not
/// re-validate that shape; they only extract values for Apple frameworks. Offline unit tests that
/// call providers without MCP may receive empty defaults for missing schema-owned fields.
enum SchemaTrustedPayload {
    /// Schema-required string field (may use `non_whitespace_string` / `minLength` on the Rust side).
    /// Does **not** trim: Apple identifiers must round-trip exactly; whitespace-only values are
    /// rejected by Rust schema before the MCP hop.
    static func requiredString(_ dictionary: [String: Any], _ key: String) -> String {
        dictionary[key] as? String ?? ""
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
}
