//
//  LLMSettings.swift
//  Quarry
//

import Foundation
import Observation

/// User's BYOK configuration: which provider and model to use, and the API keys
/// backing them. Keys live in the Keychain; the rest is plain preferences.
@MainActor
@Observable
final class LLMSettings {
    static let shared = LLMSettings()

    private enum Key {
        static let provider = "llm.provider"
        static let model = "llm.model"
        /// Keychain account prefix — one entry per provider.
        static func keychain(_ provider: LLMProviderKind) -> String {
            "llm.apiKey.\(provider.rawValue)"
        }
    }

    private let defaults = UserDefaults.standard

    /// Mirrors the Keychain so views observe key changes without reading it on
    /// every redraw. Holds presence, never the secret itself.
    private(set) var configuredProviders: Set<LLMProviderKind> = []

    var provider: LLMProviderKind {
        didSet {
            guard provider != oldValue else { return }
            defaults.set(provider.rawValue, forKey: Key.provider)
            // A model id is provider-specific, so reset when switching vendors.
            model = provider.defaultModel
        }
    }

    var model: String {
        didSet {
            guard model != oldValue else { return }
            defaults.set(model, forKey: Key.model)
        }
    }

    private init() {
        let storedProvider = defaults.string(forKey: Key.provider)
            .flatMap(LLMProviderKind.init(rawValue:)) ?? .anthropic
        provider = storedProvider
        model = defaults.string(forKey: Key.model) ?? storedProvider.defaultModel
        refreshConfiguredProviders()
    }

    // MARK: - API keys

    func apiKey(for provider: LLMProviderKind) -> String? {
        KeychainHelper.shared.retrieve(for: Key.keychain(provider))
    }

    @discardableResult
    func setAPIKey(_ key: String, for provider: LLMProviderKind) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed.isEmpty
            ? KeychainHelper.shared.delete(for: Key.keychain(provider))
            : KeychainHelper.shared.store(password: trimmed, for: Key.keychain(provider))
        refreshConfiguredProviders()
        return stored
    }

    func hasAPIKey(for provider: LLMProviderKind) -> Bool {
        configuredProviders.contains(provider)
    }

    private func refreshConfiguredProviders() {
        configuredProviders = Set(
            LLMProviderKind.allCases.filter {
                KeychainHelper.shared.passwordExists(for: Key.keychain($0))
            }
        )
    }

    /// Throws rather than returning nil so providers surface a single, clear
    /// error to the user instead of a generic auth failure from the vendor.
    func requireAPIKey(for provider: LLMProviderKind) throws -> String {
        guard let key = apiKey(for: provider), !key.isEmpty else {
            throw LLMError.missingAPIKey(provider)
        }
        return key
    }
}
