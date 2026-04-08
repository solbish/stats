//
//  keychain.swift
//  Claude
//
//  Created by Claude Usage Monitor
//  Copyright 2024. All rights reserved.
//

import Foundation
import Security
import Kit

class ClaudeAuth {
    static let shared = ClaudeAuth()

    private let storageKey = "Claude_StoredCredentials"
    private let claudeCodeService = "Claude Code-credentials"

    // Check if we have stored credentials (from previous connection)
    var isConnected: Bool {
        return getStoredCredentials() != nil
    }

    // Get credentials - first from our storage, then from Claude Code keychain
    func getCredentials() -> ClaudeCredentials? {
        // First try our own stored credentials
        if let stored = getStoredCredentials() {
            return stored
        }
        return nil
    }

    // Connect: Import from Claude Code keychain and store locally
    func connect(completion: @escaping (Bool, String?) -> Void) {
        // Read from Claude Code keychain (will prompt for password)
        guard let creds = importFromClaudeCode() else {
            completion(false, "Could not read credentials from Claude Code. Make sure Claude Code is installed and you're logged in.")
            return
        }

        // Store in our own storage
        if storeCredentials(creds) {
            completion(true, nil)
        } else {
            completion(false, "Failed to store credentials")
        }
    }

    // Disconnect: Remove stored credentials
    func disconnect() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: .claudeAuthStateChanged, object: nil)
    }

    // Import credentials from Claude Code keychain
    private func importFromClaudeCode() -> ClaudeCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeCodeService,
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        do {
            let credentials = try JSONDecoder().decode(CredentialsFile.self, from: data)
            return credentials.claudeAiOauth
        } catch {
            return nil
        }
    }

    // Store credentials in UserDefaults
    func storeCredentials(_ creds: ClaudeCredentials) -> Bool {
        do {
            let data = try JSONEncoder().encode(creds)
            UserDefaults.standard.set(data, forKey: storageKey)
            NotificationCenter.default.post(name: .claudeAuthStateChanged, object: nil)
            return true
        } catch {
            return false
        }
    }

    // Get stored credentials from UserDefaults
    private func getStoredCredentials() -> ClaudeCredentials? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(ClaudeCredentials.self, from: data)
        } catch {
            return nil
        }
    }
}

// Notification for auth state changes
public extension Notification.Name {
    static let claudeAuthStateChanged = Notification.Name("claudeAuthStateChanged")
}

// Legacy compatibility
class KeychainHelper {
    static func hasClaudeCredentials() -> Bool {
        return ClaudeAuth.shared.isConnected
    }

    static func getClaudeCredentials() -> ClaudeCredentials? {
        return ClaudeAuth.shared.getCredentials()
    }
}
