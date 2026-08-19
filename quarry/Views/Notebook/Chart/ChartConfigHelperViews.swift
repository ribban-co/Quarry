import AppKit

final class CollapsibleSplitView: NSSplitView {
    var hideDivider = false

    override var dividerThickness: CGFloat {
        hideDivider ? 0 : super.dividerThickness
    }

    override func drawDivider(in rect: NSRect) {
        if hideDivider { return }
        super.drawDivider(in: rect)
    }
}

final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
}

final class HoverIconButton: NSView {

    private let iconView: NSImageView
    private let action: Selector
    private weak var target: AnyObject?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(symbolName: String, target: AnyObject, action: Selector) {
        self.iconView = NSImageView()
        self.target = target
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isHidden: Bool {
        didSet {
            if isHidden && isHovering {
                isHovering = false
                updateHover()
            }
        }
    }

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
        isHovering = true
        updateHover()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateHover()
    }

    override func mouseDown(with event: NSEvent) {
        _ = target?.perform(action, with: self)
    }

    private func updateHover() {
        applyHoverBackground(isHovering)
    }
}

final class FieldRowCell: NSTableCellView {

    private let hoverBackground = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let typeLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    nonisolated(unsafe) private var boundsObserver: NSObjectProtocol?
    private weak var observedClipView: NSClipView?
    private var isHovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupViews() {
        hoverBackground.wantsLayer = true
        hoverBackground.layer?.cornerRadius = 6
        hoverBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hoverBackground)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        iconView.alphaValue = 0.7
        addSubview(iconView)

        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        typeLabel.font = .systemFont(ofSize: 11)
        typeLabel.textColor = .tertiaryLabelColor
        typeLabel.alignment = .right
        typeLabel.lineBreakMode = .byTruncatingTail
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(typeLabel)

        NSLayoutConstraint.activate([
            hoverBackground.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            hoverBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            hoverBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            hoverBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            typeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 4),
            typeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            typeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            typeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 60),
        ])
    }

    func configure(name: String, iconName: String, dataType: String) {
        nameLabel.stringValue = name
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        typeLabel.stringValue = dataType.lowercased()
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        syncHoverStateWithMouse()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateHover()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateHover()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateBoundsObservation()
        syncHoverStateWithMouse()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBoundsObservation()
        syncHoverStateWithMouse()
        if window == nil {
            isHovering = false
            updateHover()
        }
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    private func updateBoundsObservation() {
        let clipView = enclosingScrollView?.contentView
        guard observedClipView !== clipView else { return }
        removeBoundsObservation()
        guard let clipView else { return }
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncHoverStateWithMouse()
            }
        }
        observedClipView = clipView
    }

    private func removeBoundsObservation() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        observedClipView = nil
    }

    private func syncHoverStateWithMouse() {
        guard let window else {
            if isHovering {
                isHovering = false
                updateHover()
            }
            return
        }

        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInView = convert(mouseInWindow, from: nil)
        let shouldHover = bounds.contains(mouseInView)
        guard shouldHover != isHovering else { return }
        isHovering = shouldHover
        updateHover()
    }

    private func updateHover() {
        hoverBackground.applyHoverBackground(isHovering)
    }
}
