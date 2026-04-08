//
//  oauth.swift
//  Claude
//
//  Created by Claude Usage Monitor
//  Copyright 2024. All rights reserved.
//

import Foundation
import Cocoa
import CommonCrypto
import Network

class ClaudeOAuth {
    static let shared = ClaudeOAuth()

    private let authURL = "https://claude.ai/oauth/authorize"
    private let tokenURL = "https://claude.ai/api/auth/oauth/token"
    private let redirectPort: UInt16 = 54134
    private var redirectURI: String { "http://localhost:\(redirectPort)/callback" }

    private var codeVerifier: String = ""
    private var listener: NWListener?
    private var completion: ((Bool, String?) -> Void)?

    var isLoggingIn: Bool = false

    // MARK: - Public API

    func login(completion: @escaping (Bool, String?) -> Void) {
        // If already logging in, cancel previous attempt and start fresh
        if isLoggingIn {
            stopCallbackServer()
            self.completion = nil
        }

        self.isLoggingIn = true
        self.completion = completion

        // Generate PKCE
        let (verifier, challenge) = generatePKCE()
        self.codeVerifier = verifier

        // Start callback server
        startCallbackServer()

        // Build authorization URL
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: "user:inference user:profile user:file_upload")
        ]

        guard let url = components.url else {
            finishLogin(success: false, error: "Failed to build authorization URL")
            return
        }

        // Open browser
        NSWorkspace.shared.open(url)
    }

    func cancelLogin() {
        stopCallbackServer()
        isLoggingIn = false
        completion?(false, "Cancelled")
        completion = nil
    }

    // MARK: - PKCE

    private func generatePKCE() -> (verifier: String, challenge: String) {
        // Generate 32 random bytes for verifier
        var randomBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &randomBytes)

        // Base64URL encode
        let verifier = Data(randomBytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // SHA256 hash for challenge
        let verifierData = verifier.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        verifierData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }

        let challenge = Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return (verifier, challenge)
    }

    // MARK: - Local HTTP Server

    private func startCallbackServer() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: redirectPort)!)
            listener?.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.finishLogin(success: false, error: "Server error: \(error)")
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: .main)
        } catch {
            finishLogin(success: false, error: "Failed to start callback server: \(error)")
        }
    }

    private func stopCallbackServer() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }

            if let request = String(data: data, encoding: .utf8) {
                self.parseCallback(request: request, connection: connection)
            } else {
                connection.cancel()
            }
        }
    }

    private func parseCallback(request: String, connection: NWConnection) {
        // Parse HTTP request for authorization code
        // Request looks like: GET /callback?code=xxx HTTP/1.1

        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let urlPart = firstLine.components(separatedBy: " ").dropFirst().first,
              let components = URLComponents(string: "http://localhost\(urlPart)") else {
            sendResponse(connection: connection, success: false, message: "Invalid callback")
            finishLogin(success: false, error: "Invalid callback request")
            return
        }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let description = components.queryItems?.first(where: { $0.name == "error_description" })?.value ?? error
            sendResponse(connection: connection, success: false, message: description)
            finishLogin(success: false, error: description)
            return
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            sendResponse(connection: connection, success: false, message: "No authorization code")
            finishLogin(success: false, error: "No authorization code received")
            return
        }

        // Success - show message and exchange code
        sendResponse(connection: connection, success: true, message: "Login successful! You can close this tab.")
        exchangeCodeForToken(code: code)
    }

    private func sendResponse(connection: NWConnection, success: Bool, message: String) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Stats - Claude Login</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #f5f5f5; }
                .container { text-align: center; padding: 40px; background: white; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                .icon { font-size: 48px; margin-bottom: 16px; }
                h1 { margin: 0 0 8px 0; color: #333; }
                p { color: #666; margin: 0; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="icon">\(success ? "✓" : "✗")</div>
                <h1>\(success ? "Success" : "Error")</h1>
                <p>\(message)</p>
            </div>
        </body>
        </html>
        """

        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(html)"

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Token Exchange

    private func exchangeCodeForToken(code: String) {
        stopCallbackServer()

        guard let url = URL(string: tokenURL) else {
            finishLogin(success: false, error: "Invalid token URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
         .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.finishLogin(success: false, error: error.localizedDescription)
                return
            }

            guard let data = data else {
                self?.finishLogin(success: false, error: "No response data")
                return
            }

            do {
                let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

                // Store tokens
                let creds = ClaudeCredentials(
                    accessToken: tokenResponse.accessToken,
                    refreshToken: tokenResponse.refreshToken ?? "",
                    expiresAt: Int64(Date().timeIntervalSince1970 * 1000) + Int64(tokenResponse.expiresIn * 1000),
                    scopes: tokenResponse.scope?.components(separatedBy: " ") ?? [],
                    subscriptionType: nil,
                    rateLimitTier: nil
                )

                if ClaudeAuth.shared.storeCredentials(creds) {
                    self?.finishLogin(success: true, error: nil)
                } else {
                    self?.finishLogin(success: false, error: "Failed to store credentials")
                }
            } catch {
                // Try to parse error response
                if let errorResponse = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                    self?.finishLogin(success: false, error: errorResponse.errorDescription ?? errorResponse.error)
                } else {
                    self?.finishLogin(success: false, error: "Failed to parse token response: \(error)")
                }
            }
        }.resume()
    }

    private func finishLogin(success: Bool, error: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoggingIn = false
            self?.completion?(success, error)
            self?.completion = nil
        }
    }
}

// MARK: - Response Models

private struct OAuthTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct OAuthErrorResponse: Codable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
