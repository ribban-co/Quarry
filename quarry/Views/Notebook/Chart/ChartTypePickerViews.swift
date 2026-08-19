import AppKit

// MARK: - Chart type picker button

final class ChartTypePickerButton: NSView, NSPopoverDelegate {

    private let onSelect: (ChartBlockConfig.ChartType) -> Void
    private let iconView: ChartTypeMiniIcon
    private let label: NSTextField
    private let chevron: NSImageView
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var popover: NSPopover?
    private(set) var selectedType: ChartBlockConfig.ChartType

    init(initialType: ChartBlockConfig.ChartType, onSelect: @escaping (ChartBlockConfig.ChartType) -> Void) {
        self.selectedType = initialType
        self.onSelect = onSelect
        self.iconView = ChartTypeMiniIcon(chartType: initialType)
        self.label = NSTextField(labelWithString: initialType.displayName)
        self.chevron = NSImageView()
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        setContentHuggingPriority(.required, for: .horizontal)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(label)

        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 8, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 12),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevron.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 3),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 10),
        ])

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func updateSelection(_ type: ChartBlockConfig.ChartType) {
        selectedType = type
        label.stringValue = type.displayName
        iconView.chartType = type
        iconView.needsDisplay = true
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        refreshHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyHoverBackground(isHovering)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(isHovering)
    }

    override func mouseDown(with event: NSEvent) {
        if popover != nil {
            popover?.performClose(nil)
            popover = nil
            return
        }
        showPickerPopover()
    }

    private func refreshHoverState() {
        guard let window else {
            if isHovering { isHovering = false; applyHoverBackground(false) }
            return
        }
        let mouseInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let shouldHover = bounds.contains(mouseInView)
        if shouldHover != isHovering {
            isHovering = shouldHover
            applyHoverBackground(isHovering)
        }
    }

    // MARK: - Popover

    private func showPickerPopover() {
        let popoverVC = ChartTypePickerPopoverController(
            selectedType: selectedType
        ) { [weak self] type in
            guard let self else { return }
            self.popover?.performClose(nil)
            self.popover = nil
            self.updateSelection(type)
            self.onSelect(type)
        }

        let pop = NSPopover()
        pop.delegate = self
        pop.contentViewController = popoverVC
        pop.behavior = .transient
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        self.popover = pop
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }
}

// MARK: - Mini icon for button

final class ChartTypeMiniIcon: NSView {

    var chartType: ChartBlockConfig.ChartType

    init(chartType: ChartBlockConfig.ChartType) {
        self.chartType = chartType
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.controlAccentColor
            ctx.setStrokeColor(color.cgColor)
            ctx.setFillColor(color.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ChartIconDrawing.draw(chartType, in: bounds, ctx: ctx, mini: true)
        }
    }
}

// MARK: - Chart type picker popover

final class ChartTypePickerPopoverController: NSViewController {

    private let selectedType: ChartBlockConfig.ChartType
    private let onSelect: (ChartBlockConfig.ChartType) -> Void

    init(selectedType: ChartBlockConfig.ChartType, onSelect: @escaping (ChartBlockConfig.ChartType) -> Void) {
        self.selectedType = selectedType
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)

        for group in ChartBlockConfig.chartTypeGroups {
            let sectionHeader = NSTextField(labelWithString: group.title)
            sectionHeader.font = .systemFont(ofSize: 10, weight: .medium)
            sectionHeader.textColor = .secondaryLabelColor
            sectionHeader.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(sectionHeader)
            stack.setCustomSpacing(6, after: sectionHeader)

            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false

            for chartType in group.types {
                let tile = ChartTypeTileView(
                    chartType: chartType,
                    isSelected: chartType == selectedType
                ) { [weak self] in
                    self?.onSelect(chartType)
                }
                tile.translatesAutoresizingMaskIntoConstraints = false
                row.addArrangedSubview(tile)
                tile.widthAnchor.constraint(equalToConstant: 88).isActive = true
            }

            stack.addArrangedSubview(row)
        }

        stack.widthAnchor.constraint(equalToConstant: 310).isActive = true
        self.view = stack
    }
}

// MARK: - Chart type tile

final class ChartTypeTileView: NSView {

    private let chartType: ChartBlockConfig.ChartType
    private let isSelected: Bool
    private let action: () -> Void
    private let cardView: NSView
    private var trackingArea: NSTrackingArea?

    init(chartType: ChartBlockConfig.ChartType, isSelected: Bool, action: @escaping () -> Void) {
        self.chartType = chartType
        self.isSelected = isSelected
        self.action = action
        self.cardView = NSView()
        super.init(frame: .zero)

        wantsLayer = true
        setupViews()
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupViews() {
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 6
        cardView.layer?.borderWidth = isSelected ? 1.5 : 1
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        let drawingView = ChartTypeTileDrawingView(chartType: chartType)
        drawingView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(drawingView)

        let label = NSTextField(labelWithString: chartType.displayName)
        label.font = .systemFont(ofSize: 10)
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.heightAnchor.constraint(equalToConstant: 52),

            drawingView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            drawingView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            drawingView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            drawingView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),

            label.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 3),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func updateAppearance() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            if isSelected {
                cardView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
                cardView.layer?.backgroundColor = isDark
                    ? NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
                    : NSColor.controlAccentColor.withAlphaComponent(0.04).cgColor
            } else {
                cardView.layer?.borderColor = isDark
                    ? NSColor.white.withAlphaComponent(0.1).cgColor
                    : NSColor.black.withAlphaComponent(0.08).cgColor
                cardView.layer?.backgroundColor = nil
            }
        }
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isSelected else { return }
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            cardView.layer?.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.06).cgColor
                : NSColor.black.withAlphaComponent(0.03).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard !isSelected else { return }
        cardView.layer?.backgroundColor = nil
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }
}

// MARK: - Chart type tile drawing

final class ChartTypeTileDrawingView: NSView {

    let chartType: ChartBlockConfig.ChartType

    init(chartType: ChartBlockConfig.ChartType) {
        self.chartType = chartType
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            ChartIconDrawing.draw(chartType, in: bounds, ctx: ctx, mini: false)
        }
    }
}

// MARK: - Centralized chart icon drawing

enum ChartIconDrawing {

    static func draw(_ type: ChartBlockConfig.ChartType, in bounds: CGRect, ctx: CGContext, mini: Bool) {
        let isDark = NSAppearance.currentDrawing().isDarkMode
        let stroke = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.7 : 0.55)
        let fill = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.35 : 0.2)
        let fillStrong = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.5 : 0.35)
        let w = bounds.width
        let h = bounds.height

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch type {
        // MARK: Column
        case .groupedColumn:
            drawVerticalBars(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill, heights: [0.4, 0.7, 0.85, 0.55, 0.72])
        case .stackedColumn:
            drawStackedColumns(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill, fillStrong: fillStrong)
        case .hundredPercentStackedColumn:
            drawFullStackedColumns(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill, fillStrong: fillStrong)

        // MARK: Bar
        case .groupedBar:
            drawHorizontalBars(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill, widths: [0.6, 0.85, 0.45, 0.72])
        case .stackedBar:
            drawStackedBars(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill, fillStrong: fillStrong)
        case .hundredPercentStackedBar:
            drawFullStackedBars(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill, fillStrong: fillStrong)

        // MARK: Line & Area
        case .line:
            drawLine(ctx: ctx, w: w, h: h, stroke: stroke, mini: mini)
        case .stackedArea:
            drawArea(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill)
        case .hundredPercentStackedArea:
            drawFullArea(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill, fillStrong: fillStrong)

        // MARK: Other
        case .histogram:
            drawHistogram(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill)
        case .scatter:
            drawScatter(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill)
        case .pie:
            drawPie(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill, fillStrong: fillStrong)

        // MARK: Table
        case .pivotTable:
            drawPivotTable(ctx: ctx, w: w, h: h, stroke: stroke, fill: fill)
        }
    }

    // MARK: - Column drawings

    private static func drawVerticalBars(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor, heights: [CGFloat]) {
        let count = heights.count
        let gap = w * 0.06
        let barWidth = (w - gap * CGFloat(count - 1)) / CGFloat(count)

        for (i, barH) in heights.enumerated() {
            let x = CGFloat(i) * (barWidth + gap)
            let rect = CGRect(x: x, y: 0, width: barWidth, height: h * barH)
            let path = CGPath(roundedRect: rect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.addPath(path); ctx.setFillColor(fill.cgColor); ctx.fillPath()
            ctx.addPath(path); ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(1); ctx.strokePath()
        }
    }

    private static func drawStackedColumns(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor, fillStrong: NSColor) {
        let count = 4
        let gap = w * 0.08
        let barWidth = (w - gap * CGFloat(count - 1)) / CGFloat(count)
        let bottoms: [CGFloat] = [0.3, 0.4, 0.25, 0.35]
        let tops: [CGFloat] = [0.65, 0.85, 0.55, 0.75]

        for i in 0..<count {
            let x = CGFloat(i) * (barWidth + gap)
            let bottomH = h * bottoms[i]
            let topH = h * tops[i]
            let r1 = CGRect(x: x, y: 0, width: barWidth, height: bottomH)
            ctx.setFillColor(fillStrong.cgColor); ctx.fill(r1)
            ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(0.5); ctx.stroke(r1)
            let r2 = CGRect(x: x, y: bottomH, width: barWidth, height: topH - bottomH)
            ctx.setFillColor(fill.cgColor); ctx.fill(r2)
            ctx.setStrokeColor(stroke.cgColor); ctx.stroke(r2)
        }
    }

    private static func drawFullStackedColumns(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor, fillStrong: NSColor) {
        let count = 5
        let gap = w * 0.06
        let barWidth = (w - gap * CGFloat(count - 1)) / CGFloat(count)
        let splits: [CGFloat] = [0.4, 0.55, 0.35, 0.6, 0.45]

        for i in 0..<count {
            let x = CGFloat(i) * (barWidth + gap)
            let splitH = h * splits[i]
            let r1 = CGRect(x: x, y: 0, width: barWidth, height: splitH)
            ctx.setFillColor(fillStrong.cgColor); ctx.fill(r1)
            ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(0.5); ctx.stroke(r1)
            let r2 = CGRect(x: x, y: splitH, width: barWidth, height: h - splitH)
            ctx.setFillColor(fill.cgColor); ctx.fill(r2)
            ctx.setStrokeColor(stroke.cgColor); ctx.stroke(r2)
        }
    }

    // MARK: - Bar (horizontal) drawings

    private static func drawHorizontalBars(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor, widths: [CGFloat]) {
        let count = widths.count
        let gap = h * 0.08
        let barHeight = (h - gap * CGFloat(count - 1)) / CGFloat(count)

        for (i, barW) in widths.enumerated() {
            let y = h - CGFloat(i + 1) * barHeight - CGFloat(i) * gap
            let rect = CGRect(x: 0, y: y, width: w * barW, height: barHeight)
            let path = CGPath(roundedRect: rect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.addPath(path); ctx.setFillColor(fill.cgColor); ctx.fillPath()
            ctx.addPath(path); ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(1); ctx.strokePath()
        }
    }

    private static func drawStackedBars(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor, fillStrong: NSColor) {
        let count = 3
        let gap = h * 0.1
        let barHeight = (h - gap * CGFloat(count - 1)) / CGFloat(count)
        let lefts: [CGFloat] = [0.35, 0.45, 0.3]
        let rights: [CGFloat] = [0.7, 0.85, 0.6]

        for i in 0..<count {
            let y = h - CGFloat(i + 1) * barHeight - CGFloat(i) * gap
            let leftW = w * lefts[i]
            let r1 = CGRect(x: 0, y: y, width: leftW, height: barHeight)
            ctx.setFillColor(fillStrong.cgColor); ctx.fill(r1)
            ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(0.5); ctx.stroke(r1)
            let r2 = CGRect(x: leftW, y: y, width: w * rights[i] - leftW, height: barHeight)
            ctx.setFillColor(fill.cgColor); ctx.fill(r2)
            ctx.setStrokeColor(stroke.cgColor); ctx.stroke(r2)
        }
    }

    private static func drawFullStackedBars(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor, fillStrong: NSColor) {
        let count = 3
        let gap = h * 0.1
        let barHeight = (h - gap * CGFloat(count - 1)) / CGFloat(count)
        let splits: [CGFloat] = [0.45, 0.6, 0.35]

        for i in 0..<count {
            let y = h - CGFloat(i + 1) * barHeight - CGFloat(i) * gap
            let splitW = w * splits[i]
            let r1 = CGRect(x: 0, y: y, width: splitW, height: barHeight)
            ctx.setFillColor(fillStrong.cgColor); ctx.fill(r1)
            ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(0.5); ctx.stroke(r1)
            let r2 = CGRect(x: splitW, y: y, width: w - splitW, height: barHeight)
            ctx.setFillColor(fill.cgColor); ctx.fill(r2)
            ctx.setStrokeColor(stroke.cgColor); ctx.stroke(r2)
        }
    }

    // MARK: - Line & Area drawings

    private static func drawLine(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, mini: Bool) {
        let points: [(CGFloat, CGFloat)] = [(0.0, 0.25), (0.15, 0.5), (0.35, 0.35), (0.55, 0.7), (0.75, 0.55), (1.0, 0.8)]

        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(mini ? 1.5 : 2)
        for (i, pt) in points.enumerated() {
            let p = CGPoint(x: pt.0 * w, y: pt.1 * h)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.strokePath()

        if !mini {
            ctx.setFillColor(stroke.cgColor)
            for pt in points {
                ctx.fillEllipse(in: CGRect(x: pt.0 * w - 2, y: pt.1 * h - 2, width: 4, height: 4))
            }
        }
    }

    private static func drawArea(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor) {
        let points: [(CGFloat, CGFloat)] = [(0.0, 0.2), (0.2, 0.5), (0.4, 0.35), (0.6, 0.7), (0.8, 0.55), (1.0, 0.75)]

        ctx.move(to: CGPoint(x: 0, y: 0))
        for pt in points { ctx.addLine(to: CGPoint(x: pt.0 * w, y: pt.1 * h)) }
        ctx.addLine(to: CGPoint(x: w, y: 0))
        ctx.closePath()
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()

        ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(1.5)
        for (i, pt) in points.enumerated() {
            let p = CGPoint(x: pt.0 * w, y: pt.1 * h)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.strokePath()
    }

    private static func drawFullArea(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor, fillStrong: NSColor) {
        let top: [(CGFloat, CGFloat)] = [(0.0, 0.85), (0.25, 0.75), (0.5, 0.9), (0.75, 0.8), (1.0, 0.95)]
        let mid: [(CGFloat, CGFloat)] = [(0.0, 0.45), (0.25, 0.4), (0.5, 0.55), (0.75, 0.5), (1.0, 0.6)]

        // Top band
        ctx.move(to: CGPoint(x: mid[0].0 * w, y: mid[0].1 * h))
        for pt in mid.dropFirst() { ctx.addLine(to: CGPoint(x: pt.0 * w, y: pt.1 * h)) }
        for pt in top.reversed() { ctx.addLine(to: CGPoint(x: pt.0 * w, y: pt.1 * h)) }
        ctx.closePath()
        ctx.setFillColor(fill.cgColor); ctx.fillPath()

        // Bottom band
        ctx.move(to: CGPoint(x: 0, y: 0))
        for pt in mid { ctx.addLine(to: CGPoint(x: pt.0 * w, y: pt.1 * h)) }
        ctx.addLine(to: CGPoint(x: w, y: 0))
        ctx.closePath()
        ctx.setFillColor(fillStrong.cgColor); ctx.fillPath()

        // Lines
        ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(1)
        for pts in [mid, top] {
            for (i, pt) in pts.enumerated() {
                let p = CGPoint(x: pt.0 * w, y: pt.1 * h)
                if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
            }
            ctx.strokePath()
        }
    }

    // MARK: - Other drawings

    private static func drawHistogram(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor) {
        let count = 7
        let barWidth = w / CGFloat(count)
        let heights: [CGFloat] = [0.15, 0.3, 0.55, 0.85, 0.65, 0.35, 0.15]

        for (i, barH) in heights.enumerated() {
            let rect = CGRect(x: CGFloat(i) * barWidth, y: 0, width: barWidth, height: h * barH)
            ctx.setFillColor(fill.cgColor); ctx.fill(rect)
            ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(0.5); ctx.stroke(rect)
        }
    }

    private static func drawScatter(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor) {
        let dots: [(CGFloat, CGFloat)] = [
            (0.1, 0.2), (0.2, 0.35), (0.25, 0.15), (0.35, 0.5),
            (0.4, 0.4), (0.5, 0.55), (0.55, 0.7), (0.6, 0.45),
            (0.7, 0.65), (0.75, 0.8), (0.85, 0.6), (0.9, 0.75)
        ]
        let r: CGFloat = 2.5
        ctx.setFillColor(stroke.cgColor)
        for d in dots {
            ctx.fillEllipse(in: CGRect(x: d.0 * w - r, y: d.1 * h - r, width: r * 2, height: r * 2))
        }
    }

    private static func drawPie(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor, fillStrong: NSColor) {
        let cx = w / 2
        let cy = h / 2
        let radius = min(w, h) / 2 - 1

        let slices: [(CGFloat, NSColor)] = [
            (0.4, fillStrong),
            (0.25, fill),
            (0.35, NSColor.controlAccentColor.withAlphaComponent(
                NSAppearance.currentDrawing().isDarkMode ? 0.15 : 0.1)),
        ]

        var startAngle: CGFloat = 0
        for (fraction, color) in slices {
            let endAngle = startAngle + fraction * .pi * 2
            ctx.move(to: CGPoint(x: cx, y: cy))
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            ctx.closePath()
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()

            ctx.move(to: CGPoint(x: cx, y: cy))
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            ctx.closePath()
            ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(0.5); ctx.strokePath()

            startAngle = endAngle
        }
    }

    private static func drawPivotTable(ctx: CGContext, w: CGFloat, h: CGFloat, stroke: NSColor, fill: NSColor) {
        let cols = 4
        let rows = 3
        let cellW = w / CGFloat(cols)
        let cellH = h / CGFloat(rows)

        for r in 0..<rows {
            for c in 0..<cols {
                let rect = CGRect(x: CGFloat(c) * cellW, y: CGFloat(r) * cellH, width: cellW, height: cellH)
                let isHeader = r == rows - 1 || c == 0
                ctx.setFillColor(isHeader ? fill.cgColor : NSColor.clear.cgColor)
                ctx.fill(rect)
                ctx.setStrokeColor(stroke.withAlphaComponent(0.4).cgColor)
                ctx.setLineWidth(0.5)
                ctx.stroke(rect)
            }
        }
    }
}
