import Foundation

// MARK: - Convex Error Types

enum ConvexError: Error, LocalizedError {
    case authenticationFailed(String)
    case apiError(String, Int?)
    case networkError(Error)
    case decodingError(String)
    case configurationError(String)
    case invalidResponse(String)
    case notImplemented(String)
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .apiError(let message, let statusCode):
            if let code = statusCode {
                return "API error (\(code)): \(message)"
            } else {
                return "API error: \(message)"
            }
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .notImplemented(let message):
            return "Not implemented: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .authenticationFailed:
            return "Check your access token and ensure it hasn't expired"
        case .apiError(_, let statusCode):
            if statusCode == 401 {
                return "Your access token may have expired. Try reconnecting."
            } else if statusCode == 403 {
                return "Check that your token has the required permissions"
            } else if statusCode == 404 {
                return "The requested resource was not found"
            } else {
                return "Check the Convex service status and try again"
            }
        case .networkError:
            return "Check your internet connection and try again"
        case .decodingError:
            return "This may be due to an API change. Please report this issue."
        case .configurationError:
            return "Check your connection settings and deployment configuration"
        case .invalidResponse:
            return "The server returned an unexpected response format"
        case .notImplemented:
            return "This feature is not yet implemented for Convex"
        }
    }
}

// MARK: - Conversion to DatabaseError

extension ConvexError {
    var asDatabaseError: DatabaseError {
        switch self {
        case .authenticationFailed(let message):
            return .connectionFailed("Authentication failed: \(message)")
        case .apiError(let message, _):
            return .connectionFailed("API error: \(message)")
        case .networkError(let error):
            return .connectionFailed("Network error: \(error.localizedDescription)")
        case .decodingError(let message):
            return .connectionFailed("Failed to decode response: \(message)")
        case .configurationError(let message):
            return .configurationError(message)
        case .invalidResponse(let message):
            return .connectionFailed("Invalid response: \(message)")
        case .notImplemented(let message):
            return .notImplemented(message)
        }
    }
}