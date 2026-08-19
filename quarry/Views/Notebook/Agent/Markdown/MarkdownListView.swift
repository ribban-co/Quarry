import AppKit

final class MarkdownListView: NSView {

    private let stackView: NSStackView
    private var isOrdered: Bool

    init(items: [ListItem], ordered: Bool) {
        stackView = NSStackView()
        isOrdered = ordered
        super.init(frame: .zero)
        setupStack()
        buildItems(items)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(items: [ListItem], ordered: Bool) {
        isOrdered = ordered
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buildItems(items)
        invalidateIntrinsicContentSize()
    }

    private func setupStack() {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func buildItems(_ items: [ListItem]) {
        for (index, item) in items.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 4
            row.translatesAutoresizingMaskIntoConstraints = false

            let bullet: String
            if item.isTask {
                bullet = item.isChecked ? "\u{2611}" : "\u{2610}"
            } else if isOrdered {
                bullet = "\(index + 1)."
            } else {
                bullet = "\u{2022}"
            }

            let bulletLabel = NSTextField(labelWithString: bullet)
            bulletLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
            bulletLabel.textColor = .secondaryLabelColor
            bulletLabel.alignment = .right
            bulletLabel.translatesAutoresizingMaskIntoConstraints = false
            bulletLabel.widthAnchor.constraint(equalToConstant: 20).isActive = true
            bulletLabel.setContentHuggingPriority(.required, for: .horizontal)

            let textField = NSTextField(labelWithAttributedString: MarkdownInlineRenderer.render(item.text))
            textField.configureForMarkdownDisplay()
            textField.translatesAutoresizingMaskIntoConstraints = false

            row.addArrangedSubview(bulletLabel)
            row.addArrangedSubview(textField)
            stackView.addArrangedSubview(row)

            row.leadingAnchor.constraint(equalTo: stackView.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: stackView.trailingAnchor).isActive = true
        }
    }
}
