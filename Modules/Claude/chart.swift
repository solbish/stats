//
//  chart.swift
//  Claude
//
//  Created by Claude Usage Monitor
//  Copyright 2024. All rights reserved.
//

import Cocoa
import Kit

/// Custom chart view for Claude usage history with peak hours highlighting and activity indicators
public class ClaudeHistoryChartView: NSView {
    public var points: [ChartDataPoint] = []
    public var color: NSColor = .controlAccentColor

    // Peak hours configuration (8 AM - 2 PM ET on weekdays)
    public var peakHourStart: Int = 8
    public var peakHourEnd: Int = 14
    public var peakTimeZone: TimeZone = TimeZone(identifier: "America/New_York")!
    public var showPeakHighlight: Bool = true
    public var showActivityIndicators: Bool = true

    private var cursor: NSPoint? = nil
    private let chartHours: Int = 24

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTrackingArea() {
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    public override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        setupTrackingArea()
        super.updateTrackingAreas()
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(true)

        let height = frame.height
        let width = frame.width
        let offset: CGFloat = 1 / (NSScreen.main?.backingScaleFactor ?? 1)

        // Draw peak hours shading first (behind everything)
        if showPeakHighlight {
            drawPeakHoursShading(context: context, width: width, height: height)
        }

        // Draw 50% reference line
        draw50PercentLine(context: context, width: width, height: height)

        // Draw chart line and fill
        drawChartLine(context: context, width: width, height: height, offset: offset)

        // Draw activity indicators on top
        if showActivityIndicators {
            drawActivityIndicators(width: width, height: height)
        }

        // Draw tooltip if hovering
        if let cursor = cursor {
            drawTooltip(at: cursor, width: width, height: height, offset: offset)
        }
    }

    private func drawPeakHoursShading(context: CGContext, width: CGFloat, height: CGFloat) {
        let now = Date()
        var calendar = Calendar.current
        calendar.timeZone = peakTimeZone

        let components = calendar.dateComponents([.weekday], from: now)
        // Show peak hours for historical data (yesterday's peaks if visible)
        // Peak hours are 8 AM - 2 PM ET on weekdays, but we show the shading
        // for any visible peak hours in the 24-hour window

        // Calculate x positions for peak hours within 24-hour window
        // Chart shows last 24 hours, with "now" at the right edge
        let chartStartTime = now.addingTimeInterval(-Double(chartHours) * 3600)

        // Find peak hour boundaries for today
        let todayStart = calendar.startOfDay(for: now)

        // Today's peak window
        let peakStart = calendar.date(bySettingHour: peakHourStart, minute: 0, second: 0, of: todayStart)!
        let peakEnd = calendar.date(bySettingHour: peakHourEnd, minute: 0, second: 0, of: todayStart)!

        // Yesterday's peak window (if visible in 24h window)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let yesterdayPeakStart = calendar.date(bySettingHour: peakHourStart, minute: 0, second: 0, of: yesterdayStart)!
        let yesterdayPeakEnd = calendar.date(bySettingHour: peakHourEnd, minute: 0, second: 0, of: yesterdayStart)!

        // Draw both peak windows if they fall within our chart range and are weekdays
        let peakWindows = [
            (yesterdayPeakStart, yesterdayPeakEnd, yesterdayStart),
            (peakStart, peakEnd, todayStart)
        ]

        for (windowStart, windowEnd, dayStart) in peakWindows {
            // Check if this day is a weekday (Mon-Fri)
            let dayWeekday = calendar.component(.weekday, from: dayStart)
            let isDayWeekday = dayWeekday >= 2 && dayWeekday <= 6
            if !isDayWeekday { continue }  // Skip weekends

            // Check if this peak window is visible in our chart
            if windowEnd < chartStartTime { continue }  // Completely in the past
            if windowStart > now { continue }  // Completely in the future

            // Clamp to chart bounds
            let visibleStart = max(windowStart, chartStartTime)
            let visibleEnd = min(windowEnd, now)

            // Convert to x coordinates
            let totalSeconds = Double(chartHours) * 3600
            let startOffset = visibleStart.timeIntervalSince(chartStartTime)
            let endOffset = visibleEnd.timeIntervalSince(chartStartTime)

            let xStart = CGFloat(startOffset / totalSeconds) * width
            let xEnd = CGFloat(endOffset / totalSeconds) * width

            // Draw shaded region
            let peakRect = NSRect(x: xStart, y: 0, width: xEnd - xStart, height: height)
            NSColor.systemOrange.withAlphaComponent(0.1).setFill()
            context.fill(peakRect)

            // Draw subtle border lines at peak boundaries
            NSColor.systemOrange.withAlphaComponent(0.3).setStroke()
            context.setLineWidth(0.5)

            if xStart > 0 {
                context.move(to: CGPoint(x: xStart, y: 0))
                context.addLine(to: CGPoint(x: xStart, y: height))
                context.strokePath()
            }
            if xEnd < width {
                context.move(to: CGPoint(x: xEnd, y: 0))
                context.addLine(to: CGPoint(x: xEnd, y: height))
                context.strokePath()
            }
        }
    }

    private func draw50PercentLine(context: CGContext, width: CGFloat, height: CGFloat) {
        let y = height * 0.5  // 50% line

        // Draw dashed line
        context.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.move(to: CGPoint(x: 0, y: y))
        context.addLine(to: CGPoint(x: width, y: y))
        context.strokePath()

        // Reset dash
        context.setLineDash(phase: 0, lengths: [])
    }

    private func drawChartLine(context: CGContext, width: CGFloat, height: CGFloat, offset: CGFloat) {
        guard !points.isEmpty else { return }

        let maxValue: Double = 1.0  // Fixed at 100% for consistent scale
        let now = Date()
        let chartStartTime = now.addingTimeInterval(-Double(chartHours) * 3600)
        let totalSeconds = Double(chartHours) * 3600

        // Build line path
        let linePath = NSBezierPath()
        var linePoints: [(point: CGPoint, data: ChartDataPoint)] = []

        for (index, dataPoint) in points.enumerated() {
            let x = CGFloat(dataPoint.timestamp.timeIntervalSince(chartStartTime) / totalSeconds) * width
            let y = CGFloat(dataPoint.value / maxValue) * (height - 2) + 1

            let point = CGPoint(x: x, y: y)
            linePoints.append((point: point, data: dataPoint))

            if index == 0 {
                linePath.move(to: point)
            } else {
                linePath.line(to: point)
            }
        }

        // Stroke line
        color.setStroke()
        linePath.lineWidth = offset
        linePath.stroke()

        // Fill area under line
        if linePoints.count > 1 {
            let fillPath = linePath.copy() as! NSBezierPath
            fillPath.line(to: CGPoint(x: linePoints.last!.point.x, y: 0))
            fillPath.line(to: CGPoint(x: linePoints.first!.point.x, y: 0))
            fillPath.close()

            let gradient = NSGradient(colors: [
                color.withAlphaComponent(0.3),
                color.withAlphaComponent(0.6)
            ])
            gradient?.draw(in: fillPath, angle: 90)
        }
    }

    private func drawActivityIndicators(width: CGFloat, height: CGFloat) {
        guard !points.isEmpty else { return }

        let maxValue: Double = 1.0  // Fixed at 100% for consistent scale
        let now = Date()
        let chartStartTime = now.addingTimeInterval(-Double(chartHours) * 3600)
        let totalSeconds = Double(chartHours) * 3600

        for dataPoint in points {
            let x = CGFloat(dataPoint.timestamp.timeIntervalSince(chartStartTime) / totalSeconds) * width
            let y = CGFloat(dataPoint.value / maxValue) * (height - 2) + 1

            if dataPoint.hasIntenseActivity {
                // Intense activity: larger red dot (5px)
                let dotSize: CGFloat = 5
                let dotRect = NSRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            } else if dataPoint.hasActivity {
                // Normal activity: smaller orange dot (3px)
                let dotSize: CGFloat = 3
                let dotRect = NSRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }

    private func drawTooltip(at cursor: NSPoint, width: CGFloat, height: CGFloat, offset: CGFloat) {
        guard !points.isEmpty else { return }

        let maxValue: Double = 1.0  // Fixed at 100% for consistent scale
        let now = Date()
        let chartStartTime = now.addingTimeInterval(-Double(chartHours) * 3600)
        let totalSeconds = Double(chartHours) * 3600

        // Find nearest point
        var nearest: (point: CGPoint, data: ChartDataPoint)?
        var minDistance: CGFloat = .greatestFiniteMagnitude

        for dataPoint in points {
            let x = CGFloat(dataPoint.timestamp.timeIntervalSince(chartStartTime) / totalSeconds) * width
            let y = CGFloat(dataPoint.value / maxValue) * (height - 2) + 1
            let distance = abs(x - cursor.x)

            if distance < minDistance {
                minDistance = distance
                nearest = (CGPoint(x: x, y: y), dataPoint)
            }
        }

        guard let nearest = nearest else { return }

        // Draw vertical guide line
        let vLine = NSBezierPath()
        vLine.setLineDash([4, 4], count: 2, phase: 0)
        vLine.move(to: CGPoint(x: cursor.x, y: 0))
        vLine.line(to: CGPoint(x: cursor.x, y: height))
        NSColor.tertiaryLabelColor.setStroke()
        vLine.lineWidth = offset
        vLine.stroke()

        // Draw dot at nearest point
        let dotSize: CGFloat = 4
        let dotRect = NSRect(x: nearest.point.x - dotSize/2, y: nearest.point.y - dotSize/2, width: dotSize, height: dotSize)
        NSColor.systemRed.setStroke()
        NSBezierPath(ovalIn: dotRect).stroke()

        // Draw tooltip
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeStr = formatter.string(from: nearest.data.timestamp)
        let valueStr = String(format: "%.0f%%", nearest.data.value * 100)

        var tooltipText = "\(valueStr) @ \(timeStr)"
        if nearest.data.hasIntenseActivity {
            tooltipText += " (spike!)"
        } else if nearest.data.hasActivity {
            tooltipText += " (active)"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let attrStr = NSAttributedString(string: tooltipText, attributes: attributes)
        let textSize = attrStr.size()

        // Position tooltip to the right of cursor, or left if near edge
        var tooltipX = nearest.point.x + 6
        if tooltipX + textSize.width + 8 > width {
            tooltipX = nearest.point.x - textSize.width - 14
        }
        let tooltipY = min(max(nearest.point.y - 6, 2), height - textSize.height - 4)

        // Draw tooltip background
        let bgRect = NSRect(x: tooltipX - 4, y: tooltipY - 2, width: textSize.width + 8, height: textSize.height + 4)
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()

        // Draw tooltip text
        attrStr.draw(at: NSPoint(x: tooltipX, y: tooltipY))
    }

    // MARK: - Mouse Events

    public override func mouseEntered(with event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    public override func mouseMoved(with event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        cursor = nil
        needsDisplay = true
    }
}
