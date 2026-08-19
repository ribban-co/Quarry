import AppKit

final class MessageActionBarButton: NSView {

    var onTap: () -> Void = {}

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    private let iconView: NSImageView
    private let originalImage: NSImage
    private let symbolConfig: NSImage.SymbolConfiguration
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(symbolName: String, size: CGFloat = 11, weight: NSFont.Weight = .semibold, tooltip: String) {
        symbolConfig = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(symbolConfig)
        originalImage = image ?? NSImage()
        iconView = NSImageView(image: originalImage)
        iconView.contentTintColor = .tertiaryLabelColor

        super.init(frame: .zero)

        toolTip = tooltip
        wantsLayer = true
        layer?.cornerRadius = 5

        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange, object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func flashCheckmark() {
        let checkImage = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) ?? NSImage()

        iconView.wantsLayer = true
        guard let layer = iconView.layer else { return }

        iconView.image = checkImage
        addSpringAnimation(to: layer, key: "checkPop")

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !self.isSelected else { return }
            guard let layer = self.iconView.layer else { return }

            self.iconView.image = self.originalImage
            self.updateAppearance()
            addSpringAnimation(to: layer, key: "restorePop")
        }
    }

    private func addSpringAnimation(to layer: CALayer, key: String) {
        let animation = CASpringAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: centerScaleTransform(0.5, in: layer.bounds))
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.stiffness = 300
        animation.damping = 18
        animation.mass = 0.8
        animation.duration = animation.settlingDuration
        layer.add(animation, forKey: key)
    }

    private func centerScaleTransform(_ scale: CGFloat, in bounds: CGRect) -> CATransform3D {
        let tx = bounds.width / 2
        let ty = bounds.height / 2
        var t = CATransform3DIdentity
        t = CATransform3DTranslate(t, tx, ty, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        t = CATransform3DTranslate(t, -tx, -ty, 0)
        return t
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
        refreshHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onTap()
    }

    private func refreshHoverState() {
        guard let window else {
            isHovering = false
            updateAppearance()
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        updateAppearance()
    }

    @objc private func handleAppearanceChange() {
        updateAppearance()
    }

    private func updateAppearance() {
        let showBackground = isSelected || isHovering

        if isSelected {
            iconView.contentTintColor = .labelColor
        } else if isHovering {
            iconView.contentTintColor = .secondaryLabelColor
        } else {
            iconView.contentTintColor = .tertiaryLabelColor
        }

        applyHoverBackground(showBackground)
    }
}

final class UserMessageActionBar: NSView {

    var onCopy: () -> Void = {}

    init(timestamp: Date) {
        super.init(frame: .zero)

        let timestampLabel = NSTextField(labelWithString: timestamp.formatted(date: .omitted, time: .shortened))
        timestampLabel.font = .systemFont(ofSize: 10)
        timestampLabel.textColor = .tertiaryLabelColor

        let copyButton = MessageActionBarButton(symbolName: "doc.on.doc", tooltip: "Copy text")
        copyButton.onTap = { [weak self] in
            self?.onCopy()
            copyButton.flashCheckmark()
        }

        let stack = NSStackView(views: [timestampLabel, copyButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

final class AssistantMessageActionBar: NSView {

    var onThumbsUp: () -> Void = {}
    var onThumbsDown: () -> Void = {}
    var onCopyText: () -> Void = {}
    var onRetry: () -> Void = {}

    private let thumbsUpButton: MessageActionBarButton
    private let thumbsDownButton: MessageActionBarButton

    private var currentFeedback: AgentMessageFeedback?

    override init(frame: NSRect) {
        thumbsUpButton = MessageActionBarButton(symbolName: "hand.thumbsup", tooltip: "Good response")
        thumbsDownButton = MessageActionBarButton(symbolName: "hand.thumbsdown", tooltip: "Bad response")

        super.init(frame: frame)

        let copyTextButton = MessageActionBarButton(symbolName: "doc.on.doc", tooltip: "Copy as text")
        let retryButton = MessageActionBarButton(symbolName: "arrow.counterclockwise", tooltip: "Retry")

        thumbsUpButton.onTap = { [weak self] in self?.handleThumbsUp() }
        thumbsDownButton.onTap = { [weak self] in self?.handleThumbsDown() }
        copyTextButton.onTap = { [weak self] in
            self?.onCopyText()
            copyTextButton.flashCheckmark()
        }
        retryButton.onTap = { [weak self] in self?.onRetry() }

        let stack = NSStackView(views: [thumbsUpButton, thumbsDownButton, copyTextButton, retryButton])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setFeedback(_ feedback: AgentMessageFeedback?) {
        currentFeedback = feedback
        syncButtonStates()
    }

    private func handleThumbsUp() {
        currentFeedback = currentFeedback == .up ? nil : .up
        syncButtonStates()
        onThumbsUp()
    }

    private func handleThumbsDown() {
        currentFeedback = currentFeedback == .down ? nil : .down
        syncButtonStates()
        onThumbsDown()
    }

    private func syncButtonStates() {
        thumbsUpButton.isSelected = currentFeedback == .up
        thumbsDownButton.isSelected = currentFeedback == .down
    }

    var resolvedFeedback: AgentMessageFeedback? { currentFeedback }
}
