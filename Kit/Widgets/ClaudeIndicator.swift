//
//  ClaudeIndicator.swift
//  Kit
//
//  Widget tailored to the Claude module: surfaces both the 5h and 7d windows
//  in the menu bar, with optional "on pace / over / under" coloring on the
//  7-day signal. Lives in Kit because widget_t.new() needs to instantiate it.
//

import Cocoa

public enum ClaudeIndicatorPaceStatus: Int { case under = -1, onPace = 0, over = 1 }

public enum ClaudeIndicatorStyle: String, CaseIterable {
    case dualConcentric     = "dual_concentric"
    case dualSplit          = "dual_split"
    case dualTachometer     = "dual_tachometer"
    case singleWithPaceTick = "single_with_pace_tick"

    public var label: String {
        switch self {
        case .dualConcentric:     return "Dual concentric rings"
        case .dualSplit:          return "Dual split rings"
        case .dualTachometer:     return "Dual tachometers"
        case .singleWithPaceTick: return "Single ring + pace tick"
        }
    }

    /// True if the widget needs roughly 2× width (side-by-side glyphs).
    public var isWide: Bool {
        switch self {
        case .dualSplit, .dualTachometer: return true
        case .dualConcentric, .singleWithPaceTick: return false
        }
    }
}

public class ClaudeIndicatorView: NSView {
    private let stateQueue = DispatchQueue(label: "eu.exelban.Stats.Widgets.ClaudeIndicator", attributes: .concurrent)

    private var fiveHourUtil: Double = 0
    private var sevenDayUtil: Double = 0
    private var paceStatus: ClaudeIndicatorPaceStatus = .onPace
    private var weekElapsedFraction: Double = 0
    private var sevenDayDominates: Bool = false

    public var style: ClaudeIndicatorStyle = .dualConcentric {
        didSet {
            guard oldValue != self.style else { return }
            self.needsDisplay = true
        }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setValue(fiveHourUtil: Double, sevenDayUtil: Double, paceStatus: ClaudeIndicatorPaceStatus, weekElapsedFraction: Double, sevenDayDominates: Bool) {
        let f = max(0, min(100, fiveHourUtil))
        let s = max(0, min(100, sevenDayUtil))
        let e = max(0, min(1, weekElapsedFraction))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let changed = self.fiveHourUtil != f
                || self.sevenDayUtil != s
                || self.paceStatus != paceStatus
                || self.weekElapsedFraction != e
                || self.sevenDayDominates != sevenDayDominates
            self.fiveHourUtil = f
            self.sevenDayUtil = s
            self.paceStatus = paceStatus
            self.weekElapsedFraction = e
            self.sevenDayDominates = sevenDayDominates
            if changed { self.needsDisplay = true }
        }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(true)

        switch self.style {
        case .dualConcentric:     self.drawDualConcentric(ctx)
        case .dualSplit:          self.drawDualSplit(ctx)
        case .dualTachometer:     self.drawDualTachometer(ctx)
        case .singleWithPaceTick: self.drawSingleWithPaceTick(ctx)
        }
    }

    private var trackColor: NSColor { NSColor.lightGray.withAlphaComponent(0.5) }
    private var fiveHourColor: NSColor { NSColor.systemBlue }
    private var sevenDayColor: NSColor {
        if self.sevenDayDominates { return NSColor.systemOrange }
        switch self.paceStatus {
        case .under:  return NSColor.systemGreen
        case .onPace: return NSColor.systemGreen
        case .over:   return NSColor.systemRed
        }
    }

    private func drawRing(_ ctx: CGContext, in rect: CGRect, lineWidth: CGFloat, fraction: Double, color: NSColor, track: NSColor) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = (min(rect.width, rect.height) - lineWidth) / 2
        guard radius > 0 else { return }
        let start: CGFloat = .pi / 2
        let full: CGFloat = 2 * .pi
        let value = CGFloat(max(0, min(1, fraction)))

        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.butt)

        ctx.setStrokeColor(track.cgColor)
        ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: start + full, clockwise: false)
        ctx.strokePath()

        if value > 0 {
            ctx.setStrokeColor(color.cgColor)
            // Fill clockwise from top (visually intuitive: 25% = top-right quadrant).
            ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: start - value * full, clockwise: true)
            ctx.strokePath()
        }
    }

    private func drawHalfRing(_ ctx: CGContext, in rect: CGRect, lineWidth: CGFloat, fraction: Double, color: NSColor, track: NSColor) {
        let center = CGPoint(x: rect.midX, y: rect.minY + 2)
        let radius = (min(rect.width, rect.height * 2) - lineWidth) / 2
        guard radius > 0 else { return }
        let start: CGFloat = .pi
        let end: CGFloat = 2 * .pi
        let value = CGFloat(max(0, min(1, fraction)))

        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.butt)

        ctx.setStrokeColor(track.cgColor)
        ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        ctx.strokePath()

        if value > 0 {
            ctx.setStrokeColor(color.cgColor)
            ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: start + value * .pi, clockwise: false)
            ctx.strokePath()
        }
    }

    private func drawDualConcentric(_ ctx: CGContext) {
        let rect = self.bounds
        let outerLine: CGFloat = max(3, min(rect.width, rect.height) * 0.18)
        let gap: CGFloat = 1.5
        let innerLine: CGFloat = max(3, outerLine * 0.85)

        self.drawRing(ctx, in: rect, lineWidth: outerLine, fraction: self.sevenDayUtil / 100, color: self.sevenDayColor, track: self.trackColor)

        let inset = outerLine + gap
        let innerRect = rect.insetBy(dx: inset, dy: inset)
        if innerRect.width > 4 && innerRect.height > 4 {
            self.drawRing(ctx, in: innerRect, lineWidth: innerLine, fraction: self.fiveHourUtil / 100, color: self.fiveHourColor, track: self.trackColor)
        }
    }

    private func drawDualSplit(_ ctx: CGContext) {
        let rect = self.bounds
        let halfWidth = rect.width / 2
        let leftRect = NSRect(x: rect.minX, y: rect.minY, width: halfWidth, height: rect.height).insetBy(dx: 1, dy: 0)
        let rightRect = NSRect(x: rect.minX + halfWidth, y: rect.minY, width: halfWidth, height: rect.height).insetBy(dx: 1, dy: 0)
        let lineWidth: CGFloat = max(3, min(leftRect.width, leftRect.height) * 0.22)

        self.drawRing(ctx, in: leftRect, lineWidth: lineWidth, fraction: self.fiveHourUtil / 100, color: self.fiveHourColor, track: self.trackColor)
        self.drawRing(ctx, in: rightRect, lineWidth: lineWidth, fraction: self.sevenDayUtil / 100, color: self.sevenDayColor, track: self.trackColor)
    }

    private func drawDualTachometer(_ ctx: CGContext) {
        let rect = self.bounds
        let halfWidth = rect.width / 2
        let leftRect = NSRect(x: rect.minX, y: rect.minY, width: halfWidth, height: rect.height).insetBy(dx: 1, dy: 0)
        let rightRect = NSRect(x: rect.minX + halfWidth, y: rect.minY, width: halfWidth, height: rect.height).insetBy(dx: 1, dy: 0)
        let lineWidth: CGFloat = max(3, min(leftRect.width, leftRect.height) * 0.28)

        self.drawHalfRing(ctx, in: leftRect, lineWidth: lineWidth, fraction: self.fiveHourUtil / 100, color: self.fiveHourColor, track: self.trackColor)
        self.drawHalfRing(ctx, in: rightRect, lineWidth: lineWidth, fraction: self.sevenDayUtil / 100, color: self.sevenDayColor, track: self.trackColor)
    }

    private func drawSingleWithPaceTick(_ ctx: CGContext) {
        let rect = self.bounds
        let lineWidth: CGFloat = max(3, min(rect.width, rect.height) * 0.22)

        self.drawRing(ctx, in: rect, lineWidth: lineWidth, fraction: self.sevenDayUtil / 100, color: self.sevenDayColor, track: self.trackColor)

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = (min(rect.width, rect.height) - lineWidth) / 2
        guard radius > 0 else { return }
        let start: CGFloat = .pi / 2
        // Match the clockwise-from-top fill: 0% → top, 25% → right, 50% → bottom.
        let angle = start - CGFloat(self.weekElapsedFraction) * 2 * .pi
        let inner = radius - lineWidth / 2 - 1
        let outer = radius + lineWidth / 2 + 1
        let p1 = CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner)
        let p2 = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)

        ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineCap(.round)
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()
    }
}

public class ClaudeIndicator: WidgetWrapper {
    private var style: ClaudeIndicatorStyle = .dualConcentric

    private let chart: ClaudeIndicatorView

    private let baseSize: CGFloat = Constants.Widget.height - (Constants.Widget.margin.y * 2) + (Constants.Widget.margin.x * 2)

    public init(title: String, preview: Bool = false) {
        let height = Constants.Widget.height - (Constants.Widget.margin.y * 2)
        self.chart = ClaudeIndicatorView(frame: NSRect(
            x: 0,
            y: 0,
            width: self.baseSize,
            height: height
        ))

        super.init(.claudeIndicator, title: title, frame: CGRect(
            x: Constants.Widget.margin.x,
            y: Constants.Widget.margin.y,
            width: self.baseSize,
            height: height
        ))

        self.canDrawConcurrently = true

        if preview {
            self.chart.setValue(
                fiveHourUtil: 24,
                sevenDayUtil: 58,
                paceStatus: .onPace,
                weekElapsedFraction: 4.0 / 7.0,
                sevenDayDominates: false
            )
        } else {
            let raw = Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_style", defaultValue: ClaudeIndicatorStyle.dualConcentric.rawValue)
            self.style = ClaudeIndicatorStyle(rawValue: raw) ?? .dualConcentric
            self.chart.style = self.style
        }

        self.applyWidth(for: self.style)
        self.addSubview(self.chart)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setValue(fiveHourUtil: Double, sevenDayUtil: Double, paceStatus: ClaudeIndicatorPaceStatus, weekElapsedFraction: Double, sevenDayDominates: Bool) {
        self.chart.setValue(
            fiveHourUtil: fiveHourUtil,
            sevenDayUtil: sevenDayUtil,
            paceStatus: paceStatus,
            weekElapsedFraction: weekElapsedFraction,
            sevenDayDominates: sevenDayDominates
        )
    }

    private func widgetWidth(for style: ClaudeIndicatorStyle) -> CGFloat {
        return style.isWide ? self.baseSize * 2 : self.baseSize
    }

    private func applyWidth(for style: ClaudeIndicatorStyle) {
        let width = self.widgetWidth(for: style)
        let height = Constants.Widget.height - (Constants.Widget.margin.y * 2)
        self.chart.frame = NSRect(x: 0, y: 0, width: width, height: height)
        self.setFrameSize(NSSize(width: width, height: height))
        self.setWidth(width)
    }

    // MARK: - Settings

    public override func settings() -> NSView {
        let view = SettingsContainerView()

        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Style"), component: selectView(
                action: #selector(self.toggleStyle),
                items: ClaudeIndicatorStyle.allCases.map { KeyValue_t(key: $0.rawValue, value: localizedString($0.label)) },
                selected: self.style.rawValue
            ))
        ]))

        return view
    }

    @objc private func toggleStyle(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let newStyle = ClaudeIndicatorStyle(rawValue: key) else { return }
        self.style = newStyle
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_style", value: newStyle.rawValue)
        self.chart.style = newStyle
        self.applyWidth(for: newStyle)
        self.chart.needsDisplay = true
    }
}
