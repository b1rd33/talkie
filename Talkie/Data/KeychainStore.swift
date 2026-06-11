import Foundation
import Security

/// Generic-password Keychain wrapper. All Talkie secrets live here, never in UserDefaults.
/// @unchecked Sendable: stateless beyond the immutable service string; the Security
/// framework handles its own synchronization.
final class KeychainStore: @unchecked Sendable {
    enum Key: String {
        case openAIKey = "openai_api_key"
        case openRouterKey = "openrouter_api_key"
        case licenseKey = "license_key"
        case trialSeal = "trial_seal"
    }

    private let service: String

    init(service: String = "com.archiev.talkie") {
        self.service = service
    }

    func read(_ key: Key) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func write(_ value: String, for key: Key) -> OSStatus {
        delete(key)
        var query = baseQuery(key)
        query[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(query as CFDictionary, nil)
    }

    func delete(_ key: Key) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private func baseQuery(_ key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
