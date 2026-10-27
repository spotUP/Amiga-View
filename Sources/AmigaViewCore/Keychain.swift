import Foundation
import Security

/// One generic password in the login keychain, holding a single line of text.
public struct Keychain: Equatable {
    public var service: String
    public var account: String

    /// The wasabid key typed in Settings.
    public static let wasabi = Keychain(service: "com.spotup.amiga-view.wasabi", account: "wasabid")

    public init(service: String, account: String) {
        self.service = service; self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The stored text, or nil when there is no item or it is empty.
    public func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    /// Replaces the stored text. Returns the Security status on failure, nil on success.
    @discardableResult
    public func write(_ text: String) -> OSStatus? {
        let data = Data(text.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return nil }
        guard status == errSecItemNotFound else { return status }
        var q = query
        q[kSecValueData as String] = data
        let added = SecItemAdd(q as CFDictionary, nil)
        return added == errSecSuccess ? nil : added
    }

    public func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
