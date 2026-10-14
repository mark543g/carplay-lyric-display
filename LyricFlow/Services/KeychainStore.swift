import Foundation
import Security

/// iOS Keychain 輕量封裝:儲存敏感憑證(Musixmatch API Key、Spotify Client ID)。
///
/// [稽核 F1 修補] 原設計將憑證明文寫入 UserDefaults,會隨未加密備份外洩;
/// 改存 Keychain 後:
/// - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:首次解鎖後才可讀取,
///   且**不隨裝置備份/移轉**,遺失或換機後需重新輸入(可接受的取捨)。
/// - 空值儲存 → 自動刪除對應項目,避免殘留空殼條目。
enum KeychainStore {

    private static let service = "com.lab.lyricflow.credentials"

    enum KeychainError: Error {
        case unhandled(OSStatus)
    }

    // MARK: - 寫入(空值 → 刪除)

    static func save(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete(forKey: key)
            return
        }
        guard let data = trimmed.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        // 先嘗試更新既有項目;不存在則新增
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            _ = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    // MARK: - 讀取

    static func load(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 刪除

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
