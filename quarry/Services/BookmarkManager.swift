import Foundation
import AppKit

final class BookmarkManager: Sendable {
    static let shared = BookmarkManager()
    
    private init() {}
    
    /// Create a security-scoped bookmark from a URL (when user picks a file)
    /// Note: The caller should already have security-scoped access started
    func createBookmark(from url: URL) throws -> Data {
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
    
    /// Resolve a security-scoped bookmark back to a URL
    func resolveBookmark(_ bookmarkData: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        
        if isStale {
            print("⚠️ Bookmark is stale, may need to re-select file")
            throw BookmarkError.staleBookmark
        }
        
        return url
    }
    
    /// Execute a block with access to a security-scoped file
    func withSecurityScopedAccess<T>(to bookmarkData: Data, execute: (URL) throws -> T) throws -> T {
        let url = try resolveBookmark(bookmarkData)
        
        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        return try execute(url)
    }
    
    /// Validate a bookmark without fully resolving it
    func validateBookmark(_ bookmarkData: Data) -> BookmarkValidationResult {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                return .stale(path: url.path)
            }
            
            // Test if we can start accessing the resource
            guard url.startAccessingSecurityScopedResource() else {
                return .inaccessible(path: url.path)
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            // Check if file actually exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .fileNotFound(path: url.path)
            }
            
            return .valid(path: url.path)
            
        } catch {
            return .invalid(error: error)
        }
    }
    
    /// Encode bookmark data as a string for storage with encrypted path
    func encodeBookmark(_ bookmarkData: Data, withPath path: String) -> String {
        let bookmarkString = bookmarkData.base64EncodedString()
        let encryptedPath = encryptPath(path)
        return "bookmark:\(bookmarkString)|\(encryptedPath)"
    }
    
    /// Decode bookmark data from a string with encrypted path
    func decodeBookmark(_ encodedString: String) -> (bookmarkData: Data, path: String)? {
        guard encodedString.hasPrefix("bookmark:") else { return nil }
        
        let bookmarkString = String(encodedString.dropFirst(9)) // Remove "bookmark:"
        let components = bookmarkString.components(separatedBy: "|")
        
        guard components.count >= 2,
              let bookmarkData = Data(base64Encoded: components[0]) else {
            return nil
        }
        
        let decryptedPath = decryptPath(components[1])
        return (bookmarkData: bookmarkData, path: decryptedPath)
    }
    
    /// Encrypt file path for secure storage
    private func encryptPath(_ path: String) -> String {
        // Simple encryption using base64 encoding with salt
        // In production, consider using proper encryption like CryptoKit
        // Pre-rebrand salt; changing it makes existing stored bookmarks unreadable.
        let salt = "PlukSecureBookmark2025"
        let saltedPath = salt + path + salt
        return saltedPath.data(using: .utf8)?.base64EncodedString() ?? path
    }
    
    /// Decrypt file path from secure storage
    private func decryptPath(_ encryptedPath: String) -> String {
        guard let data = Data(base64Encoded: encryptedPath),
              let saltedPath = String(data: data, encoding: .utf8) else {
            return encryptedPath // Fallback to original if decryption fails
        }
        
        // Pre-rebrand salt; changing it makes existing stored bookmarks unreadable.
        let salt = "PlukSecureBookmark2025"
        if saltedPath.hasPrefix(salt) && saltedPath.hasSuffix(salt) {
            let startIndex = saltedPath.index(saltedPath.startIndex, offsetBy: salt.count)
            let endIndex = saltedPath.index(saltedPath.endIndex, offsetBy: -salt.count)
            return String(saltedPath[startIndex..<endIndex])
        }
        
        return encryptedPath // Fallback if format is unexpected
    }
}

enum BookmarkValidationResult {
    case valid(path: String)
    case stale(path: String)
    case inaccessible(path: String)
    case fileNotFound(path: String)
    case invalid(error: Error)
    
    var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }
    
    var needsUserAction: Bool {
        switch self {
        case .valid:
            return false
        case .stale, .inaccessible, .fileNotFound, .invalid:
            return true
        }
    }
    
    var userMessage: String {
        switch self {
        case .valid(let path):
            return "Access to \(URL(fileURLWithPath: path).lastPathComponent) is working"
        case .stale(let path):
            return "Access to \(URL(fileURLWithPath: path).lastPathComponent) needs to be refreshed"
        case .inaccessible(let path):
            return "Cannot access \(URL(fileURLWithPath: path).lastPathComponent)"
        case .fileNotFound(let path):
            return "\(URL(fileURLWithPath: path).lastPathComponent) was not found"
        case .invalid:
            return "File access permission is corrupted"
        }
    }
}

enum BookmarkError: Error, LocalizedError {
    case accessDenied
    case invalidBookmark
    case staleBookmark
    case encryptionFailed
    case decryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to the security-scoped resource was denied"
        case .invalidBookmark:
            return "The bookmark data is invalid or corrupted"
        case .staleBookmark:
            return "The bookmark is stale and needs to be recreated. The file may have been moved or renamed."
        case .encryptionFailed:
            return "Failed to encrypt the file path for secure storage"
        case .decryptionFailed:
            return "Failed to decrypt the stored file path"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .staleBookmark:
            return "Please select the file again using the folder button to grant fresh access."
        case .accessDenied:
            return "Try selecting the file again or check that the file still exists."
        case .invalidBookmark:
            return "The stored access permission is corrupted. Please grant access again."
        case .encryptionFailed, .decryptionFailed:
            return "This is likely a temporary issue. Please try again."
        }
    }
}
