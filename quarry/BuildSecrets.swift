import Foundation

enum BuildSecrets {
    static let convexOAuthClientID = value(for: "QUARRYConvexOAuthClientID")
    static let convexOAuthClientSecret = value(for: "QUARRYConvexOAuthClientSecret")

    private static func value(for key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}
