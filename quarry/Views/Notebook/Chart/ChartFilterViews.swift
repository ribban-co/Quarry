import AppKit

final class FilterChipView: NSView {

    enum Style { case plain, active }

    private let action: () -> Void
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(icon: String, title: String?, style: Style, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        iconView.contentTintColor = style == .active ? .controlAccentColor : .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
        ])

        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = style == .active ? .controlAccentColor : .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
        refreshHoverState()
    }

    private func refreshHoverState() {
        guard let window else { return }
        let loc = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let inside = bounds.contains(loc)
        if isHovering != inside {
            isHovering = inside
            updateHover()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateHover()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateHover()
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }

    private func updateHover() {
        applyHoverBackground(isHovering)
    }
}

final class FilterPillView: NSView {

    private let filter: ChartFilterCondition
    private let isValid: Bool
    private let onEdit: (NSView) -> Void
    private let onRemove: () -> Void
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(filter: ChartFilterCondition, isValid: Bool = true, onEdit: @escaping (NSView) -> Void, onRemove: @escaping () -> Void) {
        self.filter = filter
        self.isValid = isValid
        self.onEdit = onEdit
        self.onRemove = onRemove
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        updateBorderColor()

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        if !isValid {
            let warningIcon = NSImageView()
            warningIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Invalid field")
            warningIcon.symbolConfiguration = .init(pointSize: 10, weight: .medium)
            warningIcon.contentTintColor = .systemOrange
            warningIcon.translatesAutoresizingMaskIntoConstraints = false
            warningIcon.setContentHuggingPriority(.required, for: .horizontal)
            stack.addArrangedSubview(warningIcon)
            NSLayoutConstraint.activate([
                warningIcon.widthAnchor.constraint(equalToConstant: 14),
                warningIcon.heightAnchor.constraint(equalToConstant: 14),
            ])
        }

        let label = NSTextField(labelWithString: filter.displaySummary)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = isValid ? .secondaryLabelColor : .systemOrange
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(label)

        let closeButton = NSButton()
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove filter")
        closeButton.symbolConfiguration = .init(pointSize: 8, weight: .bold)
        closeButton.bezelStyle = .accessoryBar
        closeButton.isBordered = false
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(removeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),

            label.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: .appAppearanceDidChange, object: nil)

        if !isValid {
            installCustomTooltip("Field \"\(filter.field)\" does not exist in current table", position: .top, delay: 0, spacing: 4)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func removeClicked() {
        onRemove()
    }

    @objc private func appearanceChanged() {
        updateBorderColor()
    }

    private func updateBorderColor() {
        if !isValid {
            layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.5).cgColor
            return
        }
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            layer?.borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.12).cgColor
                : NSColor.black.withAlphaComponent(0.1).cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
        refreshHoverState()
    }

    private func refreshHoverState() {
        guard let window else { return }
        let loc = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let inside = bounds.contains(loc)
        if isHovering != inside {
            isHovering = inside
            updateHover()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateHover()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateHover()
    }

    override func mouseDown(with event: NSEvent) {
        onEdit(self)
    }

    private func updateHover() {
        applyHoverBackground(isHovering)
    }
}
