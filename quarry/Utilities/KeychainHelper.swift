//
//  KeychainHelper.swift
//  Quarry
//
//  Created by Fauzaan on 8/2/25.
//

import Foundation
import OSLog
import Security

final class KeychainHelper: Sendable {
    static let shared = KeychainHelper()

    /// Pre-rebrand service name. Renaming it orphans every saved connection
    /// password, so it stays until a keychain migration ships.
    private static let service = "Pluk"
    private static let logger = Logger(subsystem: "se.ribban.quarry", category: "KeychainHelper")

    private init() {}

    // MARK: - Store Password
    @discardableResult
    func store(password: String, for connectionId: String) -> Bool {
        guard let data = password.data(using: .utf8) else {
            Self.logger.error("Failed to UTF-8 encode password for '\(connectionId, privacy: .public)'")
            return false
        }

        if upsertPassword(
            data,
            for: connectionId,
            in: dataProtectionBaseQuery(for: connectionId),
            label: "data protection keychain",
            accessible: kSecAttrAccessibleAfterFirstUnlock
        ) {
            return true
        }

        Self.logger.warning(
            "Falling back to legacy keychain storage for '\(connectionId, privacy: .public)'"
        )
        return upsertPassword(
            data,
            for: connectionId,
            in: legacyBaseQuery(for: connectionId),
            label: "legacy keychain"
        )
    }

    // MARK: - Retrieve Password
    func retrieve(for connectionId: String) -> String? {
        if let password = readPassword(
            for: connectionId,
            using: dataProtectionReadQuery(for: connectionId),
            label: "data protection keychain"
        ) {
            return password
        }

        guard let password = readPassword(
            for: connectionId,
            using: legacyReadQuery(for: connectionId),
            label: "legacy keychain"
        ) else {
            return nil
        }

        if let data = password.data(using: .utf8) {
            if upsertPassword(
                data,
                for: connectionId,
                in: dataProtectionBaseQuery(for: connectionId),
                label: "data protection keychain",
                accessible: kSecAttrAccessibleAfterFirstUnlock
            ) {
                Self.logger.info(
                    "Migrated legacy keychain item '\(connectionId, privacy: .public)' on access"
                )
            } else {
                Self.logger.warning(
                    "Using legacy keychain item '\(connectionId, privacy: .public)' because migration failed"
                )
            }
        }

        return password
    }

    // MARK: - Delete Password
    @discardableResult
    func delete(for connectionId: String) -> Bool {
        let dataProtectionStatus = SecItemDelete(dataProtectionBaseQuery(for: connectionId) as CFDictionary)
        let legacyStatus = SecItemDelete(legacyBaseQuery(for: connectionId) as CFDictionary)

        logDeleteStatus(dataProtectionStatus, for: connectionId, label: "data protection keychain")
        logDeleteStatus(legacyStatus, for: connectionId, label: "legacy keychain")

        return isSuccessfulDeleteStatus(dataProtectionStatus) && isSuccessfulDeleteStatus(legacyStatus)
    }

    // MARK: - Update Password
    @discardableResult
    func update(password: String, for connectionId: String) -> Bool {
        store(password: password, for: connectionId)
    }

    // MARK: - Check if Password Exists
    func passwordExists(for connectionId: String) -> Bool {
        itemExists(dataProtectionBaseQuery(for: connectionId))
            || itemExists(legacyBaseQuery(for: connectionId))
    }

    private func dataProtectionBaseQuery(for connectionId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: connectionId,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func legacyBaseQuery(for connectionId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: connectionId,
        ]
    }

    private func dataProtectionReadQuery(for connectionId: String) -> [String: Any] {
        var query = dataProtectionBaseQuery(for: connectionId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private func legacyReadQuery(for connectionId: String) -> [String: Any] {
        var query = legacyBaseQuery(for: connectionId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    @discardableResult
    private func upsertPassword(
        _ data: Data,
        for connectionId: String,
        in baseQuery: [String: Any],
        label: String,
        accessible: CFString? = nil
    ) -> Bool {
        var addQuery = baseQuery
        if let accessible {
            addQuery[kSecAttrAccessible as String] = accessible
        }
        addQuery[kSecValueData as String] = data

        var status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributes: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        }

        if status != errSecSuccess {
            Self.logger.error(
                "Keychain store failed for '\(connectionId, privacy: .public)' in \(label, privacy: .public): \(status)"
            )
        }
        return status == errSecSuccess
    }

    private func readPassword(
        for connectionId: String,
        using query: [String: Any],
        label: String
    ) -> String? {
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                Self.logger.error(
                    "Keychain retrieve failed for '\(connectionId, privacy: .public)' in \(label, privacy: .public): \(status)"
                )
            }
            return nil
        }

        guard let data = dataTypeRef as? Data,
              let password = String(data: data, encoding: .utf8) else {
            Self.logger.error(
                "Keychain item '\(connectionId, privacy: .public)' in \(label, privacy: .public) contained invalid UTF-8"
            )
            return nil
        }
        return password
    }

    private func itemExists(_ baseQuery: [String: Any]) -> Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func logDeleteStatus(_ status: OSStatus, for connectionId: String, label: String) {
        guard !isSuccessfulDeleteStatus(status) else { return }
        Self.logger.error(
            "Keychain delete failed for '\(connectionId, privacy: .public)' in \(label, privacy: .public): \(status)"
        )
    }

    private func isSuccessfulDeleteStatus(_ status: OSStatus) -> Bool {
        status == errSecSuccess || status == errSecItemNotFound
    }
}
