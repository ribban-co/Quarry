import Foundation

// MARK: - Convex Response Structure

struct ConvexResponse {
    let status: String?
    let value: Any?
    let error: String?
    let rawData: Data
    
    init(data: Data) throws {
        self.rawData = data
        
        // First check if we have any data
        guard !data.isEmpty else {
            throw ConvexError.invalidResponse("Empty response received")
        }
        
        // Try to parse as JSON with better error information
        let parsedJson: Any
        do {
            parsedJson = try JSONSerialization.jsonObject(with: data)
        } catch let jsonError {
            // Get string representation for debugging
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response as UTF-8"
            throw ConvexError.invalidResponse("Failed to parse JSON: \(jsonError.localizedDescription). Response: \(responseString)")
        }
        
        // Handle different response types
        if let jsonObject = parsedJson as? [String: Any] {
            // JSON object response
            self.status = jsonObject["status"] as? String
            self.error = jsonObject["error"] as? String
            
            // Handle different response formats
            if let status = self.status {
                // Response has status field - check for errors
                if status != "success" {
                    let errorMessage = error ?? "Unknown error occurred"
                    throw ConvexError.apiError(errorMessage, nil)
                }
                self.value = jsonObject["value"]
            } else {
                // No status field - treat the entire response as the value
                // This is common for API endpoints like token_details
                self.value = jsonObject
            }
        } else if let jsonArray = parsedJson as? [Any] {
            // JSON array response (e.g., list_deployments)
            self.status = nil
            self.error = nil
            self.value = jsonArray
        } else {
            // Other JSON types (string, number, etc.)
            self.status = nil
            self.error = nil
            self.value = parsedJson
        }
    }
    
}

// MARK: - Deployments
struct ConvexDeployment: Decodable {
    let name: String
    let createTime: Int64
    let deploymentType: String
    let projectId: Int64
    let previewIdentifier: String?
}
