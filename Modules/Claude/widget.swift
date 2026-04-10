//
//  widget.swift
//  Claude
//
//  Created by Claude Usage Monitor
//  Copyright 2024. All rights reserved.
//

import SwiftUI
import WidgetKit
import Charts
import Kit

public struct Claude_entry: TimelineEntry {
    public static let kind = "ClaudeWidget"
    public static var snapshot: Claude_entry = Claude_entry(value: Claude_Usage(
        fiveHourUtil: 73,
        fiveHourResetsAt: Date().addingTimeInterval(2 * 3600),
        sevenDayUtil: 34,
        sevenDayResetsAt: Date().addingTimeInterval(3 * 24 * 3600)
    ), isPreview: true)

    public var date: Date {
        Calendar.current.date(byAdding: .minute, value: 2, to: Date())!
    }
    public var value: Claude_Usage? = nil
    public var isPreview: Bool = false
}

public struct ClaudeProvider: TimelineProvider {
    public typealias Entry = Claude_entry

    private let userDefaults: UserDefaults? = UserDefaults(suiteName: "\(Bundle.main.object(forInfoDictionaryKey: "TeamId") as! String).eu.exelban.Stats.widgets")

    public var systemWidgetsUpdatesState: Bool {
        self.userDefaults?.bool(forKey: "systemWidgetsUpdates_state") ?? false
    }

    public func placeholder(in context: Context) -> Claude_entry {
        Claude_entry()
    }

    public func getSnapshot(in context: Context, completion: @escaping (Claude_entry) -> Void) {
        completion(Claude_entry.snapshot)
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<Claude_entry>) -> Void) {
        self.userDefaults?.set(Date().timeIntervalSince1970, forKey: Claude_entry.kind)
        var entry = Claude_entry()
        if let raw = self.userDefaults?.data(forKey: "Claude@UsageReader"), let usage = try? JSONDecoder().decode(Claude_Usage.self, from: raw) {
            entry.value = usage
        }
        let entries: [Claude_entry] = [entry]
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

@available(macOS 14.0, *)
public struct ClaudeWidget: Widget {
    var usedColor: Color = Color(nsColor: NSColor.systemOrange)
    var remainingColor: Color = Color(nsColor: NSColor.systemGreen)
    var weekColor: Color = Color(nsColor: NSColor.systemBlue)

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Claude_entry.kind, provider: ClaudeProvider()) { entry in
            VStack(spacing: 8) {
                if ClaudeProvider().systemWidgetsUpdatesState || entry.isPreview, let value = entry.value, value.error == nil {
                    HStack {
                        Chart {
                            SectorMark(angle: .value("Used", value.fiveHourUtil), innerRadius: .ratio(0.75)).foregroundStyle(self.usedColor)
                            SectorMark(angle: .value("Remaining", max(0, 100 - value.fiveHourUtil)), innerRadius: .ratio(0.75)).foregroundStyle(self.remainingColor)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 80)
                        .chartLegend(.hidden)
                        .chartBackground { chartProxy in
                            GeometryReader { geometry in
                                if let anchor = chartProxy.plotFrame {
                                    let frame = geometry[anchor]
                                    Text("\(Int(value.fiveHourUtil))%")
                                        .font(.system(size: 14, weight: .medium))
                                        .position(x: frame.midX, y: frame.midY-4)
                                    Text("Claude")
                                        .font(.system(size: 8, weight: .semibold))
                                        .position(x: frame.midX, y: frame.midY+10)
                                }
                            }
                        }
                    }
                    VStack(spacing: 4) {
                        HStack {
                            Rectangle().fill(self.usedColor).frame(width: 10, height: 10).cornerRadius(2)
                            Text("5h").font(.system(size: 10, weight: .regular)).foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(value.fiveHourUtil))%").font(.system(size: 10))
                            Text(formatTimeRemaining(value.fiveHourResetsAt)).font(.system(size: 9)).foregroundColor(.secondary)
                        }
                        HStack {
                            Rectangle().fill(self.weekColor).frame(width: 10, height: 10).cornerRadius(2)
                            Text("7d").font(.system(size: 10, weight: .regular)).foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(value.sevenDayUtil))%").font(.system(size: 10))
                            Text(formatTimeRemaining(value.sevenDayResetsAt)).font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                } else if !ClaudeProvider().systemWidgetsUpdatesState {
                    Text("Enable in Settings")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                } else if let value = entry.value, let error = value.error {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24))
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("No data")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .containerBackground(for: .widget) {
                Color.clear
            }
        }
        .configurationDisplayName("Claude widget")
        .description("Displays Claude API usage")
        .supportedFamilies([.systemSmall])
    }
}

private func formatTimeRemaining(_ date: Date) -> String {
    let remaining = date.timeIntervalSinceNow
    if remaining <= 0 { return "now" }
    let hours = Int(remaining / 3600)
    let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
    if hours > 24 {
        return "\(hours / 24)d"
    } else if hours > 0 {
        return "\(hours)h"
    } else {
        return "\(minutes)m"
    }
}
