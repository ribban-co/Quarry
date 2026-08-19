import Foundation

enum SandboxStoreMigrationError: LocalizedError {
    case copyFailed(source: URL, destination: URL, underlying: Error)
    case destinationDirectoryFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let source, let destination, let underlying):
            return "Failed to copy \(source.path) to \(destination.path): \(underlying.localizedDescription)"
        case .destinationDirectoryFailed(let url, let underlying):
            return "Failed to create \(url.path): \(underlying.localizedDescription)"
        }
    }
}

struct SandboxStoreMigrator {
    /// Pre-rebrand bundle id. Names both the sandboxed source container and the
    /// live Application Support directory, so it stays until a store move ships.
    private static let bundleIdentifier = "doc.pluk"
    private static let migrationCompletedKey = "sandboxStoreMigration.v1.completed"
    private static let defaultsMigrationCompletedKey = "sandboxDefaultsMigration.v1.completed"
    private static let storeBaseName = "default.store"
    private static let supportDirectoryName = ".default_SUPPORT"

    static var destinationStoreURL: URL {
        destinationApplicationSupportURL.appending(path: storeBaseName)
    }

    static func migrateIfNeeded() throws {
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            debugLog("[SandboxStoreMigrator] App is sandboxed; skipping unsandboxed store migration")
            return
        }

        migrateUserDefaultsIfNeeded()

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationCompletedKey), FileManager.default.fileExists(atPath: destinationStoreURL.path) {
            debugLog("[SandboxStoreMigrator] Migration already completed")
            return
        }

        guard FileManager.default.fileExists(atPath: sourceStoreURL.path) else {
            debugLog("[SandboxStoreMigrator] No sandboxed store found at \(sourceStoreURL.path)")
            defaults.set(true, forKey: migrationCompletedKey)
            return
        }

        if FileManager.default.fileExists(atPath: destinationStoreURL.path) {
            debugLog("[SandboxStoreMigrator] Destination store already exists at \(destinationStoreURL.path); leaving it untouched")
            defaults.set(true, forKey: migrationCompletedKey)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationApplicationSupportURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw SandboxStoreMigrationError.destinationDirectoryFailed(destinationApplicationSupportURL, underlying: error)
        }

        do {
            try copyStoreFiles()
            try copySupportDirectory()
            defaults.set(true, forKey: migrationCompletedKey)
            debugLog("[SandboxStoreMigrator] Migrated sandboxed store to \(destinationStoreURL.path)")
        } catch {
            removePartialDestinationFiles()
            throw error
        }
    }

    private static var sourceContainerURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Containers")
            .appending(path: bundleIdentifier)
            .appending(path: "Data")
    }

    private static var sourceApplicationSupportURL: URL {
        sourceContainerURL
            .appending(path: "Library")
            .appending(path: "Application Support")
    }

    private static var sourceStoreURL: URL {
        sourceApplicationSupportURL.appending(path: storeBaseName)
    }

    private static var sourcePreferencesURL: URL {
        sourceContainerURL
            .appending(path: "Library")
            .appending(path: "Preferences")
            .appending(path: "\(bundleIdentifier).plist")
    }

    private static var destinationApplicationSupportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Application Support")
            .appending(path: bundleIdentifier)
    }

    private static var storeFileNames: [String] {
        [
            storeBaseName,
            "\(storeBaseName)-shm",
            "\(storeBaseName)-wal"
        ]
    }

    private static var sourceSupportDirectoryURL: URL {
        sourceApplicationSupportURL.appending(path: supportDirectoryName)
    }

    private static var destinationSupportDirectoryURL: URL {
        destinationApplicationSupportURL.appending(path: supportDirectoryName)
    }

    private static func migrateUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsMigrationCompletedKey) else {
            debugLog("[SandboxStoreMigrator] UserDefaults migration already completed")
            return
        }

        guard FileManager.default.fileExists(atPath: sourcePreferencesURL.path) else {
            debugLog("[SandboxStoreMigrator] No sandboxed UserDefaults plist found at \(sourcePreferencesURL.path)")
            defaults.set(true, forKey: defaultsMigrationCompletedKey)
            return
        }

        guard let dictionary = NSDictionary(contentsOf: sourcePreferencesURL) as? [String: Any] else {
            debugLog("[SandboxStoreMigrator] Could not read sandboxed UserDefaults plist at \(sourcePreferencesURL.path)")
            return
        }

        var migratedCount = 0
        for (key, value) in dictionary {
            guard shouldMigrateDefaultsKey(key), defaults.object(forKey: key) == nil else { continue }
            defaults.set(value, forKey: key)
            migratedCount += 1
        }

        defaults.set(true, forKey: defaultsMigrationCompletedKey)
        debugLog("[SandboxStoreMigrator] Migrated \(migratedCount) UserDefaults keys from sandboxed preferences")
    }

    private static func shouldMigrateDefaultsKey(_ key: String) -> Bool {
        !key.hasPrefix("NS") && !key.hasPrefix("Apple")
    }

    private static func copyStoreFiles() throws {
        for fileName in storeFileNames {
            let source = sourceApplicationSupportURL.appending(path: fileName)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }

            let destination = destinationApplicationSupportURL.appending(path: fileName)
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                debugLog("[SandboxStoreMigrator] Copied \(source.path) to \(destination.path)")
            } catch {
                throw SandboxStoreMigrationError.copyFailed(source: source, destination: destination, underlying: error)
            }
        }
    }

    private static func copySupportDirectory() throws {
        guard FileManager.default.fileExists(atPath: sourceSupportDirectoryURL.path) else { return }

        if FileManager.default.fileExists(atPath: destinationSupportDirectoryURL.path) {
            debugLog("[SandboxStoreMigrator] Destination support directory already exists at \(destinationSupportDirectoryURL.path); leaving it untouched")
            return
        }

        do {
            try FileManager.default.copyItem(at: sourceSupportDirectoryURL, to: destinationSupportDirectoryURL)
            debugLog("[SandboxStoreMigrator] Copied \(sourceSupportDirectoryURL.path) to \(destinationSupportDirectoryURL.path)")
        } catch {
            try? FileManager.default.removeItem(at: destinationSupportDirectoryURL)
            throw SandboxStoreMigrationError.copyFailed(
                source: sourceSupportDirectoryURL,
                destination: destinationSupportDirectoryURL,
                underlying: error
            )
        }
    }

    private static func removePartialDestinationFiles() {
        for fileName in storeFileNames {
            let destination = destinationApplicationSupportURL.appending(path: fileName)
            guard FileManager.default.fileExists(atPath: destination.path) else { continue }
            try? FileManager.default.removeItem(at: destination)
        }
    }
}
