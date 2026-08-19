import AppKit

final class AgentEmptyStateView: NSView {

    static let notebookSuggestions: [(icon: String, label: String)] = [
        ("chart.bar.xaxis", "Analyze trends over time"),
        ("sparkle.magnifyingglass", "Explore and visualize this data"),
        ("text.below.photo", "Build a dashboard with insights"),
    ]

    static let tableSuggestions: [(icon: String, label: String)] = [
        ("tablecells", "Summarize this table"),
        ("sparkle.magnifyingglass", "Find interesting patterns in this data"),
        ("questionmark.circle", "Explain what each column means"),
    ]

    var onSuggestionSelected: (String) -> Void = { _ in }

    private let stackView: NSStackView

    init(suggestions: [(icon: String, label: String)] = AgentEmptyStateView.notebookSuggestions) {
        let rows = suggestions

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0

        super.init(frame: .zero)

        for row in rows {
            let suggestionRow = AgentSuggestionRowView(iconName: row.icon, label: row.label) { [weak self] in
                self?.onSuggestionSelected(row.label)
            }
            stackView.addArrangedSubview(suggestionRow)
            suggestionRow.translatesAutoresizingMaskIntoConstraints = false
        }

        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

// MARK: - Suggestion Row

private final class AgentSuggestionRowView: NSView {

    private let iconView: NSImageView
    private let textLabel: NSTextField
    private let action: () -> Void
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(iconName: String, label: String, action: @escaping () -> Void) {
        self.action = action

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        iconView = NSImageView(image: image ?? NSImage())
        iconView.contentTintColor = .secondaryLabelColor

        textLabel = NSTextField(labelWithString: label)
        textLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        textLabel.textColor = .secondaryLabelColor

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8

        let stack = NSStackView(views: [iconView, textLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])

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
        applyHoverBackground(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(false)
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }

    private func refreshHoverState() {
        guard let window else {
            isHovering = false
            applyHoverBackground(false)
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        applyHoverBackground(isHovering)
    }

    @objc private func handleAppearanceChange() {
        applyHoverBackground(isHovering)
    }
}
