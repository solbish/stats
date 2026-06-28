//
//  main.swift
//  Claude
//
//  Created by Claude Usage Monitor
//  Copyright 2024. All rights reserved.
//

import Cocoa
import Kit
import WidgetKit

public struct Claude_Usage: Codable {
    public var fiveHourUtil: Double = 0
    public var fiveHourResetsAt: Date = Date().addingTimeInterval(5 * 3600)  // Default: 5 hours from now
    public var sevenDayUtil: Double = 0
    public var sevenDayResetsAt: Date = Date().addingTimeInterval(7 * 24 * 3600)  // Default: 7 days from now
    public var opusUtil: Double = 0
    public var sonnetUtil: Double = 0
    public var tier: String = ""
    public var rateLimitTier: String = ""
    public var lastUpdated: Date = Date()
    public var error: String? = nil
    public var viaWebAPI: Bool = false  // True if data came from web API fallback
}

public enum BindingWindow: String, Codable { case fiveHour, sevenDay, both }

public extension Claude_Usage {
    var effectiveUtil: Double { max(fiveHourUtil, sevenDayUtil) }

    var bindingWindow: BindingWindow {
        if abs(fiveHourUtil - sevenDayUtil) < 0.5 { return .both }
        return fiveHourUtil > sevenDayUtil ? .fiveHour : .sevenDay
    }

    var bindingResetsAt: Date {
        bindingWindow == .sevenDay ? sevenDayResetsAt : fiveHourResetsAt
    }

    var sevenDayDominates: Bool {
        sevenDayUtil >= 80 && sevenDayUtil > fiveHourUtil
    }
}

public class Claude: Module {
    public let instance: ClaudeInstance
    private let webAPI: ClaudeWebAPI
    private let historyStore: UsageHistory

    private let popupView: Popup
    private let settingsView: Settings

    private var usageReader: UsageReader? = nil

    private var systemWidgetsUpdatesState: Bool {
        self.userDefaults?.bool(forKey: "systemWidgetsUpdates_state") ?? false
    }

    /// True if this instance owns the system WidgetKit slot (first instance in registry).
    private var ownsSystemWidget: Bool {
        return ClaudeInstanceRegistry.shared.instances.first?.id == self.instance.id
    }

    public init(_ instance: ClaudeInstance) {
        self.instance = instance
        self.webAPI = ClaudeWebAPI(instanceId: instance.id)
        self.historyStore = UsageHistory(instanceId: instance.id)

        self.settingsView = Settings(.claude, instance: instance, webAPI: self.webAPI)
        self.popupView = Popup(.claude)

        super.init(
            moduleType: .claude,
            popup: self.popupView,
            settings: self.settingsView,
            displayName: "Claude · \(instance.displayName)"
        )
        guard self.available else { return }

        self.popupView.setHistoryStore(self.historyStore)

        self.usageReader = UsageReader(
            .claude,
            instanceId: instance.id,
            webAPI: self.webAPI,
            history: self.historyStore
        ) { [weak self] value in
            self?.usageCallback(value)
        }

        self.settingsView.callback = { [weak self] in
            self?.usageReader?.read()
        }
        self.settingsView.setInterval = { [weak self] value in
            self?.usageReader?.setInterval(value)
        }

        self.setReaders([self.usageReader])
    }

    private func usageCallback(_ raw: Claude_Usage?) {
        guard let value = raw, self.enabled else { return }

        self.popupView.usageCallback(value)

        self.menuBar.widgets.filter{ $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini:
                widget.setValue(value.effectiveUtil / 100)
            case let widget as LineChart:
                widget.setValue(value.effectiveUtil / 100)
            case let widget as BarChart:
                widget.setValue([[ColorValue(value.fiveHourUtil / 100)], [ColorValue(value.sevenDayUtil / 100)]])
            case let widget as PieChart:
                let v = value.effectiveUtil / 100
                widget.setValue([
                    ColorValue(v, color: NSColor.systemOrange),
                    ColorValue(1 - v, color: NSColor.systemGreen)
                ])
            default: break
            }
        }

        // System WidgetKit slot: only the first instance owns it (v1).
        if self.systemWidgetsUpdatesState && self.ownsSystemWidget {
            let widgetKind = "ClaudeWidget"
            if let blobData = try? JSONEncoder().encode(value) {
                self.userDefaults?.set(blobData, forKey: "Claude@UsageReader")
            }
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
    }

    public override func isAvailable() -> Bool {
        // Always available - users can connect via settings
        return true
    }
}
