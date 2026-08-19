import AppKit

final class MarkdownTableView: NSView {

    private let containerView: NSView

    init(headers: [String], rows: [[String]]) {
        containerView = NSView()
        super.init(frame: .zero)
        setupContainer()
        buildTable(headers: headers, rows: rows)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(headers: [String], rows: [[String]]) {
        for sub in containerView.subviews {
            sub.removeFromSuperview()
        }
        buildTable(headers: headers, rows: rows)
        invalidateIntrinsicContentSize()
    }

    private func setupContainer() {
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 6
        containerView.layer?.borderWidth = 1
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        updateColors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildTable(headers: [String], rows: [[String]]) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: containerView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        let columnCount = headers.count

        let headerRow = makeRow(cells: headers, bold: true)
        stack.addArrangedSubview(headerRow)
        headerRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        headerRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let separator = NSView()
        separator.wantsLayer = true
        separator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(separator)
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        separator.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        separator.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }

        for row in rows {
            let paddedRow = row + Array(repeating: "", count: max(0, columnCount - row.count))
            let rowView = makeRow(cells: Array(paddedRow.prefix(columnCount)), bold: false)
            stack.addArrangedSubview(rowView)
            rowView.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            rowView.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
    }

    private func makeRow(cells: [String], bold: Bool) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false

        for cell in cells {
            let field = NSTextField(labelWithString: cell)
            field.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: bold ? .semibold : .regular)
            field.textColor = .labelColor
            field.isEditable = false
            field.isSelectable = true
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false

            let cellContainer = NSView()
            cellContainer.translatesAutoresizingMaskIntoConstraints = false
            cellContainer.addSubview(field)

            NSLayoutConstraint.activate([
                field.topAnchor.constraint(equalTo: cellContainer.topAnchor, constant: 4),
                field.bottomAnchor.constraint(equalTo: cellContainer.bottomAnchor, constant: -4),
                field.leadingAnchor.constraint(equalTo: cellContainer.leadingAnchor, constant: 8),
                field.trailingAnchor.constraint(equalTo: cellContainer.trailingAnchor, constant: -8),
            ])

            row.addArrangedSubview(cellContainer)
        }

        return row
    }

    private func updateColors() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.containerView.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    @objc private func handleAppearanceChange() {
        updateColors()
    }
}
