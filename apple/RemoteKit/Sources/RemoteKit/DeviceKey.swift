import CryptoKit
import Foundation
import Security

/// The phone's own key (spec 4.1): it proves this is the phone that paired.
public protocol DeviceSigner: Sendable {
    /// DER SubjectPublicKeyInfo.
    var publicKeyDER: Data { get }
    /// An ECDSA P-256 SHA-256 signature, DER.
    func sign(_ message: Data) throws -> Data
}

extension DeviceSigner {
    public var deviceID: String { RemoteCrypto.deviceID(publicKeyDER: publicKeyDER) }
}

/// A key in memory. Tests, and the Simulator (which has no Secure Enclave).
public struct SoftwareSigner: DeviceSigner {
    let key: P256.Signing.PrivateKey
    public init(key: P256.Signing.PrivateKey = P256.Signing.PrivateKey()) { self.key = key }
    public init(pem: String) throws { key = try P256.Signing.PrivateKey(pemRepresentation: pem) }
    public var publicKeyDER: Data { key.publicKey.derRepresentation }
    public func sign(_ message: Data) throws -> Data { try key.signature(for: message).derRepresentation }
}

/// A key that never leaves the phone's Secure Enclave.
public struct SecureEnclaveSigner: DeviceSigner {
    let key: SecureEnclave.P256.Signing.PrivateKey
    public var publicKeyDER: Data { key.publicKey.derRepresentation }
    public func sign(_ message: Data) throws -> Data { try key.signature(for: message).derRepresentation }
}

/// Keeps the device key in the Keychain, this device only.
public enum DeviceKeyStore {
    static let service = "studio.tabber.spak.device-key"

    /// The device key: the Secure Enclave on a phone, a software key in the Simulator.
    public static func loadOrCreate(account: String = "default") throws -> any DeviceSigner {
        #if targetEnvironment(simulator)
        return try software(account: account)
        #else
        if SecureEnclave.isAvailable {
            if let blob = read(account: account), let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob) {
                return SecureEnclaveSigner(key: key)
            }
            let key = try SecureEnclave.P256.Signing.PrivateKey()
            try write(key.dataRepresentation, account: account)
            return SecureEnclaveSigner(key: key)
        }
        return try software(account: account)
        #endif
    }

    static func software(account: String) throws -> SoftwareSigner {
        if let raw = read(account: account + ".software"),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
            return SoftwareSigner(key: key)
        }
        let key = P256.Signing.PrivateKey()
        try write(key.rawRepresentation, account: account + ".software")
        return SoftwareSigner(key: key)
    }

    static func read(account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }

    static func write(_ data: Data, account: String) throws {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
    }

    public struct KeychainFailure: Error { public let status: OSStatus }
}
