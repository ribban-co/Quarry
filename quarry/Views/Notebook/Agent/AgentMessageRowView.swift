import AppKit

final class AgentMessageRowView: NSView {

    var onRetry: (() -> Void)?
    var onFeedbackChanged: ((AgentMessageFeedback?) -> Void)?

    let role: AgentMessageRole
    private let textView: NSTextView
    private var containerView: NSView?
    private var textViewHeightConstraint: NSLayoutConstraint?
    private var textViewWidthConstraint: NSLayoutConstraint?
    private var markdownContentView: MarkdownContentView?
    private var streamingPartsView: StreamingPartsView?

    private var userActionBar: UserMessageActionBar?
    private var assistantActionBar: AssistantMessageActionBar?
    private var containerBottomConstraint: NSLayoutConstraint?
    private var mdBottomConstraint: NSLayoutConstraint?

    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isStreamingRow = false
    private var actionBarAlwaysVisible = false

    private static let userBubbleColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0xE5 / 255.0, green: 0x7E / 255.0, blue: 0x52 / 255.0, alpha: 1.0)
        }
        return NSColor(red: 0xB9 / 255.0, green: 0x55 / 255.0, blue: 0x31 / 255.0, alpha: 1.0)
    }

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        return style
    }()

    init(
        role: AgentMessageRole,
        content: String,
        createdAt: Date = Date(),
        feedback: AgentMessageFeedback? = nil,
        isStreaming: Bool = false
    ) {
        self.role = role
        self.isStreamingRow = isStreaming
        self.textView = NSTextView()
        super.init(frame: .zero)
        wantsLayer = true
        setupLayout()

        if role == .assistant && !isStreaming, let mdView = markdownContentView {
            if !content.isEmpty {
                mdView.update(content: content)
            }
        } else if role == .user {
            applyAttributedContent(content)
        }

        if !isStreaming {
            setupActionBar(createdAt: createdAt, feedback: feedback)
        }

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

    func update(content: String) {
        if role == .assistant, let mdView = markdownContentView {
            mdView.update(content: content)
        } else {
            applyAttributedContent(content)
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func updateParts(_ parts: [StreamingPart]) {
        if parts.isEmpty {
            streamingPartsView?.showPlaceholder()
        } else {
            streamingPartsView?.updateParts(parts)
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func markFinalized(content: String, createdAt: Date, feedback: AgentMessageFeedback?) {
        isStreamingRow = false

        if let partsView = streamingPartsView {
            partsView.removeFromSuperview()
            streamingPartsView = nil
            installMarkdownContentView()
        }

        if !content.isEmpty, let mdView = markdownContentView {
            mdView.update(content: content)
        }

        setupActionBar(createdAt: createdAt, feedback: feedback)
    }

    func updateFeedback(_ feedback: AgentMessageFeedback?) {
        assistantActionBar?.setFeedback(feedback)
    }

    func setActionBarAlwaysVisible(_ visible: Bool) {
        actionBarAlwaysVisible = visible
        let bar: NSView? = role == .user ? userActionBar : assistantActionBar
        guard let bar else { return }
        if visible {
            bar.alphaValue = 1
        } else if !isHovering {
            bar.alphaValue = 0
        }
    }

    // MARK: - Action Bar

    private func setupActionBar(createdAt: Date, feedback: AgentMessageFeedback?) {
        switch role {
        case .user:
            let bar = UserMessageActionBar(timestamp: createdAt)
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.alphaValue = 0
            bar.onCopy = { [weak self] in
                guard let self else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(textView.string, forType: .string)
            }
            addSubview(bar)

            containerBottomConstraint?.constant = -28

            NSLayoutConstraint.activate([
                bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

            userActionBar = bar

        case .assistant:
            let bar = AssistantMessageActionBar()
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.alphaValue = actionBarAlwaysVisible ? 1 : 0
            bar.setFeedback(feedback)
            bar.onThumbsUp = { [weak self] in
                guard let self else { return }
                self.onFeedbackChanged?(bar.resolvedFeedback)
            }
            bar.onThumbsDown = { [weak self] in
                guard let self else { return }
                self.onFeedbackChanged?(bar.resolvedFeedback)
            }
            bar.onCopyText = { [weak self] in
                guard let self, let mdView = self.markdownContentView else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(mdView.plainText, forType: .string)
            }
            bar.onRetry = { [weak self] in self?.onRetry?() }
            addSubview(bar)

            mdBottomConstraint?.constant = -28

            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: leadingAnchor),
                bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

            assistantActionBar = bar
        }
        updateTrackingAreas()
        refreshHoverState()
    }

    // MARK: - Hover

    private var actionBar: NSView? {
        role == .user ? userActionBar : assistantActionBar
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard actionBar != nil else { return }
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
        guard !isStreamingRow, !actionBarAlwaysVisible else { return }
        isHovering = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            actionBar?.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard !actionBarAlwaysVisible else { return }
        isHovering = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            actionBar?.animator().alphaValue = 0
        }
    }

    private func refreshHoverState() {
        guard let window else {
            if !actionBarAlwaysVisible { actionBar?.alphaValue = 0 }
            return
        }
        guard !actionBarAlwaysVisible else {
            actionBar?.alphaValue = 1
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse) && !isStreamingRow
        guard should != isHovering else { return }
        isHovering = should
        actionBar?.alphaValue = isHovering ? 1 : 0
    }

    // MARK: - Content

    private func applyAttributedContent(_ text: String) {
        let color: NSColor = role == .user ? .white : .labelColor
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: color,
                .paragraphStyle: Self.paragraphStyle,
            ]
        )
        textView.textStorage?.setAttributedString(attributed)
        invalidateIntrinsicContentSize()
        recalculateTextSize()
    }

    private func recalculateTextSize() {
        guard role == .user else { return }
        guard let attributedText = textView.textStorage else { return }
        guard let textContainer = textView.textContainer else { return }

        let maxWidth = max(0, bounds.width * 0.80 - 24)
        guard maxWidth > 0 else {
            textViewWidthConstraint?.constant = 1
            textViewHeightConstraint?.constant = 1
            return
        }

        let unconstrainedRect = attributedText.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let clampedWidth = max(1, min(maxWidth, ceil(unconstrainedRect.width)))

        let constrainedRect = attributedText.boundingRect(
            with: NSSize(width: clampedWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        textContainer.containerSize = NSSize(width: clampedWidth, height: CGFloat.greatestFiniteMagnitude)
        textViewWidthConstraint?.constant = clampedWidth
        textViewHeightConstraint?.constant = max(1, ceil(constrainedRect.height))
    }

    // MARK: - Layout Setup

    private func setupLayout() {
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.translatesAutoresizingMaskIntoConstraints = false

        let heightConstraint = textView.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        textViewHeightConstraint = heightConstraint

        let widthConstraint = textView.widthAnchor.constraint(equalToConstant: 0)
        widthConstraint.priority = .defaultHigh
        widthConstraint.isActive = true
        textViewWidthConstraint = widthConstraint

        switch role {
        case .user:
            let container = NSView()
            container.wantsLayer = true
            container.layer?.cornerRadius = 14
            container.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            container.translatesAutoresizingMaskIntoConstraints = false
            addSubview(container)
            container.addSubview(textView)
            self.containerView = container
            updateUserBubbleColor()

            let bottomC = container.bottomAnchor.constraint(equalTo: bottomAnchor)
            containerBottomConstraint = bottomC

            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
                textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

                container.topAnchor.constraint(equalTo: topAnchor),
                bottomC,
                container.trailingAnchor.constraint(equalTo: trailingAnchor),
                container.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.80),
            ])

        case .assistant:
            if isStreamingRow {
                installStreamingPartsView()
            } else {
                installMarkdownContentView()
            }
        }
    }

    private func installMarkdownContentView() {
        let mdView = MarkdownContentView()
        mdView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mdView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        mdView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mdView)
        markdownContentView = mdView
        pinAssistantContentView(mdView)
    }

    private func installStreamingPartsView() {
        let partsView = StreamingPartsView()
        partsView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        partsView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        partsView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(partsView)
        streamingPartsView = partsView
        pinAssistantContentView(partsView)
    }

    private func pinAssistantContentView(_ contentView: NSView) {
        let bottomC = contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        mdBottomConstraint = bottomC
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            bottomC,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func layout() {
        super.layout()
        recalculateTextSize()
    }

    private func updateUserBubbleColor() {
        guard role == .user else { return }
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            containerView?.layer?.backgroundColor = Self.userBubbleColor.cgColor
        }
    }

    @objc private func handleAppearanceChange() {
        updateUserBubbleColor()
    }
}

// MARK: - Streaming Parts View

final class StreamingPartsView: NSView {

    private let stackView: NSStackView
    private weak var activeThinkingView: ThinkingBlockView?
    private var placeholderView: ThinkingBlockView?

    private enum DisplayEntry {
        case single(part: StreamingPart, view: NSView)
        case toolGroup(round: Int, parts: [StreamingPart], view: ThinkingBlockView)
    }
    private var entries: [DisplayEntry] = []

    override init(frame: NSRect) {
        stackView = NSStackView()
        super.init(frame: frame)
        setupStack()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showPlaceholder() {
        guard placeholderView == nil else { return }
        removeAll()
        let placeholder = ThinkingBlockView(text: "")
        addEntryView(placeholder)
        placeholderView = placeholder
    }

    private func removePlaceholder() {
        guard let placeholder = placeholderView else { return }
        stackView.removeArrangedSubview(placeholder)
        placeholder.removeFromSuperview()
        placeholderView = nil
    }

    func updateParts(_ parts: [StreamingPart]) {
        guard !parts.isEmpty else {
            removeAll()
            return
        }

        removePlaceholder()

        let sections = segmentParts(parts)
        var entryIndex = 0

        for section in sections {
            if entryIndex < entries.count && sameSection(entries[entryIndex], section) {
                updateEntry(at: entryIndex, with: section)
                entryIndex += 1
            } else {
                while entries.count > entryIndex {
                    removeLastEntry()
                }
                let view = makeEntryView(for: section)
                addEntryView(view, animated: !entries.isEmpty)
                entries.append(makeEntry(section: section, view: view))
                entryIndex += 1
            }
        }

        while entries.count > entryIndex {
            removeLastEntry()
        }

        updateThinkingStreamState(parts)
        invalidateIntrinsicContentSize()
    }

    // MARK: - Segmentation

    private struct Section {
        enum Kind: Equatable {
            case thinking
            case text
            case toolGroup(round: Int)
        }
        var kind: Kind
        var parts: [StreamingPart]
    }

    private func segmentParts(_ parts: [StreamingPart]) -> [Section] {
        var sections: [Section] = []
        for part in parts {
            switch part {
            case .thinking:
                if case .thinking = sections.last?.kind {
                    let hasToolCalls = sections[sections.count - 1].parts.contains {
                        if case .toolCall = $0 { return true }
                        return false
                    }
                    if hasToolCalls {
                        sections.append(Section(kind: .thinking, parts: [part]))
                    } else {
                        sections[sections.count - 1].parts = [part]
                    }
                } else {
                    sections.append(Section(kind: .thinking, parts: [part]))
                }
            case .text:
                if case .text = sections.last?.kind {
                    sections[sections.count - 1].parts = [part]
                } else {
                    sections.append(Section(kind: .text, parts: [part]))
                }
            case .toolCall:
                if case .thinking = sections.last?.kind {
                    sections[sections.count - 1].parts.append(part)
                } else if case .toolGroup = sections.last?.kind {
                    sections[sections.count - 1].parts.append(part)
                } else {
                    if case .toolCall(_, _, _, _, _, let round) = part {
                        sections.append(Section(kind: .toolGroup(round: round), parts: [part]))
                    }
                }
            }
        }
        return sections
    }

    // MARK: - Reconciliation

    private func sameSection(_ entry: DisplayEntry, _ section: Section) -> Bool {
        switch (entry, section.kind) {
        case (.single(let part, _), .thinking):
            if case .thinking = part { return true }
            return false
        case (.single(let part, _), .text):
            if case .text = part { return true }
            return false
        case (.toolGroup(let existingRound, _, _), .toolGroup(let newRound)):
            return existingRound == newRound
        default:
            return false
        }
    }

    private func updateEntry(at index: Int, with section: Section) {
        switch (entries[index], section.kind) {
        case (.single(_, let view), .thinking):
            guard let tbView = view as? ThinkingBlockView else { break }
            if let thinkingText = section.parts.compactMap({
                if case .thinking(let text) = $0 { return text }
                return nil
            }).first {
                tbView.update(text: thinkingText)
            }
            for part in section.parts {
                guard case .toolCall(let id, let name, let displayText, _, let isComplete, _) = part else { continue }
                if tbView.containsToolCall(id: id) {
                    if isComplete {
                        tbView.markToolCallComplete(id: id, displayText: displayText)
                    }
                } else {
                    tbView.addToolCall(id: id, name: name, displayText: displayText, isComplete: isComplete)
                }
            }
            entries[index] = .single(part: section.parts[0], view: view)
        case (.single(_, let view), .text):
            if case .text(let text) = section.parts.first {
                (view as? MarkdownContentView)?.update(content: text)
                entries[index] = .single(part: section.parts[0], view: view)
            }
        case (.toolGroup(let round, _, let tbView), .toolGroup):
            for part in section.parts {
                guard case .toolCall(let id, let name, let displayText, _, let isComplete, _) = part else { continue }
                if tbView.containsToolCall(id: id) {
                    if isComplete {
                        tbView.markToolCallComplete(id: id, displayText: displayText)
                    }
                } else {
                    tbView.addToolCall(id: id, name: name, displayText: displayText, isComplete: isComplete)
                }
            }
            entries[index] = .toolGroup(round: round, parts: section.parts, view: tbView)
        default:
            break
        }
    }

    private func makeEntry(section: Section, view: NSView) -> DisplayEntry {
        switch section.kind {
        case .thinking, .text:
            return .single(part: section.parts[0], view: view)
        case .toolGroup(let round):
            return .toolGroup(round: round, parts: section.parts, view: view as! ThinkingBlockView)
        }
    }

    private func makeEntryView(for section: Section) -> NSView {
        switch section.kind {
        case .thinking:
            let thinkingText = section.parts.compactMap {
                if case .thinking(let text) = $0 { return text }
                return nil
            }.first ?? ""
            let view = ThinkingBlockView(text: thinkingText)
            for part in section.parts {
                guard case .toolCall(let id, let name, let displayText, _, let isComplete, _) = part else { continue }
                view.addToolCall(id: id, name: name, displayText: displayText, isComplete: isComplete)
            }
            return view
        case .text:
            let mdView = MarkdownContentView()
            if case .text(let text) = section.parts.first {
                mdView.update(content: text)
            }
            return mdView
        case .toolGroup:
            let view = ThinkingBlockView(text: "")
            for part in section.parts {
                guard case .toolCall(let id, let name, let displayText, _, let isComplete, _) = part else { continue }
                view.addToolCall(id: id, name: name, displayText: displayText, isComplete: isComplete)
            }
            return view
        }
    }

    private func removeLastEntry() {
        guard let entry = entries.popLast() else { return }
        let view: NSView
        switch entry {
        case .single(_, let v): view = v
        case .toolGroup(_, _, let v): view = v
        }
        stackView.removeArrangedSubview(view)
        view.removeFromSuperview()
    }

    // MARK: - Thinking State

    private func updateThinkingStreamState(_ parts: [StreamingPart]) {
        let thinkingView: ThinkingBlockView?

        switch entries.last {
        case .single(let part, let view):
            if case .thinking = part {
                thinkingView = view as? ThinkingBlockView
            } else {
                thinkingView = nil
            }
        case .toolGroup(_, _, let view):
            thinkingView = view
        case .none:
            thinkingView = nil
        }

        guard let thinkingView else {
            activeThinkingView?.finishAll()
            activeThinkingView = nil
            return
        }

        if activeThinkingView !== thinkingView {
            activeThinkingView?.finishAll()
            activeThinkingView = thinkingView
        }

        thinkingView.setActivelyStreaming(true)
    }

    // MARK: - Stack Helpers

    private func setupStack() {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func addEntryView(_ view: NSView, animated: Bool = false) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(view)
        view.leadingAnchor.constraint(equalTo: stackView.leadingAnchor).isActive = true
        view.trailingAnchor.constraint(equalTo: stackView.trailingAnchor).isActive = true

        if animated {
            view.wantsLayer = true
            view.alphaValue = 0
            view.layer?.transform = CATransform3DMakeTranslation(0, 6, 0)

            stackView.layoutSubtreeIfNeeded()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.animator().alphaValue = 1
                view.layer?.transform = CATransform3DIdentity
            }
        }
    }

    private func removeAll() {
        removePlaceholder()
        activeThinkingView = nil
        while !entries.isEmpty {
            removeLastEntry()
        }
    }
}

// MARK: - Streaming Tool Call Row View

final class StreamingToolCallRowView: NSView {

    private let iconView: NSImageView
    private let label: NSTextField
    private let shimmer = ShimmerLayer()
    private var isComplete = false
    private var needsShimmerStart = false

    init(displayText: String, iconName: String? = nil, initiallyComplete: Bool = false) {
        isComplete = initiallyComplete

        iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: iconName ?? "gearshape", accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label = NSTextField(labelWithString: displayText)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.wantsLayer = true

        super.init(frame: .zero)

        let row = NSStackView(views: [iconView, label])
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if !initiallyComplete {
            needsShimmerStart = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if needsShimmerStart && window != nil {
            needsShimmerStart = false
            startShimmer()
        }
    }

    override func layout() {
        super.layout()
        if needsShimmerStart && label.bounds.width > 0 {
            needsShimmerStart = false
            startShimmer()
        }
        shimmer.updateFrame(for: label)
    }

    func markComplete(newDisplayText: String? = nil) {
        guard !isComplete else { return }
        isComplete = true
        needsShimmerStart = false
        stopShimmer()
        if let text = newDisplayText {
            label.stringValue = text
        }
    }

    private func startShimmer() {
        shimmer.start(on: label)
    }

    private func stopShimmer() {
        shimmer.stop(from: label)
    }
}
