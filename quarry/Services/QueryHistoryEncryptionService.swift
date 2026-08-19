//
//  QueryHistoryEncryptionService.swift
//  Quarry
//
//  Created by Claude on 1/23/26.
//

import Foundation
import CryptoKit

struct QueryHistoryEncryptionService {
    /// Keychain account holding the random 256-bit query history key. Keeps its
    /// pre-rebrand name — renaming it discards existing query history.
    private static let keychainKeyId = "pluk.query-history-key"
    /// Prefix marking ciphertext encrypted with the Keychain-backed key.
    private static let versionPrefix = "v2:"

    /// LEGACY MIGRATION ONLY: salt for the old derived key. Entries written
    /// before the Keychain-backed key existed derive their key from the
    /// connection id stored alongside the ciphertext. Never use for new writes.
    private static let legacyAppSalt = "PlukQueryHistorySecure2026"

    private static let keyLock = NSLock()
    nonisolated(unsafe) private static var cachedKey: SymmetricKey?

    static func encrypt(query: String, connectionKeychainId: String) -> String? {
        guard !query.isEmpty else { return nil }
        guard let key = encryptionKey() else { return nil }
        guard let data = query.data(using: .utf8) else { return nil }

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else { return nil }
            return versionPrefix + combined.base64EncodedString()
        } catch {
            debugLog("Encryption failed: \(error)")
            return nil
        }
    }

    static func decrypt(encryptedQuery: String, connectionKeychainId: String) -> String? {
        guard !encryptedQuery.isEmpty else { return nil }

        if encryptedQuery.hasPrefix(versionPrefix) {
            guard let key = encryptionKey() else { return nil }
            return decrypt(base64: String(encryptedQuery.dropFirst(versionPrefix.count)), using: key)
        }

        // LEGACY MIGRATION ONLY: unprefixed ciphertext predates the
        // Keychain-backed key. Callers should persist the result of
        // reencryptLegacyEntry(encryptedQuery:connectionKeychainId:) to
        // complete migration.
        return decrypt(base64: encryptedQuery, using: legacyDerivedKey(from: connectionKeychainId))
    }

    /// Returns the entry re-encrypted under the Keychain-backed key when it is
    /// still stored under the legacy derived key, nil when no migration is
    /// needed or the entry cannot be decrypted. Callers persist the returned
    /// ciphertext in place of the old one.
    static func reencryptLegacyEntry(encryptedQuery: String, connectionKeychainId: String) -> String? {
        guard !encryptedQuery.isEmpty, !encryptedQuery.hasPrefix(versionPrefix) else { return nil }
        guard let query = decrypt(
            base64: encryptedQuery,
            using: legacyDerivedKey(from: connectionKeychainId)
        ) else { return nil }
        return encrypt(query: query, connectionKeychainId: connectionKeychainId)
    }

    private static func decrypt(base64: String, using key: SymmetricKey) -> String? {
        guard let data = Data(base64Encoded: base64) else { return nil }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            debugLog("Decryption failed: \(error)")
            return nil
        }
    }

    /// Loads the random query history key from the Keychain, generating and
    /// storing it on first use.
    private static func encryptionKey() -> SymmetricKey? {
        keyLock.lock()
        defer { keyLock.unlock() }

        if let cachedKey { return cachedKey }

        if let stored = KeychainHelper.shared.retrieve(for: keychainKeyId),
           let keyData = Data(base64Encoded: stored),
           keyData.count == 32 {
            let key = SymmetricKey(data: keyData)
            cachedKey = key
            return key
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        guard KeychainHelper.shared.store(password: keyData.base64EncodedString(), for: keychainKeyId) else {
            debugLog("Failed to store query history key in Keychain")
            return nil
        }
        cachedKey = key
        return key
    }

    /// LEGACY MIGRATION ONLY: the old derivation, kept solely to decrypt
    /// pre-migration entries.
    private static func legacyDerivedKey(from connectionKeychainId: String) -> SymmetricKey {
        let keyMaterial = connectionKeychainId + legacyAppSalt
        let hash = SHA256.hash(data: Data(keyMaterial.utf8))
        return SymmetricKey(data: hash)
    }
}
