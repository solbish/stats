//
//  settings.swift
//  Claude
//
//  Created by Claude Usage Monitor
//  Copyright 2024. All rights reserved.
//

import Cocoa
import Kit

// JSON Cookie format from Cookies Extractor extension
private struct JSONCookie: Codable {
    let name: String
    let value: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

internal class Settings: NSStackView, Settings_v {
    public var callback: (() -> Void) = {}
    public var setInterval: ((_ value: Int) -> Void) = {_ in }

    private let title: String
    private var authSection: PreferencesSection?
    private var webSection: PreferencesSection?
    private var codeStatusLabel: NSTextField?
    private var orgIdField: NSTextField?
    private var webStatusLabel: NSTextField?
    private var sessionKeyDisplay: NSTextField?

    private var webUpdateInterval: Int {
        get { Store.shared.int(key: "Claude_webUpdateInterval", defaultValue: 60) }
        set { Store.shared.set(key: "Claude_webUpdateInterval", value: newValue) }
    }

    private var codeUpdateInterval: Int {
        get { Store.shared.int(key: "Claude_codeUpdateInterval", defaultValue: 300) }
        set { Store.shared.set(key: "Claude_codeUpdateInterval", value: newValue) }
    }

    public init(_ module: ModuleType) {
        self.title = module.stringValue

        super.init(frame: NSRect.zero)

        self.orientation = .vertical
        self.spacing = Constants.Settings.margin

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.authStateChanged),
            name: .claudeAuthStateChanged,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func load(widgets: [widget_t]) {
        self.subviews.forEach { $0.removeFromSuperview() }

        // Web API section FIRST (primary method)
        self.addWebAuthSection()

        // Claude Code section SECOND (fallback method)
        self.addClaudeCodeSection()
    }

    private func addClaudeCodeSection() {
        // Status label
        let hasToken = !Store.shared.string(key: "Claude_accessToken", defaultValue: "").isEmpty || ClaudeAuth.shared.isConnected
        self.codeStatusLabel = NSTextField(labelWithString: hasToken ? "Configured" : "Not configured")
        self.codeStatusLabel?.textColor = hasToken ? NSColor.systemGreen : NSColor.systemGray
        self.codeStatusLabel?.font = NSFont.systemFont(ofSize: 12)

        // Import from Keychain button
        let importBtn = buttonView(#selector(self.importFromKeychain), text: "Import from Keychain")

        // Clear button
        let clearBtn = buttonView(#selector(self.clearCodeToken), text: "Clear")

        // Update interval for Claude Code (default 5 min)
        let intervalSelect = selectView(
            action: #selector(self.changeCodeUpdateInterval),
            items: [
                KeyValue_t(key: "60", value: "1 min"),
                KeyValue_t(key: "120", value: "2 min"),
                KeyValue_t(key: "300", value: "5 min"),
                KeyValue_t(key: "600", value: "10 min")
            ],
            selected: "\(self.codeUpdateInterval)"
        )

        // Instructions
        let instructionsText = "Imports from Claude Code CLI Keychain.\nRequires: claude CLI installed & logged in."
        let instructions = NSTextField(wrappingLabelWithString: instructionsText)
        instructions.font = NSFont.systemFont(ofSize: 10)
        instructions.textColor = NSColor.secondaryLabelColor
        instructions.preferredMaxLayoutWidth = 280

        self.authSection = PreferencesSection(label: "Claude Code (fallback)", [
            PreferencesRow("Status", component: self.codeStatusLabel!),
            PreferencesRow(component: importBtn),
            PreferencesRow(component: clearBtn),
            PreferencesRow("Update interval", component: intervalSelect),
            PreferencesRow(component: instructions)
        ])
        self.addArrangedSubview(self.authSection!)
    }

    private func getMaskedToken(_ token: String) -> String {
        if token.isEmpty { return "" }
        let suffix = String(token.suffix(8))
        return "••••••••••••\(suffix)"
    }

    private func addWebAuthSection() {
        // Web status label with last fetch info
        self.webStatusLabel = NSTextField(labelWithString: getWebStatusText())
        self.webStatusLabel?.textColor = getWebStatusColor()
        self.webStatusLabel?.font = NSFont.systemFont(ofSize: 12)

        // Import from clipboard button
        let importBtn = buttonView(#selector(self.importFromClipboard), text: "Import from Clipboard")

        // Session Key display (show masked value with last 8 chars)
        self.sessionKeyDisplay = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
        self.sessionKeyDisplay?.isEditable = false
        self.sessionKeyDisplay?.isBordered = true
        self.sessionKeyDisplay?.backgroundColor = NSColor.textBackgroundColor
        self.sessionKeyDisplay?.stringValue = getMaskedSessionKey()
        self.sessionKeyDisplay?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        self.sessionKeyDisplay?.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Org ID field (editable, shows full value)
        self.orgIdField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
        self.orgIdField?.placeholderString = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        self.orgIdField?.stringValue = getMaskedOrgId()
        self.orgIdField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        self.orgIdField?.isEditable = false
        self.orgIdField?.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Clear button
        let clearBtn = buttonView(#selector(self.clearWebAuth), text: "Clear")

        // Update interval for Web API (default 1 min)
        let intervalSelect = selectView(
            action: #selector(self.changeWebUpdateInterval),
            items: [
                KeyValue_t(key: "10", value: "10 sec"),
                KeyValue_t(key: "30", value: "30 sec"),
                KeyValue_t(key: "60", value: "1 min"),
                KeyValue_t(key: "120", value: "2 min"),
                KeyValue_t(key: "300", value: "5 min")
            ],
            selected: "\(self.webUpdateInterval)"
        )

        // Detailed instructions
        let instructionsText = """
        How to get cookies:
        1. Install 'Cookies Extractor' Chrome extension
        2. Go to claude.ai and log in
        3. Click the extension icon
        4. Click 'Copy as JSON Cookie'
        5. Click 'Import from Clipboard' above
        """
        let instructions = NSTextField(wrappingLabelWithString: instructionsText)
        instructions.font = NSFont.systemFont(ofSize: 10)
        instructions.textColor = NSColor.secondaryLabelColor
        instructions.preferredMaxLayoutWidth = 280

        self.webSection = PreferencesSection(label: "Claude.ai Web", [
            PreferencesRow("Status", component: self.webStatusLabel!),
            PreferencesRow(component: importBtn),
            PreferencesRow("Session Key", component: self.sessionKeyDisplay!),
            PreferencesRow("Org ID", component: self.orgIdField!),
            PreferencesRow(component: clearBtn),
            PreferencesRow("Update interval", component: intervalSelect),
            PreferencesRow(component: instructions)
        ])
        self.addArrangedSubview(self.webSection!)
    }

    private func getWebStatusText() -> String {
        let hasWebAuth = ClaudeWebAPI.shared.hasWebAuth
        if !hasWebAuth {
            return "Not configured"
        }

        // Check for last fetch error
        if let error = Store.shared.string(key: "Claude_lastFetchError", defaultValue: "").nilIfEmpty {
            return "Error: \(error)"
        }

        // Check last fetch time
        let lastFetch = Store.shared.int(key: "Claude_lastFetchTime", defaultValue: 0)
        if lastFetch > 0 {
            let date = Date(timeIntervalSince1970: Double(lastFetch))
            let ago = Date().timeIntervalSince(date)
            if ago < 60 {
                return "OK - \(Int(ago))s ago"
            } else if ago < 3600 {
                return "OK - \(Int(ago / 60))m ago"
            } else {
                return "OK - \(Int(ago / 3600))h ago"
            }
        }

        return "Configured"
    }

    private func getWebStatusColor() -> NSColor {
        let hasWebAuth = ClaudeWebAPI.shared.hasWebAuth
        if !hasWebAuth {
            return NSColor.systemGray
        }
        if Store.shared.string(key: "Claude_lastFetchError", defaultValue: "").nilIfEmpty != nil {
            return NSColor.systemOrange
        }
        return NSColor.systemGreen
    }

    private func getMaskedSessionKey() -> String {
        let sessionKey = ClaudeWebAPI.shared.getSessionKey()
        if sessionKey.isEmpty {
            return ""
        }
        // Show last 8 chars, mask the rest
        let suffix = String(sessionKey.suffix(8))
        return "••••••••••••\(suffix)"
    }

    private func getMaskedOrgId() -> String {
        let orgId = ClaudeWebAPI.shared.getOrgId()
        if orgId.isEmpty { return "" }
        let suffix = String(orgId.suffix(8))
        return "••••••••••••\(suffix)"
    }

    private func updateWebStatus() {
        self.webStatusLabel?.stringValue = getWebStatusText()
        self.webStatusLabel?.textColor = getWebStatusColor()
    }

    @objc private func importFromClipboard() {
        guard let clipboardString = NSPasteboard.general.string(forType: .string) else {
            showAlert(title: "Clipboard Empty", message: "No text found in clipboard")
            return
        }

        // Try to parse as JSON first (from Cookies Extractor "Copy as JSON Cookie")
        if let jsonResult = parseJSONCookies(clipboardString) {
            applyParsedCookies(jsonResult)
            return
        }

        // Try to parse as Header Cookie format (key=value; key2=value2)
        if let headerResult = parseHeaderCookies(clipboardString) {
            applyParsedCookies(headerResult)
            return
        }

        showAlert(title: "Parse Failed", message: "Could not parse cookies. Use 'Copy as JSON Cookie' from Cookies Extractor extension.")
    }

    private func parseJSONCookies(_ json: String) -> (sessionKey: String, orgId: String)? {
        guard let data = json.data(using: .utf8),
              let cookies = try? JSONDecoder().decode([JSONCookie].self, from: data) else {
            return nil
        }

        var sessionKey: String?
        var orgId: String?

        for cookie in cookies {
            if cookie.name == "sessionKey" {
                sessionKey = cookie.value
            } else if cookie.name == "lastActiveOrg" {
                orgId = cookie.value
            }
        }

        guard let sk = sessionKey, let org = orgId else { return nil }
        return (sk, org)
    }

    private func parseHeaderCookies(_ header: String) -> (sessionKey: String, orgId: String)? {
        var sessionKey: String?
        var orgId: String?

        // Parse "key=value; key2=value2" format
        let pairs = header.components(separatedBy: "; ")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1])
                if key == "sessionKey" {
                    sessionKey = value
                } else if key == "lastActiveOrg" {
                    orgId = value
                }
            }
        }

        guard let sk = sessionKey, let org = orgId else { return nil }
        return (sk, org)
    }

    private func applyParsedCookies(_ result: (sessionKey: String, orgId: String)) {
        ClaudeWebAPI.shared.setSessionToken(result.sessionKey, orgId: result.orgId)
        self.sessionKeyDisplay?.stringValue = getMaskedSessionKey()
        self.orgIdField?.stringValue = result.orgId
        self.updateWebStatus()
        self.callback()

        showAlert(title: "Import Successful", message: "Session Key and Org ID imported from clipboard.")
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = title.contains("Failed") || title.contains("Empty") ? .warning : .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func clearWebAuth() {
        ClaudeWebAPI.shared.clearSessionToken()
        ClaudeWebAPI.shared.clearBrowserCookies()
        Store.shared.remove("Claude_lastFetchTime")
        Store.shared.remove("Claude_lastFetchError")
        self.sessionKeyDisplay?.stringValue = ""
        self.orgIdField?.stringValue = ""
        self.updateWebStatus()
        self.callback()
    }

    @objc private func importFromKeychain() {
        ClaudeAuth.shared.connect { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.updateCodeStatus()
                    self?.callback()
                    self?.showAlert(title: "Import Successful", message: "Token imported from Keychain.")
                } else if let error = error {
                    self?.showAlert(title: "Import Failed", message: error)
                }
            }
        }
    }

    @objc private func clearCodeToken() {
        Store.shared.remove("Claude_accessToken")
        ClaudeAuth.shared.disconnect()
        updateCodeStatus()
        self.callback()
    }

    private func updateCodeStatus() {
        let hasToken = !Store.shared.string(key: "Claude_accessToken", defaultValue: "").isEmpty || ClaudeAuth.shared.isConnected
        self.codeStatusLabel?.stringValue = hasToken ? "Configured" : "Not configured"
        self.codeStatusLabel?.textColor = hasToken ? NSColor.systemGreen : NSColor.systemGray
    }

    @objc private func authStateChanged() {
        DispatchQueue.main.async { [weak self] in
            // Update Web API status (for last fetch time updates)
            self?.updateWebStatus()
            // Update Claude Code status
            self?.updateCodeStatus()
        }
    }

    @objc private func changeWebUpdateInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.webUpdateInterval = value
        self.setInterval(value)
    }

    @objc private func changeCodeUpdateInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.codeUpdateInterval = value
        // Only update interval if Code is the active method (Web not configured)
        if !ClaudeWebAPI.shared.hasWebAuth {
            self.setInterval(value)
        }
    }
}
