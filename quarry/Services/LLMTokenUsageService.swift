import Foundation

struct LLMTokenUsageSnapshot: Codable, Sendable, Equatable {
    let periodKey: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationInputTokens: Int
    var cacheReadInputTokens: Int

    var usedTokens: Int {
        inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens
    }

    var usedCreditCents: Double {
        SonnetTokenPricing.costCents(for: self)
    }
}

private enum SonnetTokenPricing {
    private static let tokenDenominator = 1_000_000.0
    // Claude Sonnet 4.6 standard pricing; cache write uses the 5-minute TTL rate.
    private static let inputCentsPerMillionTokens = 300.0
    private static let outputCentsPerMillionTokens = 1_500.0
    private static let cacheCreationCentsPerMillionTokens = 375.0
    private static let cacheReadCentsPerMillionTokens = 30.0

    static func costCents(for snapshot: LLMTokenUsageSnapshot) -> Double {
        costCents(
            inputTokens: snapshot.inputTokens,
            outputTokens: snapshot.outputTokens,
            cacheCreationInputTokens: snapshot.cacheCreationInputTokens,
            cacheReadInputTokens: snapshot.cacheReadInputTokens
        )
    }

    static func costCents(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheReadInputTokens: Int
    ) -> Double {
        let inputCost = Double(inputTokens) * inputCentsPerMillionTokens
        let outputCost = Double(outputTokens) * outputCentsPerMillionTokens
        let cacheCreationCost = Double(cacheCreationInputTokens) * cacheCreationCentsPerMillionTokens
        let cacheReadCost = Double(cacheReadInputTokens) * cacheReadCentsPerMillionTokens
        return (inputCost + outputCost + cacheCreationCost + cacheReadCost) / tokenDenominator
    }
}

@Observable
@MainActor
final class LLMTokenUsageService {
    static let shared = LLMTokenUsageService()

    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "llm_token_usage_v1"
    private(set) var latestSnapshot: LLMTokenUsageSnapshot

    private init() {
        latestSnapshot = Self.emptySnapshot()
        latestSnapshot = loadSnapshot(date: Date())
    }

    func currentSnapshot(date: Date = Date()) -> LLMTokenUsageSnapshot {
        let snapshot = loadSnapshot(date: date)
        updateLatestSnapshot(snapshot)
        return snapshot
    }

    @discardableResult
    func record(_ usage: LLMTokenUsage, date: Date = Date()) -> LLMTokenUsageSnapshot {
        var snapshot = loadSnapshot(date: date)
        snapshot.inputTokens += usage.inputTokens
        snapshot.outputTokens += usage.outputTokens
        snapshot.cacheCreationInputTokens += usage.cacheCreationInputTokens
        snapshot.cacheReadInputTokens += usage.cacheReadInputTokens
        persist(snapshot, forKey: storageKey(periodKey: snapshot.periodKey))
        updateLatestSnapshot(snapshot)
        return snapshot
    }

    private func loadSnapshot(date: Date) -> LLMTokenUsageSnapshot {
        let periodKey = Self.periodKey(for: date)
        let key = storageKey(periodKey: periodKey)

        if let snapshot = readSnapshot(forKey: key) {
            return snapshot
        }

        let snapshot = LLMTokenUsageSnapshot(
            periodKey: periodKey,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0
        )
        persist(snapshot, forKey: key)
        return snapshot
    }

    private func storageKey(periodKey: String) -> String {
        "\(keyPrefix).\(periodKey)"
    }

    private func readSnapshot(forKey key: String) -> LLMTokenUsageSnapshot? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? Foundation.JSONDecoder().decode(LLMTokenUsageSnapshot.self, from: data)
    }

    private func persist(_ snapshot: LLMTokenUsageSnapshot, forKey key: String) {
        guard let data = try? Foundation.JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: key)
    }

    private func updateLatestSnapshot(_ snapshot: LLMTokenUsageSnapshot) {
        guard latestSnapshot != snapshot else { return }
        latestSnapshot = snapshot
    }

    private static func periodKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let monthText = month < 10 ? "0\(month)" : "\(month)"
        return "\(year)-\(monthText)"
    }

    private static func emptySnapshot() -> LLMTokenUsageSnapshot {
        LLMTokenUsageSnapshot(
            periodKey: periodKey(for: Date()),
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0
        )
    }
}
