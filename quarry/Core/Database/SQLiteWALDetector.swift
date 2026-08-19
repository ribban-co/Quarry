import Foundation

struct SQLiteWALDetector {
    
    /// Check if a SQLite file is in WAL mode by reading the header
    /// Returns true if the file is in WAL mode (writer version 2)
    static func isInWALMode(at url: URL) -> Bool {
        do {
            let fileData = try Data(contentsOf: url)
            
            // SQLite file must be at least 100 bytes (header size)
            guard fileData.count >= 100 else {
                return false
            }
            
            // Check SQLite magic header
            let sqliteHeader = "SQLite format 3\0"
            let headerData = Data(sqliteHeader.utf8)
            guard fileData.prefix(16) == headerData else {
                return false
            }
            
            // Byte 18 contains the writer version
            // Writer version 2 = WAL mode
            // Writer version 1 = other journal modes
            let writerVersion = fileData[18]
            return writerVersion == 2
            
        } catch {
            print("Failed to read SQLite file: \(error)")
            return false
        }
    }
    
    /// Get detailed SQLite file information including WAL status
    static func getSQLiteFileInfo(at url: URL) -> SQLiteFileInfo? {
        do {
            let fileData = try Data(contentsOf: url)
            
            guard fileData.count >= 100 else {
                return nil
            }
            
            // Check SQLite magic header
            let sqliteHeader = "SQLite format 3\0"
            let headerData = Data(sqliteHeader.utf8)
            guard fileData.prefix(16) == headerData else {
                return nil
            }
            
            // Extract header information
            let pageSize = readUInt16(from: fileData, at: 16)
            let writerVersion = fileData[18]
            let readerVersion = fileData[19]
            let fileChangeCounter = readUInt32(from: fileData, at: 24)
            let databasePages = readUInt32(from: fileData, at: 28)
            let schemaCookie = readUInt32(from: fileData, at: 40)
            let schemaFormat = readUInt32(from: fileData, at: 44)
            let versionValidFor = readUInt32(from: fileData, at: 92)
            
            return SQLiteFileInfo(
                isWALMode: writerVersion == 2,
                writerVersion: writerVersion,
                readerVersion: readerVersion,
                pageSize: pageSize,
                fileChangeCounter: fileChangeCounter,
                databasePages: databasePages,
                schemaCookie: schemaCookie,
                schemaFormat: schemaFormat,
                versionValidFor: versionValidFor
            )
            
        } catch {
            print("Failed to read SQLite file: \(error)")
            return nil
        }
    }
    
    private static func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        return data.withUnsafeBytes { bytes in
            let pointer = bytes.bindMemory(to: UInt16.self)
            return CFSwapInt16BigToHost(pointer[offset / 2])
        }
    }
    
    private static func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        return data.withUnsafeBytes { bytes in
            let pointer = bytes.bindMemory(to: UInt32.self)
            return CFSwapInt32BigToHost(pointer[offset / 4])
        }
    }
}

struct SQLiteFileInfo {
    let isWALMode: Bool
    let writerVersion: UInt8
    let readerVersion: UInt8
    let pageSize: UInt16
    let fileChangeCounter: UInt32
    let databasePages: UInt32
    let schemaCookie: UInt32
    let schemaFormat: UInt32
    let versionValidFor: UInt32
    
    var journalMode: String {
        return isWALMode ? "WAL" : "Other"
    }
    
    var description: String {
        return """
        SQLite File Information:
        - Journal Mode: \(journalMode)
        - Writer Version: \(writerVersion)
        - Reader Version: \(readerVersion)
        - Page Size: \(pageSize) bytes
        - Database Pages: \(databasePages)
        - File Change Counter: \(fileChangeCounter)
        - Schema Cookie: \(schemaCookie)
        - Schema Format: \(schemaFormat)
        - Version Valid For: \(versionValidFor)
        """
    }
}