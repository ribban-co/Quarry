//
//  ConvexFieldsView.swift
//  Quarry
//
//  Created by Fauzaan on 1/31/25.
//

import SwiftUI
import CryptoKit
import SwiftData

struct ConvexHelpSheet: View {
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Text("Convex Connection Setup")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                
                Text("Follow these steps to connect your Convex project")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            // Instructions
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Text("1.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Get your Deployment URL")
                            .font(.system(size: 14, weight: .medium))
                        Text("Found in your Convex dashboard under Settings → URL")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Text("2.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Generate an API Key")
                            .font(.system(size: 14, weight: .medium))
                        Text("Go to Settings → API Keys and create a new key")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Text("3.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Information")
                            .font(.system(size: 14, weight: .medium))
                        Text("Note your project name and team ID from the dashboard")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            // Action Button
            HStack {
                Spacer()
                
                Button("Got it") {
                    onDismiss()
                }
                .primaryStyle()
                .frame(width: 120)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 480)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
}

struct ConvexScopeInfoSheet: View {
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Text("Convex Authorization Scopes")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                
                Text("Choose the right authorization scope for your needs")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            // Scope descriptions
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "building.2")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        Text("Team Scope")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    Text("• Create new projects within the team")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("• Create deployments in any project")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("• Read and write access to all team projects")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.green)
                            .frame(width: 20)
                        Text("Project Scope")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    Text("• Access to a specific project only")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("• Create deployments within that project")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("• Read and write data and functions in that project")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.brand)
                    Text("Token permissions are limited by the authorizing member's permissions. If the member is removed or their permissions change, the token permissions will also change.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.brand.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal, 24)
            
            // Action Button
            HStack {
                Spacer()
                
                Button("Got it") {
                    onDismiss()
                }
                .primaryStyle()
                .frame(width: 120)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 520)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
}

struct ConvexOAuthView: View {
    @Binding var selectedDatabaseType: DatabaseType?
    @Binding var convexAccessToken: String
    var dismiss: DismissAction
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isAuthorizationLoading: Bool = false
    @State private var authorizationError: String?
    @State private var authorizationCode: String?
    @State private var arrowPulse: Bool = false
    @State private var callbackObserver: NSObjectProtocol?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SheetChromeButton(systemImage: "chevron.left") {
                    selectedDatabaseType = nil
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 4)
            
            VStack(spacing: 40) {
                if convexAccessToken.isEmpty {
                    // Setup state - show arrow and smaller icons
                    HStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#DF5719"))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Circle()
                                        .stroke(.separator, lineWidth: 1)
                                )

                            Image(systemName: "square.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .offset(x: -4, y: 4)
                        }
                        
                        // Connection Arrow
                        ZStack {
                            if arrowPulse {
                                // Single pulse animation
                                Circle()
                                    .fill(.secondary.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .scaleEffect(1.5)
                                    .opacity(0)
                                    .animation(.easeOut(duration: 0.8), value: arrowPulse)
                            }
                            
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                                .scaleEffect(arrowPulse ? 1.3 : 1.0)
                                .animation(.easeOut(duration: 0.3), value: arrowPulse)
                        }
                        .transition(.scale.combined(with: .opacity))
                        
                        // Convex Icon (spinner/loading icon)
                        ZStack {
                            Circle()
                                .fill(.clear)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Circle()
                                        .stroke(.separator, lineWidth: 1)
                                )
                            
                            Image("convex")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 1.2).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        )
                    )
                }
                
                VStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect Convex to Quarry")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("Quarry will be able to create deployments, manage your project, and read or write data in any deployment.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 350, alignment: .leading)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("What happens next")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "globe")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text("You'll be redirected to Convex in your browser")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.shield")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text("Complete the authorization process")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Image(systemName: "arrow.uturn.left")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text("Return here to finish setting up your connection")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .frame(maxWidth: 320)

                    // Error display
                    if let error = authorizationError {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                            
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                    }
                    
                    HStack(spacing: 8) {
                        Button {
                            selectedDatabaseType = nil
                        } label: {
                            Text("Cancel")
                                .frame(minWidth: 80)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.extraLarge)
                        .buttonBorderShape(.capsule)

                        Button {
                            authorizationError = nil
                            openConvexOAuthInBrowser()
                        } label: {
                            Text(isAuthorizationLoading ? "Opening Convex…" : "Authorize")
                                .frame(minWidth: 80)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        .tint(Color.primaryButton)
                        .buttonBorderShape(.capsule)
                        .disabled(isAuthorizationLoading)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 42)
            .frame(maxWidth: 460)
        }
        .onAppear {
            callbackObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ConvexOAuthCallback"),
                object: nil,
                queue: .main
            ) { notification in
                if let code = notification.userInfo?["code"] as? String {
                    Task {
                        do {
                            try await exchangeCodeForToken(code: code)
                            await saveConnection()
                        } catch {
                            await MainActor.run {
                                authorizationError = error.localizedDescription
                                isAuthorizationLoading = false
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            if let observer = callbackObserver {
                NotificationCenter.default.removeObserver(observer)
                callbackObserver = nil
            }
        }
    }
    
    private func saveConnection() async {
        // Create new connection
        let (embeddedToken, _) = buildEmbeddedTokenIfPossible()

        let newConnection = Connection(
            databaseType: .convex,
            name: convexProjectName.isEmpty ? "Convex Connection" : convexProjectName.capitalized,
            color: .purple,
            environment: nil,
            hostname: convexProjectWithId,
            port: "8080",
            username: convexTeamName,
            database: convexProjectName,
            sslMode: nil
        )

        modelContext.insert(newConnection)

        // Save to get persistentModelID, then store password in keychain
        try? modelContext.save()

        // Store token in keychain explicitly after save (not via deferred Task in init)
        if !embeddedToken.isEmpty {
            newConnection.password = embeddedToken
        }

        // Dismiss the modal immediately after saving
        await MainActor.run {
            dismiss()
        }
    }

    /// Build an embedded token string in the format "<deployKey>|m=<base64(json)>" if we have enough data
    private func buildEmbeddedTokenIfPossible() -> (String, String?) {
        // Use the full access token as the deploy key
        // The convexAccessToken should be the raw OAuth access token, not parsed
        let deployKey = convexAccessToken

        var meta: [String: Any] = [:]
        if let projectId = convexTeamId {
            meta["projectId"] = projectId
            meta["teamName"] = convexTeamName.isEmpty ? NSNull() : convexTeamName
            meta["projectName"] = convexProjectName.isEmpty ? NSNull() : convexProjectName
            if !convexDeployments.isEmpty {
                meta["deployments"] = convexDeployments
            }
        }

        // If we have at least a projectId, produce the embedded token
        if meta["projectId"] != nil {
            do {
                let data = try JSONSerialization.data(withJSONObject: meta, options: [.withoutEscapingSlashes, .sortedKeys])
                let base64 = data.base64EncodedString()
                let embedded = deployKey + "|m=" + base64
                return (embedded, base64)
            } catch {
                // Failed to serialize metadata, return raw deploy key
            }
        }
        return (deployKey, nil)
    }

    // Convex OAuth parameters
    @State private var convexTeamName = ""
    @State private var convexProjectName = ""
    @State private var convexTeamId: Int64?
    @State private var convexProjectWithId = ""
    @State private var convexDeployments: [[String: Any]] = []
    
    
    // PKCE parameters (required by RFC 8252)
    @State private var codeVerifier: String = ""
    @State private var codeChallenge: String = ""
    
    private func openConvexOAuthInBrowser() {
        // Set loading state
        isAuthorizationLoading = true

        guard let clientId = BuildSecrets.convexOAuthClientID,
              BuildSecrets.convexOAuthClientSecret != nil else {
            authorizationError = "Convex OAuth is not configured for this build."
            isAuthorizationLoading = false
            return
        }
        
        // Generate PKCE parameters (required by RFC 8252)
        generatePKCEParameters()
        
        // Build OAuth URL
        let redirectUri = "https://pluk.sh/oauth/convex/callback"
        let scope = "project"
        let state = UUID().uuidString
        
        var components = URLComponents(string: "https://dashboard.convex.dev/oauth/authorize/\(scope)")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        if let url = components.url {
            NSWorkspace.shared.open(url)
        } else {
            // Reset loading state if URL creation failed
            isAuthorizationLoading = false
        }
        
    }
    
    
    private func generatePKCEParameters() {
        // Generate code_verifier (RFC 7636 Section 4.1)
        codeVerifier = generateCodeVerifier()
        
        // Generate code_challenge (RFC 7636 Section 4.2)
        codeChallenge = generateCodeChallenge(from: codeVerifier)
    }
    
    private func generateCodeVerifier() -> String {
        // RFC 7636 recommends 43-128 characters, using 128 for maximum entropy
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<128).compactMap { _ in characters.randomElement() })
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        // RFC 7636 Section 4.2: code_challenge = BASE64URL(SHA256(code_verifier))
        guard let data = verifier.data(using: .utf8) else { return "" }
        
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncodedString()
    }
    
    private func exchangeCodeForToken(code: String) async throws {
        guard let clientId = BuildSecrets.convexOAuthClientID,
              let clientSecret = BuildSecrets.convexOAuthClientSecret else {
            throw NSError(domain: "ConvexOAuth", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Convex OAuth is not configured for this build."
            ])
        }

        // OAuth token exchange implementation
        let tokenURL = URL(string: "https://api.convex.dev/oauth/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let redirectUri = "https://pluk.sh/oauth/convex/callback"
        
        let bodyString = "client_id=\(clientId)&client_secret=\(clientSecret)&grant_type=authorization_code&redirect_uri=\(redirectUri)&code=\(code)&code_verifier=\(codeVerifier)"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for HTTP errors
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "ConvexOAuth", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Failed to exchange authorization code"
            ])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ConvexOAuth", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response from Convex OAuth server"
            ])
        }
        
        // Check for OAuth error in response
        if let error = json["error"] as? String {
            let errorDescription = json["error_description"] as? String ?? error
            throw NSError(domain: "ConvexOAuth", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "OAuth error: \(errorDescription)"
            ])
        }
        
        guard let accessToken = json["access_token"] as? String else {
            throw NSError(domain: "ConvexOAuth", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No access token received from Convex"
            ])
        }
        
        // Get token details to fetch team ID
        try await getTokenDetails(accessToken: accessToken)
    }
    
    private func getTokenDetails(accessToken: String) async throws {
        let tokenDetailsURL = URL(string: "https://api.convex.dev/v1/token_details")!
        var request = URLRequest(url: tokenDetailsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Check for HTTP errors
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode != 200 {
                throw NSError(domain: "ConvexOAuth", code: httpResponse.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to get token details. Status: \(httpResponse.statusCode)"
                ])
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ConvexOAuth", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid token details response"
            ])
        }

        // Parse values locally first
        var projectIdLocal: Int64?
        var teamNameLocal: String?
        var projectNameLocal: String?

        // Handle different number types that JSON might return
        if let projectId = json["projectId"] as? Int64 {
            projectIdLocal = projectId
        } else if let projectId = json["projectId"] as? Int {
            projectIdLocal = Int64(projectId)
        } else if let projectId = json["projectId"] as? NSNumber {
            projectIdLocal = projectId.int64Value
        }

        if let tokenName = json["name"] as? String {
            if let parenIndex = tokenName.firstIndex(of: "(") {
                teamNameLocal = String(tokenName[..<parenIndex]).trimmingCharacters(in: .whitespaces)
            } else {
                teamNameLocal = tokenName
            }
        }

        // Token format: project:username:projectname-id|rest
        var projectWithIdLocal: String?
        let tokenParts = accessToken.split(separator: "|")
        if let tokenPrefix = tokenParts.first {
            let prefixParts = tokenPrefix.split(separator: ":")
            if prefixParts.count >= 3 {
                let projectWithId = String(prefixParts[2])
                projectWithIdLocal = projectWithId
                if let dashIndex = projectWithId.firstIndex(of: "-") {
                    projectNameLocal = String(projectWithId[..<dashIndex])
                } else {
                    projectNameLocal = projectWithId
                }
            }
        }

        // Fetch deployments while we have a valid token
        var deploymentsLocal: [[String: Any]] = []
        if let pid = projectIdLocal {
            deploymentsLocal = await fetchDeployments(accessToken: accessToken, projectId: pid, teamName: teamNameLocal)
        }

        await MainActor.run {
            convexAccessToken = accessToken
            if let pid = projectIdLocal { convexTeamId = pid }
            if let tn = teamNameLocal { convexTeamName = tn }
            if let pn = projectNameLocal { convexProjectName = pn }
            if let pwid = projectWithIdLocal { convexProjectWithId = pwid }
            convexDeployments = deploymentsLocal

            arrowPulse = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                arrowPulse = false
            }
        }
    }

    private func fetchDeployments(accessToken: String, projectId: Int64, teamName: String?) async -> [[String: Any]] {
        let url = URL(string: "https://api.convex.dev/v1/projects/\(projectId)/list_deployments")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let deployments = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return deployments.compactMap { dep in
            guard let name = dep["name"] as? String,
                  let deploymentType = dep["deploymentType"] as? String else { return nil }
            let label = ConvexDriver.getDeploymentLabel(
                deployment: ConvexDeployment(
                    name: name,
                    createTime: dep["createTime"] as? Int64 ?? 0,
                    deploymentType: deploymentType,
                    projectId: projectId,
                    previewIdentifier: dep["previewIdentifier"] as? String
                ),
                whoseName: teamName
            )
            return [
                "name": label,
                "deploymentType": deploymentType,
                "projectId": projectId,
                "deploymentId": name
            ] as [String: Any]
        }
    }
}
