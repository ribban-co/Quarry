import Cocoa

@MainActor
final class KeymapSettingsViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private let contentStackView = NSStackView()

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        documentView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.orientation = .vertical
        contentStackView.alignment = .leading
        contentStackView.spacing = 20
        contentStackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        scrollView.documentView = documentView
        documentView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStackView.setViews(
            KeymapSettingsContent.sections.map(makeSectionView),
            in: .leading
        )
    }

    private func makeSectionView(_ section: KeymapShortcutSection) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: section.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let cardView = NSVisualEffectView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.material = .contentBackground
        cardView.blendingMode = .withinWindow
        cardView.state = .followsWindowActiveState
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 12
        cardView.layer?.masksToBounds = true

        let rowsStackView = NSStackView()
        rowsStackView.translatesAutoresizingMaskIntoConstraints = false
        rowsStackView.orientation = .vertical
        rowsStackView.alignment = .leading
        rowsStackView.spacing = 0

        for (index, item) in section.items.enumerated() {
            let rowView = makeRowView(item)
            rowView.widthAnchor.constraint(equalTo: rowsStackView.widthAnchor).isActive = true
            rowsStackView.addArrangedSubview(rowView)

            if index < section.items.count - 1 {
                let separatorView = NSView()
                separatorView.translatesAutoresizingMaskIntoConstraints = false
                separatorView.wantsLayer = true
                separatorView.layer?.backgroundColor = NSColor.separatorColor.cgColor
                separatorView.heightAnchor.constraint(equalToConstant: 1).isActive = true
                separatorView.widthAnchor.constraint(equalTo: rowsStackView.widthAnchor).isActive = true
                rowsStackView.addArrangedSubview(separatorView)
            }
        }

        cardView.addSubview(rowsStackView)

        NSLayoutConstraint.activate([
            rowsStackView.topAnchor.constraint(equalTo: cardView.topAnchor),
            rowsStackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            rowsStackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            rowsStackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(cardView)
        container.setCustomSpacing(10, after: titleLabel)
        container.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
        cardView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        return container
    }

    private func makeRowView(_ item: KeymapShortcutItem) -> NSView {
        let rowView = NSStackView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.orientation = .horizontal
        rowView.alignment = .centerY
        rowView.spacing = 12
        rowView.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        let actionLabel = NSTextField(labelWithString: item.action)
        actionLabel.font = .systemFont(ofSize: 13)
        actionLabel.lineBreakMode = .byTruncatingTail
        actionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let shortcutBadge = KeymapShortcutBadgeView(shortcut: item.shortcut)

        rowView.addArrangedSubview(actionLabel)
        rowView.addArrangedSubview(spacer)
        rowView.addArrangedSubview(shortcutBadge)

        return rowView
    }
}

private final class KeymapShortcutBadgeView: NSView {
    init(shortcut: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12).cgColor

        let label = NSTextField(labelWithString: shortcut)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor

        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
