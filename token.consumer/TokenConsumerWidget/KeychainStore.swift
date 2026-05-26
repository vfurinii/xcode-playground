import Foundation
import Security

enum KeychainStore {
    static func readAdminKey() -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return ""
        }

        return sanitizeAdminKey(String(data: data, encoding: .utf8) ?? "")
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SharedSettings.appGroupIdentifier,
            kSecAttrAccount as String: SharedSettings.adminKeyAccount,
            kSecAttrAccessGroup as String: SharedSettings.keychainAccessGroup
        ]
    }

    private static func sanitizeAdminKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveCompare("Bearer") == .orderedSame {
            return ""
        }
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
