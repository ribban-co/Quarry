//
//  SQLiteFieldsView.swift
//  Quarry
//
//  Created by Fauzaan on 8/16/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct SQLiteFieldsView: View {
    @Binding var filePath: String
    @State private var showFileImporter = false
    @State private var showBookmarkError = false
    @State private var bookmarkErrorMessage = ""
    @State private var showNoSQLiteFilesError = false
    @State private var showWALModeWarning = false
    @State private var isDropTargeted = false
    
    private var displayText: String {
        if filePath.isEmpty {
            return "No file selected - use Browse button to select SQLite database"
        } else if filePath.hasPrefix("bookmark:"),
                  let (_, path) = BookmarkManager.shared.decodeBookmark(filePath) {
            return URL(fileURLWithPath: path).relativePath
        } else {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
    }
    
    var body: some View {
        Section {
            if filePath.isEmpty {
                Button {
                    showFileImporter = true
                } label: {
                    VStack(spacing: 4) {
                        Text("Select or Drop File")
                            .foregroundStyle(.primary)

                        Text("Choose or drag a .db, .sqlite, or .sqlite3 file")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .fileSelectionStyle()
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primaryButton, lineWidth: 2)
                    }
                }
            } else {
                LabeledContent("File") {
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Text(displayText)
                            .truncationMode(.middle)
                            .lineLimit(1)

                        Button("Change") {
                            showFileImporter = true
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            handleSelectedURL(url)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.database, .item, .folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    handleSelectedURL(url)
                }
            case .failure(let error):
                print("❌ Error selecting file: \(error)")
            }
        }
        .alert("File Access Warning", isPresented: $showBookmarkError) {
            Button("OK") { }
        } message: {
            Text(bookmarkErrorMessage)
        }
        .alert("No SQLite Files Found", isPresented: $showNoSQLiteFilesError) {
            Button("OK") { }
        } message: {
            Text("No SQLite database files were found in the selected folder.\n\nPlease select a folder containing .db, .sqlite, or .sqlite3 files, or choose a specific database file instead.")
        }
        .alert("This Database Uses WAL Mode", isPresented: $showWALModeWarning) {
            Button("Select Folder Instead") {
                showFileImporter = true
            }
            Button("Cancel") { }
        } message: {
            Text("""
             This database is using Write-Ahead Logging (WAL) mode. 
             To work properly, it requires access to additional files (*.wal, *.shm).

             Please select the folder that contains this database, rather than the file itself, so all related files can be accessed.
             """)
        }
    }
    
    // MARK: - Helper Methods

    private func handleSelectedURL(_ url: URL) {
        guard url.isFileURL else { return }

        debugLog("📂 Selected file: \(url.path)")

        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        if hasSecurityScopedAccess {
            debugLog("🔓 Successfully started accessing security-scoped resource")
        }

        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        let finalURL: URL
        if isDirectory.boolValue {
            debugLog("📁 Directory selected, searching for SQLite files...")

            do {
                if let sqliteFileURL = try findFirstSQLiteFileInDirectory(url) {
                    debugLog("📁 Found SQLite file in directory: \(sqliteFileURL.lastPathComponent)")
                    finalURL = sqliteFileURL
                } else {
                    debugLog("❌ No SQLite files found in the selected folder")
                    showNoSQLiteFilesError = true
                    return
                }
            } catch {
                debugLog("❌ Error searching directory: \(error)")
                return
            }
        } else {
            if SQLiteWALDetector.isInWALMode(at: url) {
                debugLog("⚠️ SQLite file is in WAL mode, user should select directory")
                showWALModeWarning = true
                return
            }
            finalURL = url
        }

        persistSelectedSQLiteFile(
            originalURL: url,
            finalURL: finalURL,
            canCreateSecurityScopedBookmark: hasSecurityScopedAccess
        )
    }

    private func persistSelectedSQLiteFile(
        originalURL: URL,
        finalURL: URL,
        canCreateSecurityScopedBookmark: Bool
    ) {
        debugLog("📏 File exists: \(FileManager.default.fileExists(atPath: finalURL.path))")
        debugLog("📖 Readable: \(FileManager.default.isReadableFile(atPath: finalURL.path))")
        debugLog("✏️ Writable: \(FileManager.default.isWritableFile(atPath: finalURL.path))")

        do {
            let fileHandle = try FileHandle(forReadingFrom: finalURL)
            try fileHandle.close()
            debugLog("✅ File content is accessible")

            guard canCreateSecurityScopedBookmark else {
                filePath = finalURL.path
                debugLog("✅ Successfully selected SQLite file: \(finalURL.path)")
                return
            }

            let bookmarkData = try originalURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            filePath = BookmarkManager.shared.encodeBookmark(bookmarkData, withPath: finalURL.path)

            debugLog("✅ Successfully created security-scoped bookmark for: \(finalURL.path)")
        } catch {
            debugLog("⚠️ Failed to persist SQLite file access: \(error)")
            debugLog("📋 Error details: \(String(reflecting: error))")

            bookmarkErrorMessage = """
            Unable to save file access permissions.

            The selected file can be used now, but you may need to select it again after restarting the app.

            Error: \(error.localizedDescription)
            """
            showBookmarkError = true

            filePath = finalURL.path
        }
    }

    private func findFirstSQLiteFileInDirectory(_ directoryURL: URL) throws -> URL? {
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return nil
        }
        
        // Define SQLite file extensions to look for
        let sqliteExtensions = ["db", "sqlite", "sqlite3"]
        var walModeFiles: [URL] = []
        
        // First, look for files with standard SQLite extensions (prefer non-WAL)
        for fileURL in contents {
            let fileExtension = fileURL.pathExtension.lowercased()
            if sqliteExtensions.contains(fileExtension) {
                // Check if it's a file (not a directory)
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                   let isDirectory = resourceValues.isDirectory, !isDirectory {
                    // Basic SQLite file validation - check if file starts with "SQLite format 3"
                    if isSQLiteFile(at: fileURL) {
                        if SQLiteWALDetector.isInWALMode(at: fileURL) {
                            // Store WAL mode files as fallback
                            walModeFiles.append(fileURL)
                        } else {
                            // Return first non-WAL file found
                            return fileURL
                        }
                    }
                }
            }
        }
        
        // If no files with standard extensions found, look for files without extensions (prefer non-WAL)
        for fileURL in contents {
            let fileExtension = fileURL.pathExtension
            if fileExtension.isEmpty {
                // Check if it's a file (not a directory)
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                   let isDirectory = resourceValues.isDirectory, !isDirectory {
                    // Check if it's a SQLite file by examining its header
                    if isSQLiteFile(at: fileURL) {
                        if SQLiteWALDetector.isInWALMode(at: fileURL) {
                            // Store WAL mode files as fallback
                            walModeFiles.append(fileURL)
                        } else {
                            // Return first non-WAL file found
                            return fileURL
                        }
                    }
                }
            }
        }
        
        // If only WAL mode files found, return the first one
        return walModeFiles.first
    }
    
    private func isSQLiteFile(at url: URL) -> Bool {
        guard let fileData = try? Data(contentsOf: url) else {
            return false
        }
        
        // SQLite files start with "SQLite format 3\0" (16 bytes)
        let sqliteHeader = "SQLite format 3\0".data(using: .utf8)!
        
        if fileData.count >= sqliteHeader.count {
            let headerData = fileData.prefix(sqliteHeader.count)
            return headerData == sqliteHeader
        }
        
        return false
    }
}
