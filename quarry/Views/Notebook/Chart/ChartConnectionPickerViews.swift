import AppKit

final class NotebookArtworkView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAppearanceChange() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 2

        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode

            let circleColor = isDark
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.black.withAlphaComponent(0.06)
            ctx.setStrokeColor(circleColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            ctx.strokePath()

            let inset: CGFloat = 18
            let originX = center.x - radius + inset
            let originY = center.y - radius + inset
            let endX = center.x + radius - inset
            let endY = center.y + radius - inset

            let axisColor = isDark
                ? NSColor.white.withAlphaComponent(0.2)
                : NSColor.black.withAlphaComponent(0.15)
            ctx.setStrokeColor(axisColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)

            ctx.move(to: CGPoint(x: originX, y: originY))
            ctx.addLine(to: CGPoint(x: originX, y: endY))
            ctx.strokePath()

            ctx.move(to: CGPoint(x: originX, y: originY))
            ctx.addLine(to: CGPoint(x: endX, y: originY))
            ctx.strokePath()

            let lineColor = isDark
                ? NSColor.controlAccentColor.withAlphaComponent(0.6)
                : NSColor.controlAccentColor.withAlphaComponent(0.5)
            ctx.setStrokeColor(lineColor.cgColor)
            ctx.setLineWidth(2)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)

            let chartWidth = endX - originX - 4
            let chartHeight = endY - originY - 4
            let baseX = originX + 4
            let baseY = originY + 4

            let points: [(CGFloat, CGFloat)] = [
                (0.0, 0.15),
                (0.18, 0.35),
                (0.35, 0.28),
                (0.52, 0.55),
                (0.7, 0.48),
                (0.85, 0.78),
                (1.0, 0.92),
            ]

            if let first = points.first {
                ctx.move(to: CGPoint(
                    x: baseX + first.0 * chartWidth,
                    y: baseY + first.1 * chartHeight
                ))
            }
            for point in points.dropFirst() {
                ctx.addLine(to: CGPoint(
                    x: baseX + point.0 * chartWidth,
                    y: baseY + point.1 * chartHeight
                ))
            }
            ctx.strokePath()

            let dotColor = isDark
                ? NSColor.controlAccentColor.withAlphaComponent(0.4)
                : NSColor.controlAccentColor.withAlphaComponent(0.35)
            ctx.setFillColor(dotColor.cgColor)
            for point in points {
                let px = baseX + point.0 * chartWidth
                let py = baseY + point.1 * chartHeight
                ctx.fillEllipse(in: CGRect(x: px - 2, y: py - 2, width: 4, height: 4))
            }
        }
    }
}

final class ConnectionPickerDropdown: NSView, NSPopoverDelegate {

    private let connections: [Connection]
    private let queryDataSourcesProvider: (() -> [NotebookDataController.QueryDataSource])?
    private let onSelect: (Connection) -> Void
    private let onSelectQuerySource: ((NotebookDataController.QueryDataSource) -> Void)?
    private let iconView: NSImageView
    private let label: NSTextField
    private let chevron: NSImageView
    private let spinner: NSProgressIndicator
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var popover: NSPopover?
    private(set) var isLoading = false
    private var labelLeadingNoIcon: NSLayoutConstraint!
    private var labelLeadingWithIcon: NSLayoutConstraint!

    init(
        connections: [Connection],
        queryDataSourcesProvider: (() -> [NotebookDataController.QueryDataSource])? = nil,
        onSelect: @escaping (Connection) -> Void,
        onSelectQuerySource: ((NotebookDataController.QueryDataSource) -> Void)? = nil
    ) {
        self.connections = connections
        self.queryDataSourcesProvider = queryDataSourcesProvider
        self.onSelect = onSelect
        self.onSelectQuerySource = onSelectQuerySource
        self.iconView = NSImageView()
        self.label = NSTextField(labelWithString: "Choose a data source")
        self.chevron = NSImageView()
        self.spinner = NSProgressIndicator()
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        updateBorderColor()

        iconView.isHidden = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        labelLeadingNoIcon = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
        labelLeadingWithIcon = label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4)
        labelLeadingNoIcon.isActive = true

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),

            spinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: .appAppearanceDidChange, object: nil)
    }

    func setConnecting(_ connecting: Bool, name: String? = nil, iconName: String? = nil) {
        isLoading = connecting
        chevron.isHidden = connecting
        spinner.isHidden = !connecting
        if connecting {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        if let name {
            label.stringValue = name
            label.textColor = .secondaryLabelColor
        }
        if let iconName {
            let img = NSImage(named: iconName)
            img?.size = NSSize(width: 14, height: 14)
            iconView.image = img
            iconView.isHidden = false
            labelLeadingNoIcon.isActive = false
            labelLeadingWithIcon.isActive = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appearanceChanged() {
        updateBorderColor()
    }

    private func updateBorderColor() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            layer?.borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.1).cgColor
                : NSColor.black.withAlphaComponent(0.08).cgColor
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
        showConnectionsPopover()
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

    private func showConnectionsPopover() {
        let popoverVC = SourceConnectionsPopoverController(
            connections: connections,
            queryDataSources: queryDataSourcesProvider?() ?? [],
            onSelect: { [weak self] connection in
                self?.popover?.performClose(nil)
                self?.popover = nil
                self?.onSelect(connection)
            },
            onSelectQuerySource: { [weak self] source in
                self?.popover?.performClose(nil)
                self?.popover = nil
                self?.onSelectQuerySource?(source)
            }
        )

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
