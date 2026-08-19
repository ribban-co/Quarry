import AppKit

final class AgentChatHistoryPopoverController: NSViewController {

    var onSelectChat: (AgentChat) -> Void = { _ in }
    var onDeleteChat: (AgentChat) -> Void = { _ in }

    private let chats: [AgentChat]
    private let currentChatId: UUID?
    private let popoverWidth: CGFloat = 260

    init(chats: [AgentChat], currentChatId: UUID?) {
        self.chats = chats
        self.currentChatId = currentChatId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: popoverWidth, height: 100))
        self.view = root

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

        buildList(into: stackView)

        let scrollView = NSScrollView()
        scrollView.documentView = stackView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        ])

        let intrinsicHeight = stackView.fittingSize.height
        let height = min(max(intrinsicHeight, 60), 380)
        preferredContentSize = NSSize(width: popoverWidth, height: height)
    }

    // MARK: - Build

    private func buildList(into stackView: NSStackView) {
        let grouped = groupChatsByDate()

        if grouped.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No chats yet")
            emptyLabel.font = .systemFont(ofSize: 13)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(emptyLabel)
            NSLayoutConstraint.activate([
                emptyLabel.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                emptyLabel.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 20),
                emptyLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -20),
                wrapper.widthAnchor.constraint(equalToConstant: popoverWidth - 12),
            ])
            stackView.addArrangedSubview(wrapper)
            return
        }

        for group in grouped {
            let header = createSectionHeader(group.title)
            stackView.addArrangedSubview(header)

            for chat in group.chats {
                let row = ChatHistoryRowView(
                    chat: chat,
                    isSelected: chat.id == currentChatId,
                    width: popoverWidth - 12
                )
                row.onSelect = { [weak self] in
                    self?.onSelectChat(chat)
                }
                row.onDelete = { [weak self] in
                    self?.onDeleteChat(chat)
                }
                stackView.addArrangedSubview(row)
            }
        }
    }

    private func createSectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            container.widthAnchor.constraint(equalToConstant: popoverWidth - 12),
        ])
        return container
    }

    // MARK: - Grouping

    private struct DateGroup {
        let title: String
        let chats: [AgentChat]
    }

    private func groupChatsByDate() -> [DateGroup] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOf7DaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let startOf30DaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday)!

        var today: [AgentChat] = []
        var yesterday: [AgentChat] = []
        var previous7: [AgentChat] = []
        var previous30: [AgentChat] = []
        var older: [AgentChat] = []

        for chat in chats {
            let date = chat.updatedAt
            if date >= startOfToday {
                today.append(chat)
            } else if date >= startOfYesterday {
                yesterday.append(chat)
            } else if date >= startOf7DaysAgo {
                previous7.append(chat)
            } else if date >= startOf30DaysAgo {
                previous30.append(chat)
            } else {
                older.append(chat)
            }
        }

        var groups: [DateGroup] = []
        if !today.isEmpty { groups.append(DateGroup(title: "Today", chats: today)) }
        if !yesterday.isEmpty { groups.append(DateGroup(title: "Yesterday", chats: yesterday)) }
        if !previous7.isEmpty { groups.append(DateGroup(title: "Previous 7 Days", chats: previous7)) }
        if !previous30.isEmpty { groups.append(DateGroup(title: "Previous 30 Days", chats: previous30)) }
        if !older.isEmpty { groups.append(DateGroup(title: "Older", chats: older)) }
        return groups
    }
}

private final class ChatHistoryRowView: NSView {

    var onSelect: () -> Void = {}
    var onDelete: () -> Void = {}

    private let titleLabel: NSTextField
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(chat: AgentChat, isSelected: Bool, width: CGFloat) {
        titleLabel = NSTextField(labelWithString: Self.singleLineTitle(from: chat.title))
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.wraps = false
        titleLabel.cell?.usesSingleLineMode = true

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        var constraints = [
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]

        if isSelected {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(config)
            let checkmark = NSImageView(image: image ?? NSImage())
            checkmark.contentTintColor = .secondaryLabelColor
            checkmark.translatesAutoresizingMaskIntoConstraints = false
            checkmark.setContentHuggingPriority(.required, for: .horizontal)
            addSubview(checkmark)
            constraints.append(contentsOf: [
                checkmark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                checkmark.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmark.leadingAnchor, constant: -6),
            ])
        } else {
            constraints.append(
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
            )
        }

        NSLayoutConstraint.activate(constraints)
        menu = buildContextMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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
        applyHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHover(false)
    }

    override func mouseDown(with event: NSEvent) {
        applyHover(false)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onSelect()
        }
    }

    private func refreshHoverState() {
        guard let window else {
            isHovering = false
            applyHover(false)
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        applyHover(isHovering)
    }

    private func applyHover(_ on: Bool) {
        guard let layer else { return }
        if on {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.06).cgColor
                : NSColor.black.withAlphaComponent(0.04).cgColor
        } else {
            layer.backgroundColor = nil
        }
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(handleDelete), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(deleteItem)
        return menu
    }

    @objc private func handleDelete() {
        onDelete()
    }

    private static func singleLineTitle(from title: String) -> String {
        let flattened = title.split(whereSeparator: \.isNewline).joined(separator: " ")
        let normalized = flattened.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized.isEmpty ? "New Chat" : normalized
    }
}
