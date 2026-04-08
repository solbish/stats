//
//  popup.swift
//  Claude
//
//  Created by Claude Usage Monitor
//  Copyright 2024. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private let rowHeight: CGFloat = 22
    private let barHeight: CGFloat = 14

    private var fiveHourBar: NSProgressIndicator? = nil
    private var fiveHourLabel: NSTextField? = nil
    private var fiveHourCountdown: NSTextField? = nil

    private var sevenDayBar: NSProgressIndicator? = nil
    private var sevenDayLabel: NSTextField? = nil
    private var sevenDayCountdown: NSTextField? = nil

    private var opusLabel: NSTextField? = nil
    private var sonnetLabel: NSTextField? = nil

    private var tierLabel: NSTextField? = nil
    private var lastUpdatedLabel: NSTextField? = nil
    private var errorLabel: NSTextField? = nil
    private var peakLabel: NSTextField? = nil
    private var peakTimeLabel: NSTextField? = nil

    private var historyChart: ClaudeHistoryChartView? = nil
    private var hourlyBarChart: ColumnChartView? = nil
    private var bestTimeLabel: NSTextField? = nil

    private var countdownTimer: Timer?
    private var fiveHourResetDate: Date = Date()
    private var sevenDayResetDate: Date = Date()

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.orientation = .vertical
        self.spacing = 0

        self.setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        countdownTimer?.invalidate()
    }

    private func setupViews() {
        // 5-Hour section
        let fiveHourSection = self.createSection(title: "5-Hour Usage")
        let (fiveHourBar, fiveHourLabel, fiveHourCountdown) = self.createUsageRow()
        self.fiveHourBar = fiveHourBar
        self.fiveHourLabel = fiveHourLabel
        self.fiveHourCountdown = fiveHourCountdown
        fiveHourSection.addSubview(fiveHourBar)
        fiveHourSection.addSubview(fiveHourLabel)
        fiveHourSection.addSubview(fiveHourCountdown)
        self.addArrangedSubview(fiveHourSection)

        // 7-Day section
        let sevenDaySection = self.createSection(title: "7-Day Usage")
        let (sevenDayBar, sevenDayLabel, sevenDayCountdown) = self.createUsageRow()
        self.sevenDayBar = sevenDayBar
        self.sevenDayLabel = sevenDayLabel
        self.sevenDayCountdown = sevenDayCountdown
        sevenDaySection.addSubview(sevenDayBar)
        sevenDaySection.addSubview(sevenDayLabel)
        sevenDaySection.addSubview(sevenDayCountdown)

        // Model breakdown row
        let modelRow = NSView(frame: NSRect(x: Constants.Popup.margins, y: 8, width: Constants.Popup.width - Constants.Popup.margins * 2, height: rowHeight))
        self.opusLabel = self.createLabel(frame: NSRect(x: 0, y: 0, width: modelRow.frame.width / 2, height: 16), alignment: .left)
        self.opusLabel?.textColor = .secondaryLabelColor
        self.sonnetLabel = self.createLabel(frame: NSRect(x: modelRow.frame.width / 2, y: 0, width: modelRow.frame.width / 2, height: 16), alignment: .right)
        self.sonnetLabel?.textColor = .secondaryLabelColor
        modelRow.addSubview(self.opusLabel!)
        modelRow.addSubview(self.sonnetLabel!)
        sevenDaySection.addSubview(modelRow)

        self.addArrangedSubview(sevenDaySection)

        // History section (24-hour chart)
        let historyHeight: CGFloat = 60
        let historySection = self.createSection(title: "24-Hour History", height: Constants.Popup.separatorHeight + historyHeight + rowHeight + 8)

        self.historyChart = ClaudeHistoryChartView(
            frame: NSRect(x: Constants.Popup.margins, y: rowHeight + 8, width: Constants.Popup.width - Constants.Popup.margins * 2, height: historyHeight)
        )
        self.historyChart?.color = .controlAccentColor
        historySection.addSubview(self.historyChart!)

        self.bestTimeLabel = self.createLabel(frame: NSRect(x: Constants.Popup.margins, y: 4, width: Constants.Popup.width - Constants.Popup.margins * 2, height: 16), alignment: .center)
        self.bestTimeLabel?.textColor = .secondaryLabelColor
        self.bestTimeLabel?.stringValue = "Best time: analyzing..."
        historySection.addSubview(self.bestTimeLabel!)

        self.addArrangedSubview(historySection)

        // Sessions (24h) section - temporarily hidden, to be continued later
        // let barChartHeight: CGFloat = 50
        // let barSection = self.createSection(title: "Sessions (24h)", height: Constants.Popup.separatorHeight + barChartHeight + 8)
        // self.hourlyBarChart = ColumnChartView(
        //     frame: NSRect(x: Constants.Popup.margins, y: 4, width: Constants.Popup.width - Constants.Popup.margins * 2, height: barChartHeight),
        //     num: 24
        // )
        // barSection.addSubview(self.hourlyBarChart!)
        // self.addArrangedSubview(barSection)

        // Status section
        let statusSection = self.createSection(title: "Status", height: Constants.Popup.separatorHeight + rowHeight * 3)
        self.tierLabel = self.createLabel(frame: NSRect(x: Constants.Popup.margins, y: statusSection.frame.height - Constants.Popup.separatorHeight - rowHeight, width: (Constants.Popup.width - Constants.Popup.margins * 2) / 2, height: 16), alignment: .left)
        self.lastUpdatedLabel = self.createLabel(frame: NSRect(x: Constants.Popup.width / 2, y: statusSection.frame.height - Constants.Popup.separatorHeight - rowHeight, width: (Constants.Popup.width - Constants.Popup.margins * 2) / 2, height: 16), alignment: .right)
        self.lastUpdatedLabel?.textColor = .secondaryLabelColor

        // Peak hours row
        self.peakLabel = self.createLabel(frame: NSRect(x: Constants.Popup.margins, y: statusSection.frame.height - Constants.Popup.separatorHeight - rowHeight * 2, width: (Constants.Popup.width - Constants.Popup.margins * 2) / 2, height: 16), alignment: .left)
        self.peakTimeLabel = self.createLabel(frame: NSRect(x: Constants.Popup.width / 2, y: statusSection.frame.height - Constants.Popup.separatorHeight - rowHeight * 2, width: (Constants.Popup.width - Constants.Popup.margins * 2) / 2, height: 16), alignment: .right)
        self.peakTimeLabel?.textColor = .secondaryLabelColor

        self.errorLabel = self.createLabel(frame: NSRect(x: Constants.Popup.margins, y: 8, width: Constants.Popup.width - Constants.Popup.margins * 2, height: 16), alignment: .center)
        self.errorLabel?.textColor = .systemRed
        self.errorLabel?.isHidden = true
        statusSection.addSubview(self.tierLabel!)
        statusSection.addSubview(self.lastUpdatedLabel!)
        statusSection.addSubview(self.peakLabel!)
        statusSection.addSubview(self.peakTimeLabel!)
        statusSection.addSubview(self.errorLabel!)
        self.addArrangedSubview(statusSection)

        self.recalculateHeight()
    }

    private func createSection(title: String, height: CGFloat = 0) -> NSView {
        let sectionHeight = height > 0 ? height : Constants.Popup.separatorHeight + rowHeight * 2 + 8
        let view = NSView(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: sectionHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true

        let separator = separatorView(title, origin: NSPoint(x: 0, y: sectionHeight - Constants.Popup.separatorHeight), width: Constants.Popup.width)
        view.addSubview(separator)

        return view
    }

    private func createUsageRow() -> (NSProgressIndicator, NSTextField, NSTextField) {
        let bar = NSProgressIndicator(frame: NSRect(x: Constants.Popup.margins, y: rowHeight * 2 - 4, width: Constants.Popup.width - Constants.Popup.margins * 2, height: barHeight))
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 100
        bar.isIndeterminate = false

        let label = self.createLabel(frame: NSRect(x: Constants.Popup.margins, y: rowHeight - 4, width: (Constants.Popup.width - Constants.Popup.margins * 2) / 2, height: 16), alignment: .left)
        let countdown = self.createLabel(frame: NSRect(x: Constants.Popup.width / 2, y: rowHeight - 4, width: (Constants.Popup.width - Constants.Popup.margins * 2) / 2, height: 16), alignment: .right)
        countdown.textColor = .secondaryLabelColor

        return (bar, label, countdown)
    }

    private func createLabel(frame: NSRect, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = alignment
        label.font = NSFont.systemFont(ofSize: 11)
        label.stringValue = "-"
        return label
    }

    private func recalculateHeight() {
        var h: CGFloat = 0
        self.arrangedSubviews.forEach { v in
            h += v.bounds.height
        }
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }

    public func usageCallback(_ value: Claude_Usage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 5-hour usage
            self.fiveHourBar?.doubleValue = value.fiveHourUtil
            self.fiveHourLabel?.stringValue = String(format: "%.1f%% used", value.fiveHourUtil)

            // 7-day usage
            self.sevenDayBar?.doubleValue = value.sevenDayUtil
            self.sevenDayLabel?.stringValue = String(format: "%.1f%% used", value.sevenDayUtil)

            // Model breakdown - only show if API provides actual data
            let hasModelBreakdown = value.opusUtil > 0 || value.sonnetUtil > 0
            self.opusLabel?.isHidden = !hasModelBreakdown
            self.sonnetLabel?.isHidden = !hasModelBreakdown
            if hasModelBreakdown {
                self.opusLabel?.stringValue = String(format: "Opus: %.1f%%", value.opusUtil)
                self.sonnetLabel?.stringValue = String(format: "Sonnet: %.1f%%", value.sonnetUtil)
            }

            // Tier
            self.tierLabel?.stringValue = value.tier.isEmpty ? "Max" : value.tier

            // Last updated
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            self.lastUpdatedLabel?.stringValue = formatter.string(from: value.lastUpdated)

            // Error
            if let error = value.error {
                self.errorLabel?.stringValue = error
                self.errorLabel?.isHidden = false
            } else {
                self.errorLabel?.isHidden = true
            }

            // Update countdown timer
            self.fiveHourResetDate = value.fiveHourResetsAt
            self.sevenDayResetDate = value.sevenDayResetsAt
            self.startCountdownTimer()

            // Update history chart
            self.updateHistoryChart()
        }
    }

    private func updateHistoryChart() {
        // Get chart data with activity indicators (API usage data)
        let chartData = UsageHistory.shared.getChartDataWithActivity(hours: 24)

        // Update chart with history data (always update, even if empty)
        self.historyChart?.points = chartData
        self.historyChart?.needsDisplay = true

        // Update hourly bar chart with real Claude Code sessions
        let sessionData = ClaudeSessionReader.shared.getSessionBarData()

        // Color palette for different sessions
        let sessionColors: [NSColor] = [
            .controlAccentColor,  // Blue
            .systemOrange,
            .systemGreen,
            .systemPurple,
            .systemPink,
            .systemTeal
        ]

        let barValues: [ColorValue] = sessionData.map { data in
            switch data.state {
            case .activity:
                // Active session hour - color by session index
                let colorIndex = data.sessionIndex % sessionColors.count
                return ColorValue(data.sessionUsage, color: sessionColors[colorIndex])
            case .inSession:
                // In session but no activity - lighter shade
                let colorIndex = data.sessionIndex % sessionColors.count
                return ColorValue(data.sessionUsage, color: sessionColors[colorIndex].withAlphaComponent(0.5))
            case .idle:
                // No session - no bar
                return ColorValue(0, color: NSColor.clear)
            }
        }
        self.hourlyBarChart?.setValues(barValues)

        // Analyze and show best time
        let peakAnalysis = UsageHistory.shared.analyzePeakHours()
        if let bestHour = peakAnalysis.last {  // Last = lowest usage
            let formatter = DateFormatter()
            formatter.dateFormat = "ha"
            let calendar = Calendar.current
            if let date = calendar.date(bySettingHour: bestHour.hour, minute: 0, second: 0, of: Date()) {
                let timeStr = formatter.string(from: date).lowercased()
                self.bestTimeLabel?.stringValue = "Best time: \(timeStr) (avg \(Int(bestHour.avgUsage))% usage)"
            }
        } else if chartData.isEmpty {
            self.bestTimeLabel?.stringValue = "Best time: no data yet"
        } else {
            self.bestTimeLabel?.stringValue = "Best time: collecting data..."
        }
    }

    /// Check if an hour falls within peak hours (8 AM - 2 PM ET on weekdays)
    private func isPeakHour(_ hour: Int) -> Bool {
        let now = Date()
        let etTimeZone = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar.current
        calendar.timeZone = etTimeZone

        let weekday = calendar.component(.weekday, from: now)
        let isWeekday = weekday >= 2 && weekday <= 6

        // Convert hour to ET for comparison
        // Note: This is simplified - assumes local time roughly aligns with ET
        return isWeekday && hour >= 8 && hour < 14
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        updateCountdowns()

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCountdowns()
        }
    }

    private func updateCountdowns() {
        let now = Date()

        // 5-hour countdown
        let fiveHourRemaining = fiveHourResetDate.timeIntervalSince(now)
        if fiveHourRemaining > 0 {
            self.fiveHourCountdown?.stringValue = "Resets in \(formatTimeInterval(fiveHourRemaining))"
        } else {
            self.fiveHourCountdown?.stringValue = "Resetting..."
        }

        // 7-day countdown
        let sevenDayRemaining = sevenDayResetDate.timeIntervalSince(now)
        if sevenDayRemaining > 0 {
            self.sevenDayCountdown?.stringValue = "Resets in \(formatTimeInterval(sevenDayRemaining))"
        } else {
            self.sevenDayCountdown?.stringValue = "Resetting..."
        }

        // Peak hours status
        let peakStatus = self.calculatePeakStatus()
        self.peakLabel?.stringValue = peakStatus.isPeak ? "PEAK" : "off-peak"
        self.peakLabel?.textColor = peakStatus.isPeak ? .systemOrange : .systemGreen
        self.peakTimeLabel?.stringValue = peakStatus.timeUntilChange
    }

    /// Calculate peak hours status
    /// Peak: 8 AM - 2 PM ET on weekdays (Mon-Fri)
    private func calculatePeakStatus() -> (isPeak: Bool, timeUntilChange: String) {
        let now = Date()
        let etTimeZone = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar.current
        calendar.timeZone = etTimeZone

        let components = calendar.dateComponents([.hour, .minute, .weekday], from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let weekday = components.weekday ?? 1  // 1 = Sunday, 7 = Saturday

        let isWeekday = weekday >= 2 && weekday <= 6  // Mon-Fri
        let isPeak = isWeekday && hour >= 8 && hour < 14

        var timeUntilChange: String
        if isPeak {
            // Time until 2 PM (14:00) - off-peak starts
            let minutesUntil = (14 - hour - 1) * 60 + (60 - minute)
            timeUntilChange = "off-peak in \(formatMinutesCompact(minutesUntil))"
        } else if isWeekday && hour < 8 {
            // Before peak today
            let minutesUntil = (8 - hour - 1) * 60 + (60 - minute)
            timeUntilChange = "peak in \(formatMinutesCompact(minutesUntil))"
        } else {
            // After peak or weekend - next peak is next weekday 8 AM
            var daysUntilNextWeekday: Int
            if weekday == 1 { daysUntilNextWeekday = 1 }  // Sunday -> Monday
            else if weekday == 7 { daysUntilNextWeekday = 2 }  // Saturday -> Monday
            else if hour >= 14 { daysUntilNextWeekday = 1 }  // After peak -> tomorrow
            else { daysUntilNextWeekday = 0 }

            if daysUntilNextWeekday == 0 {
                timeUntilChange = "peak soon"
            } else {
                let hoursUntil8AM = (24 - hour) + 8 + (daysUntilNextWeekday - 1) * 24
                let minutesUntil = hoursUntil8AM * 60 - minute
                timeUntilChange = "peak in \(formatMinutesCompact(minutesUntil))"
            }
        }

        return (isPeak, timeUntilChange)
    }

    private func formatMinutesCompact(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours < 24 { return mins > 0 ? "\(hours)h\(mins)m" : "\(hours)h" }
        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours > 0 ? "\(days)d\(remainingHours)h" : "\(days)d"
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            let seconds = Int(interval) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}
