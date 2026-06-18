//
//  instances.swift
//  Claude
//
//  Created by Claude Usage Monitor
//  Copyright 2024. All rights reserved.
//

import Foundation
import Kit

public struct ClaudeInstance: Codable, Equatable {
    public let id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public extension Notification.Name {
    static let claudeInstancesChanged = Notification.Name("claudeInstancesChanged")
}

public final class ClaudeInstanceRegistry {
    public static let shared = ClaudeInstanceRegistry()

    private let storageKey = "Claude_instances"
    private let migrationFlagKey = "Claude_instances_migrated_v1"
    private let queue = DispatchQueue(label: "eu.exelban.claude.instances")
    private var _instances: [ClaudeInstance] = []

    public var instances: [ClaudeInstance] {
        queue.sync { _instances }
    }

    private init() {
        self.load()
        self.migrateIfNeeded()
    }

    private func load() {
        let raw = Store.shared.string(key: storageKey, defaultValue: "")
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([ClaudeInstance].self, from: data) else {
            return
        }
        queue.sync { _instances = decoded }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(_instances),
              let json = String(data: data, encoding: .utf8) else { return }
        Store.shared.set(key: storageKey, value: json)
    }

    /// One-shot migration: if no instances are stored yet, create a "Default"
    /// instance and copy legacy un-prefixed Claude_* keys under Claude_default_*.
    private func migrateIfNeeded() {
        let alreadyMigrated = Store.shared.bool(key: migrationFlagKey, defaultValue: false)
        if alreadyMigrated { return }

        let needsDefault = queue.sync { _instances.isEmpty }
        guard needsDefault else {
            Store.shared.set(key: migrationFlagKey, value: true)
            return
        }

        queue.sync {
            _instances.append(ClaudeInstance(id: "default", displayName: "Default"))
        }
        persist()

        // Copy legacy keys to namespaced keys for the default instance.
        let stringKeys = [
            ("Claude_sessionKey", "Claude_default_sessionKey"),
            ("Claude_orgId", "Claude_default_orgId"),
            ("Claude_browserCookies", "Claude_default_browserCookies"),
            ("Claude_lastFetchError", "Claude_default_lastFetchError")
        ]
        for (legacy, scoped) in stringKeys {
            let value = Store.shared.string(key: legacy, defaultValue: "")
            if !value.isEmpty {
                Store.shared.set(key: scoped, value: value)
                Store.shared.remove(legacy)
            }
        }

        let intKeys = [
            ("Claude_webUpdateInterval", "Claude_default_webUpdateInterval"),
            ("Claude_codeUpdateInterval", "Claude_default_codeUpdateInterval"),
            ("Claude_lastFetchTime", "Claude_default_lastFetchTime")
        ]
        for (legacy, scoped) in intKeys {
            let value = Store.shared.int(key: legacy, defaultValue: Int.min)
            if value != Int.min {
                Store.shared.set(key: scoped, value: value)
                Store.shared.remove(legacy)
            }
        }

        Store.shared.set(key: migrationFlagKey, value: true)
    }

    @discardableResult
    public func add(displayName: String) -> ClaudeInstance {
        let instance = ClaudeInstance(id: UUID().uuidString, displayName: displayName)
        queue.sync { _instances.append(instance) }
        persist()
        NotificationCenter.default.post(name: .claudeInstancesChanged, object: nil, userInfo: [
            "action": "add",
            "instance": instance
        ])
        return instance
    }

    public func rename(id: String, to newName: String) {
        var changed: ClaudeInstance? = nil
        queue.sync {
            if let idx = _instances.firstIndex(where: { $0.id == id }) {
                _instances[idx].displayName = newName
                changed = _instances[idx]
            }
        }
        guard let updated = changed else { return }
        persist()
        NotificationCenter.default.post(name: .claudeInstancesChanged, object: nil, userInfo: [
            "action": "rename",
            "instance": updated
        ])
    }

    public func remove(id: String) {
        var removed: ClaudeInstance? = nil
        queue.sync {
            if let idx = _instances.firstIndex(where: { $0.id == id }) {
                removed = _instances.remove(at: idx)
            }
        }
        guard let target = removed else { return }
        // Wipe all instance-scoped keys.
        let prefix = "Claude_\(target.id)_"
        let suffixes = ["sessionKey", "orgId", "browserCookies",
                        "webUpdateInterval", "codeUpdateInterval",
                        "lastFetchTime", "lastFetchError",
                        "history", "state", "popup_state", "position"]
        for suffix in suffixes {
            Store.shared.remove(prefix + suffix)
        }
        persist()
        NotificationCenter.default.post(name: .claudeInstancesChanged, object: nil, userInfo: [
            "action": "remove",
            "instance": target
        ])
    }
}

