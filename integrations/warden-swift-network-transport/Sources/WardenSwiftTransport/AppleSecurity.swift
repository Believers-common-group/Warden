#if canImport(Security)
import Foundation
import Security

public struct WardenKeychainSecretStore: Sendable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    public func read() throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw WardenKeychainError.status(status)
        }
        return data
    }

    @discardableResult
    public func getOrCreateRandomSecret(byteCount: Int = 32) throws -> Data {
        if let existing = try read() {
            return existing
        }
        guard byteCount >= 16 else {
            throw WardenKeychainError.invalidSecretLength
        }

        var bytes = [UInt8](repeating: 0, count: byteCount)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else {
            throw WardenKeychainError.status(randomStatus)
        }
        let data = Data(bytes)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ]
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem,
           let existing = try read() {
            return existing
        }
        guard addStatus == errSecSuccess else {
            throw WardenKeychainError.status(addStatus)
        }
        return data
    }

    public func replace(with data: Data) throws {
        guard !data.isEmpty else { throw WardenKeychainError.invalidSecretLength }
        let match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = match
            insert[kSecValueData] = data
            insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw WardenKeychainError.status(addStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw WardenKeychainError.status(status)
        }
    }
}

public enum WardenKeychainError: Error, Sendable {
    case status(OSStatus)
    case invalidSecretLength
}
#endif

#if canImport(CryptoKit)
import CryptoKit

public extension WardenKeychainSecretStore {
    /// Returns a device-bound Ed25519 private key from Keychain, creating one
    /// when absent. The raw private key never needs to leave the application.
    @discardableResult
    func getOrCreateEd25519PrivateKey() throws -> Data {
        if let existing = try read() {
            _ = try Curve25519.Signing.PrivateKey(rawRepresentation: existing)
            return existing
        }
        let generated = Curve25519.Signing.PrivateKey().rawRepresentation
        try replace(with: generated)
        return generated
    }
}
#endif
