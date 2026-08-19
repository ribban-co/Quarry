//
//  CreateEditorViewModel.swift
//  Quarry
//
//  Created by Fauzaan on 4/10/25.
//
import SwiftUI
import MongoKitten
import Observation

// MARK: - ViewModel
@Observable
class CreateEditorViewModel {
    // Dependencies
//    private let documentListModel: DocumentListModel
    
    // Observable properties
    var jsonDocument: String
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
    init(jsonDocument: String, isLoading: Bool, errorMessage: String? = nil) {
        // Initialize with a default document with a new ObjectId
             self.jsonDocument = """
             /**
             * Paste one or more documents here
             */
             {
               "_id": {
                 "$oid": "\(ObjectId())"
               }
             }
             """
    }
    
//    init(documentListModel: DocumentListModel) {
//        self.documentListModel = documentListModel
//        
//        // Initialize with a default document with a new ObjectId
//        self.jsonDocument = """
//        /** 
//        * Paste one or more documents here
//        */
//        {
//          "_id": {
//            "$oid": "\(ObjectId())"
//          }
//        }
//        """
//    }
    
    func saveDocument() async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let jsonDocumentWithoutComments = cleanupJsonInput(jsonDocument)
            
            // Attempt to parse the JSON to ensure it's valid
            guard (try? Document(fromJSON: jsonDocumentWithoutComments)) != nil else {
                throw MongoError.invalidData
            }
            
//            try await documentListModel.instance.createDocument(withDocument: document)
            isLoading = false
            return true
        } catch {
            if let mongoError = error as? MongoError {
                errorMessage = mongoError.localizedDescription
            } else {
                errorMessage = "Failed to save document: \(error.localizedDescription)"
            }
            isLoading = false
            return false
        }
    }
    
    func loadDocuments() async {
//        await documentListModel.loadDocuments()
    }
    
    func generateNewObjectId() {
        // Generate a new ObjectId
        let newObjectId = ObjectId()
        jsonDocument = """
        /** 
        * Paste one or more documents here
        */
        {
          "_id": {
            "$oid": "\(newObjectId)"
          }
        }
        """
    }
    
    // MARK: - Private Helper Methods
    /// Cleans up the JSON input by removing comment blocks and extracting valid JSON
    private func cleanupJsonInput(_ input: String) -> String {
        // Remove comment blocks (both /** ... */ and // ... style)
        var cleanedInput = input
        
        // Remove /** ... */ style comments
        let multilineCommentPattern = "/\\*\\*.*?\\*/"
        if let regex = try? NSRegularExpression(pattern: multilineCommentPattern, options: [.dotMatchesLineSeparators]) {
            cleanedInput = regex.stringByReplacingMatches(
                in: cleanedInput,
                options: [],
                range: NSRange(location: 0, length: cleanedInput.utf16.count),
                withTemplate: ""
            )
        }
        
        // Remove // ... style comments (line by line)
        var lines = cleanedInput.components(separatedBy: .newlines)
        lines = lines.map { line in
            if let range = line.range(of: "//") {
                return String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return line
        }
        
        cleanedInput = lines.joined(separator: "\n")
        
        // Trim whitespace
        cleanedInput = cleanedInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find valid JSON structure - could be an object or an array
        let trimmedInput = cleanedInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for JSON object (starts with { and ends with })
        if let objectStartRange = trimmedInput.firstIndex(of: "{"),
           let objectEndRange = trimmedInput.lastIndex(of: "}") {
            // Make sure the opening brace comes before the closing brace
            if objectStartRange < objectEndRange {
                let jsonSubstring = trimmedInput[objectStartRange...objectEndRange]
                return String(jsonSubstring)
            }
        }
        
        // Check for JSON array (starts with [ and ends with ])
        if let arrayStartRange = trimmedInput.firstIndex(of: "["),
           let arrayEndRange = trimmedInput.lastIndex(of: "]") {
            // Make sure the opening bracket comes before the closing bracket
            if arrayStartRange < arrayEndRange {
                let jsonSubstring = trimmedInput[arrayStartRange...arrayEndRange]
                return String(jsonSubstring)
            }
        }
        
        // If no valid JSON object or array found, return the cleaned input (which might still fail parsing)
        return cleanedInput
    }
}
