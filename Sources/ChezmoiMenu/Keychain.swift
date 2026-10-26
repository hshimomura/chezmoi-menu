import Foundation
import Security
import ChezmoiCore

struct KeychainResolver: ConflictResolving {
    let model: String
    func resolve(_ conflict: Conflict) async throws -> Resolution {
        let key = try Keychain.read()
        return try await OpenAIResolver(key: key, model: model).resolve(conflict)
    }
}

enum Keychain {
    private static let service = "jp.local.ChezmoiMenu.openai"
    private static let account = "api-key"
    static func read() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service, kSecAttrAccount as String: account,
                                  kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SyncError("キーチェーンから API key を読み込めません（\(status)）。")
        }
        return value
    }
    static func save(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service, kSecAttrAccount as String: account]
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SyncError("API key を削除できません（\(status)）。") }
            return
        }
        let values: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let updated = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updated == errSecItemNotFound {
            let add = query.merging(values) { _, new in new }.merging([
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]) { _, new in new }
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw SyncError("API key を保存できません（\(status)）。") }
        } else if updated != errSecSuccess { throw SyncError("API key を更新できません（\(updated)）。") }
    }
}
