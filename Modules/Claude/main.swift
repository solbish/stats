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

public class Claude: Module {
    private let popupView: Popup
    private let settingsView: Settings

    private var usageReader: UsageReader? = nil

    private var systemWidgetsUpdatesState: Bool {
        self.userDefaults?.bool(forKey: "systemWidgetsUpdates_state") ?? false
    }

    public init() {
        self.settingsView = Settings(.claude)
        self.popupView = Popup(.claude)

        super.init(
            moduleType: .claude,
            popup: self.popupView,
            settings: self.settingsView
        )
        guard self.available else { return }

        self.usageReader = UsageReader(.claude) { [weak self] value in
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
                widget.setValue(value.fiveHourUtil / 100)
            case let widget as LineChart:
                widget.setValue(value.fiveHourUtil / 100)
            case let widget as BarChart:
                widget.setValue([[ColorValue(value.fiveHourUtil / 100)], [ColorValue(value.sevenDayUtil / 100)]])
            case let widget as PieChart:
                widget.setValue([
                    circle_segment(value: value.fiveHourUtil / 100, color: NSColor.systemOrange),
                    circle_segment(value: (100 - value.fiveHourUtil) / 100, color: NSColor.systemGreen)
                ])
            default: break
            }
        }

        // Update widget - always write data so widget has something to display
        if self.systemWidgetsUpdatesState {
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
