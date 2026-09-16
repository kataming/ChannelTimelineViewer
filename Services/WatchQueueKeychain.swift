import Foundation
import Security

/// Watch Queue V2 の端末トークンの置き場所。
///
/// トークンは「この端末がそのグループの一員である」ことの証明なので、
/// UserDefaults ではなく Keychain に置く。画面にも URL にもログにも出さない。
/// 端末から出さない（バックアップにも載せない）ため `ThisDeviceOnly` を使う。
enum WatchQueueKeychain {
    private static let service = "com.deskflowlabs.channeltimelineviewer.watchqueue"
    private static let account = "deviceToken"

    static func loadToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        // 既にあるものは消してから入れ直す（更新と新規を1本道にする）。
        SecItemDelete(baseQuery() as CFDictionary)

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func deleteToken() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
