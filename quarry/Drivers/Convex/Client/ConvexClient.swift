import Foundation

// MARK: - Convex Client

class ConvexClient {
    
    // MARK: - Properties
    
    private let accessToken: String
    private let deploymentUrl: String
    private let apiBaseURL = "https://api.convex.dev"
    private let urlSession: URLSession
    
    // MARK: - Initialization
    
    init(accessToken: String, deploymentUrl: String, urlSession: URLSession = .shared) {
        self.accessToken = accessToken
        self.deploymentUrl = deploymentUrl
        self.urlSession = urlSession
    }
    
    // MARK: - Core API Methods
    
    func executeAPIRequest(endpoint: String, method: String = "GET", body: Data? = nil) async throws -> ConvexResponse {
        let url = URL(string: "\(apiBaseURL)\(endpoint)")!
        var urlRequest = URLRequest(url: url)
        
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Quarry", forHTTPHeaderField: "User-Agent")
        
        if let body = body {
            urlRequest.httpBody = body
        }
        
        return try await performRequest(urlRequest)
    }
    
    // MARK: - Specific Operations

    func listDeployments(projectId: Int64) async throws -> [ConvexDeployment] {
        let response = try await executeAPIRequest(endpoint: "/v1/projects/\(projectId)/list_deployments")
        return try Foundation.JSONDecoder().decode([ConvexDeployment].self, from: response.rawData)
    }
    
    // MARK: - Private Helpers

    private func performRequest(_ request: URLRequest) async throws -> ConvexResponse {
        do {
            let (data, response) = try await urlSession.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    throw ConvexError.authenticationFailed("Invalid or expired access token")
                } else if httpResponse.statusCode == 403 {
                    throw ConvexError.authenticationFailed("Insufficient permissions")
                } else if httpResponse.statusCode == 404 {
                    throw ConvexError.apiError("Resource not found", httpResponse.statusCode)
                } else if httpResponse.statusCode >= 400 {
                    let errorMessage = parseErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
                    // Include response body for debugging 400+ errors
                    let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                    throw ConvexError.apiError("\(errorMessage). Response: \(responseString)", httpResponse.statusCode)
                }
            }
            
            return try ConvexResponse(data: data)
            
        } catch let error as ConvexError {
            throw error
        } catch {
            throw ConvexError.networkError(error)
        }
    }
    
    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Try common error message fields
        if let message = json["message"] as? String {
            return message
        } else if let error = json["error"] as? String {
            return error
        } else if let detail = json["detail"] as? String {
            return detail
        }
        
        return nil
    }
}

