//
//  MongoError.swift
//  Collection
//
//  Created by Fauzaan on 1/1/25.
//
enum MongoError: Error {
    case databaseNotInitialized
    case collectionNotFound
    case invalidData
    case invalidWrapper
    
    var localizedDescription: String {
        switch self {
        case .databaseNotInitialized:
            return "Database not initialized"
        case .collectionNotFound:
            return "Collection not found"
        case .invalidData:
            return "Invalid data format"
        case .invalidWrapper:
            return "Invalid wrapper"
        }
    }
}
