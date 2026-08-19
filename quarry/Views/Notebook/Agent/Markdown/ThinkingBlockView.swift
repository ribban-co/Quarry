import AppKit

final class ThinkingBlockView: NSView, @unchecked Sendable {

    private let titleLabel: NSTextField
    private let chevronIcon: NSImageView
    private let headerArea: NSView
    private let bulletDot: NSView
    private let markdownView: MarkdownContentView
    private let contentContainer: NSView
    private var containerHeightConstraint: NSLayoutConstraint!
    private var contentTopConstraint: NSLayoutConstraint!
    private var isExpanded = false
    private var autoExpanded = false
    private var isHovering = false
    private var headerTrackingArea: NSTrackingArea?
    private var streamingStartTime: Date?
    private var isFinished = false
    private var extractedTitle: String?
    private let shimmer = ShimmerLayer()
    private var hasReasoning = false
    private var markdownLeadingToBullet: NSLayoutConstraint!
    private var markdownLeadingToContainer: NSLayoutConstraint!
    private var reasoningHeightConstraint: NSLayoutConstraint!

    // Tool calls
    private var toolCallContainer: NSView?
    private let timelineLine = NSView()
    private var timelineBottomConstraint: NSLayoutConstraint?
    private var toolGroupStack: NSStackView?
    private var toolCallGroups: [ToolCallGroup] = []
    private static let pillHeight: CGFloat = 24
    private static let pillSpacing: CGFloat = 5
    private static let groupSpacing: CGFloat = 12
    private static let maxScrollHeight: CGFloat = 178

    private var toolScrollAnchor: ScrollAnchor?
    private var reasoningScrollView: NSScrollView!
    private var reasoningScrollAnchor: ScrollAnchor!

    private struct ToolCallRow {
        let id: String
        let pill: NSView
        let spinner: NSProgressIndicator
        let checkmark: NSImageView
        let label: NSTextField
    }

    private struct ToolCallGroup {
        let toolName: String
        let container: NSView
        let pillStack: NSStackView
        var rows: [ToolCallRow]
    }

    init(text: String, finishedDuration: Int? = nil) {
        titleLabel = NSTextField(labelWithString: "Thinking...")
        chevronIcon = NSImageView()
        headerArea = NSView()
        bulletDot = NSView()
        markdownView = MarkdownContentView()
        contentContainer = NSView()
        super.init(frame: .zero)
        setupViews()
        extractedTitle = Self.extractTitle(text)
        let stripped = Self.stripTitle(text)
        markdownView.update(content: stripped)
        hasReasoning = !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        updateReasoningLayout()

        chevronIcon.isHidden = true

        if let duration = finishedDuration {
            isFinished = true
            chevronIcon.isHidden = false
            showFinishedHeader(duration: duration)
        } else {
            startHeaderAnimations()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(text: String) {
        extractedTitle = Self.extractTitle(text)
        let stripped = Self.stripTitle(text)
        markdownView.update(content: stripped)
        let newHasReasoning = !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if newHasReasoning != hasReasoning {
            hasReasoning = newHasReasoning
            updateReasoningLayout()
        }
        if isExpanded {
            updateExpandedHeight(animated: false)
        }
        invalidateIntrinsicContentSize()
        reasoningScrollAnchor.scrollToBottom(layout: layoutAncestorTree)
    }

    func setActivelyStreaming(_ streaming: Bool) {
        if streaming && !isFinished {
            toolScrollAnchor?.resetUserScroll()
            reasoningScrollAnchor.resetUserScroll()
            startHeaderAnimations()
            chevronIcon.isHidden = false
            if streamingStartTime == nil {
                streamingStartTime = Date()
            }
            if !isExpanded {
                autoExpanded = true
                setExpanded(true, animated: false)
            }
        } else if !streaming && !isFinished {
            finishAll()
        }
    }

    func finishAll() {
        guard !isFinished else { return }
        isFinished = true
        autoExpanded = false
        updateHeaderToFinished()
        collapseQuietly()
    }

    // MARK: - Tool Calls

    func addToolCall(id: String, name: String, displayText: String, isComplete: Bool) {
        if toolCallContainer == nil {
            setupToolCallSection()
        }

        let key = ToolMetadata.groupKey(for: name)
        let groupIndex: Int
        if let existing = toolCallGroups.firstIndex(where: { $0.toolName == key }) {
            groupIndex = existing
        } else {
            addToolGroup(for: key)
            groupIndex = toolCallGroups.count - 1
        }

        let pillStack = toolCallGroups[groupIndex].pillStack

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 12
        pill.layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.04)
                : NSColor.black.withAlphaComponent(0.03)
        }.cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let checkmark = NSImageView()
        checkmark.image = NSImage(systemSymbolName: ToolMetadata.pillIcon(for: name), accessibilityDescription: nil)
        checkmark.contentTintColor = .tertiaryLabelColor
        checkmark.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        checkmark.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: displayText)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        pill.addSubview(spinner)
        pill.addSubview(checkmark)
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 13),
            spinner.heightAnchor.constraint(equalToConstant: 13),
            spinner.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            spinner.centerYAnchor.constraint(equalTo: pill.centerYAnchor),

            checkmark.widthAnchor.constraint(equalToConstant: 13),
            checkmark.heightAnchor.constraint(equalToConstant: 13),
            checkmark.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            checkmark.centerYAnchor.constraint(equalTo: pill.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),

            pill.heightAnchor.constraint(equalToConstant: Self.pillHeight),
        ])

        if isComplete {
            spinner.isHidden = true
            checkmark.isHidden = false
        } else {
            spinner.startAnimation(nil)
            spinner.isHidden = false
            checkmark.isHidden = true
        }

        pill.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        pillStack.addArrangedSubview(pill)
        pill.widthAnchor.constraint(lessThanOrEqualTo: pillStack.widthAnchor, multiplier: 0.85).isActive = true
        toolCallGroups[groupIndex].rows.append(ToolCallRow(id: id, pill: pill, spinner: spinner, checkmark: checkmark, label: label))

        if isExpanded {
            updateExpandedHeight(animated: false)
        }
        invalidateIntrinsicContentSize()
        toolScrollAnchor?.scrollToBottom(layout: layoutAncestorTree)
    }

    func containsToolCall(id: String) -> Bool {
        toolCallGroups.contains { group in group.rows.contains { $0.id == id } }
    }

    func markToolCallComplete(id: String, displayText: String) {
        for group in toolCallGroups {
            guard let entry = group.rows.first(where: { $0.id == id }) else { continue }
            entry.spinner.stopAnimation(nil)
            entry.spinner.isHidden = true
            entry.checkmark.isHidden = false
            entry.label.stringValue = displayText
            return
        }
    }

    private func setupToolCallSection() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(container)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = Self.makeOverlayScrollView(documentView: documentView)
        container.addSubview(scrollView)

        let groupStack = NSStackView()
        groupStack.orientation = .vertical
        groupStack.alignment = .leading
        groupStack.spacing = Self.groupSpacing
        groupStack.translatesAutoresizingMaskIntoConstraints = false
        toolGroupStack = groupStack
        documentView.addSubview(groupStack)

        if hasReasoning {
            timelineBottomConstraint?.isActive = false
            timelineBottomConstraint = timelineLine.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            timelineBottomConstraint?.isActive = true
        }

        NSLayoutConstraint.activate([
            groupStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            groupStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            groupStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            groupStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            container.topAnchor.constraint(
                equalTo: hasReasoning ? reasoningScrollView.bottomAnchor : contentContainer.topAnchor,
                constant: hasReasoning ? 8 : 0
            ),
            container.leadingAnchor.constraint(equalTo: reasoningScrollView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        toolScrollAnchor = ScrollAnchor(scrollView: scrollView)
        toolCallContainer = container
    }

    private func addToolGroup(for toolName: String) {
        guard let groupStack = toolGroupStack else { return }

        let groupContainer = NSView()
        groupContainer.translatesAutoresizingMaskIntoConstraints = false

        let hIcon = NSImageView()
        hIcon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        hIcon.image = NSImage(systemSymbolName: ToolMetadata.icon(for: toolName), accessibilityDescription: nil)
        hIcon.imageScaling = .scaleNone
        hIcon.contentTintColor = .secondaryLabelColor
        hIcon.translatesAutoresizingMaskIntoConstraints = false
        groupContainer.addSubview(hIcon)

        let hLabel = NSTextField(labelWithString: ToolMetadata.groupHeader(for: toolName))
        hLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        hLabel.textColor = .secondaryLabelColor
        hLabel.lineBreakMode = .byTruncatingTail
        hLabel.translatesAutoresizingMaskIntoConstraints = false
        groupContainer.addSubview(hLabel)

        let pillStack = NSStackView()
        pillStack.orientation = .vertical
        pillStack.alignment = .leading
        pillStack.spacing = Self.pillSpacing
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        groupContainer.addSubview(pillStack)

        NSLayoutConstraint.activate([
            hIcon.leadingAnchor.constraint(equalTo: groupContainer.leadingAnchor),
            hIcon.centerYAnchor.constraint(equalTo: hLabel.centerYAnchor),

            hLabel.leadingAnchor.constraint(equalTo: hIcon.trailingAnchor, constant: 5),
            hLabel.topAnchor.constraint(equalTo: groupContainer.topAnchor),
            hLabel.trailingAnchor.constraint(lessThanOrEqualTo: groupContainer.trailingAnchor),

            pillStack.leadingAnchor.constraint(equalTo: groupContainer.leadingAnchor, constant: 2),
            pillStack.topAnchor.constraint(equalTo: hLabel.bottomAnchor, constant: 10),
            pillStack.trailingAnchor.constraint(equalTo: groupContainer.trailingAnchor),
            pillStack.bottomAnchor.constraint(equalTo: groupContainer.bottomAnchor),
        ])

        groupStack.addArrangedSubview(groupContainer)
        groupContainer.widthAnchor.constraint(equalTo: groupStack.widthAnchor).isActive = true

        toolCallGroups.append(ToolCallGroup(toolName: toolName, container: groupContainer, pillStack: pillStack, rows: []))
    }

    // MARK: - Header

    private func updateHeaderToFinished() {
        let duration = streamingStartTime.map { max(1, Int(Date().timeIntervalSince($0))) } ?? 0
        showFinishedHeader(duration: duration)
    }

    private func showFinishedHeader(duration: Int) {
        stopHeaderAnimations()

        if let title = extractedTitle, !title.isEmpty {
            titleLabel.stringValue = title
        } else if duration > 0 {
            titleLabel.stringValue = "Thought for \(duration) second\(duration == 1 ? "" : "s")"
        } else {
            titleLabel.stringValue = "Thought"
        }
    }

    // MARK: - Expand / Collapse

    private static let chevronConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)

    private func updateChevronImage() {
        let name = isExpanded ? "chevron.down" : "chevron.right"
        chevronIcon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(Self.chevronConfig)
    }

    private func collapseQuietly() {
        guard isExpanded else { return }
        isExpanded = false
        updateChevronImage()
        containerHeightConstraint.constant = 0
        reasoningHeightConstraint.constant = 0
        contentTopConstraint.constant = 0
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if expanded {
            toolScrollAnchor?.resetUserScroll()
            reasoningScrollAnchor.resetUserScroll()
        }
        updateChevronImage()

        let targetHeight: CGFloat = isExpanded ? targetContentHeight() : 0
        let targetGap: CGFloat = isExpanded ? 4 : 0

        if !animated {
            containerHeightConstraint.constant = targetHeight
            contentTopConstraint.constant = targetGap
            layoutAncestorTree()
            return
        }

        let timingName: CAMediaTimingFunctionName = isExpanded ? .easeOut : .easeIn
        let duration: CGFloat = isExpanded ? 0.25 : 0.2

        NSAnimationContext.runAnimationGroup { [self] ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: timingName)
            ctx.allowsImplicitAnimation = true
            containerHeightConstraint.constant = targetHeight
            contentTopConstraint.constant = targetGap
            layoutAncestorTree()
        }
    }

    private func updateExpandedHeight(animated: Bool) {
        guard isExpanded else { return }
        let target = targetContentHeight()
        guard abs(containerHeightConstraint.constant - target) > 1 else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { [self] ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                containerHeightConstraint.constant = target
                layoutAncestorTree()
            }
        } else {
            containerHeightConstraint.constant = target
        }
    }

    private func layoutAncestorTree() {
        if let contentView = window?.contentView {
            contentView.layoutSubtreeIfNeeded()
        } else {
            superview?.layoutSubtreeIfNeeded()
        }
    }

    private func targetContentHeight() -> CGFloat {
        var height: CGFloat = 0

        if hasReasoning {
            let fitting = markdownView.fittingSize
            var reasonHeight: CGFloat
            if fitting.height > 0 {
                reasonHeight = ceil(fitting.height)
            } else {
                let size = markdownView.intrinsicContentSize
                reasonHeight = size.height > 0 ? ceil(size.height) : 20
            }
            let capped = min(reasonHeight, Self.maxScrollHeight)
            reasoningHeightConstraint.constant = capped
            height = capped
        } else {
            reasoningHeightConstraint.constant = 0
        }

        if let groupStack = toolGroupStack {
            let toolHeight = min(ceil(max(groupStack.fittingSize.height, 0)), Self.maxScrollHeight)
            if toolHeight > 0 {
                height += (hasReasoning ? 16 : 0) + toolHeight
            }
        }

        return height
    }

    override func layout() {
        super.layout()
        if isExpanded {
            let target = targetContentHeight()
            if abs(containerHeightConstraint.constant - target) > 1 {
                containerHeightConstraint.constant = target
            }
        }
        shimmer.updateFrame(for: titleLabel)
        updateBulletDotAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBulletDotAppearance()
    }

    private func updateBulletDotAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        bulletDot.layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.35)
            : NSColor.black.withAlphaComponent(0.25)
        ).cgColor
    }

    // MARK: - Setup

    private static func makeOverlayScrollView(documentView: NSView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }

    private func setupViews() {
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        chevronIcon.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(chevronConfig)
        chevronIcon.contentTintColor = .tertiaryLabelColor
        chevronIcon.translatesAutoresizingMaskIntoConstraints = false

        headerArea.wantsLayer = true
        headerArea.layer?.cornerRadius = 6
        headerArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerArea)
        headerArea.addSubview(titleLabel)
        headerArea.addSubview(chevronIcon)

        let click = NSClickGestureRecognizer(target: self, action: #selector(toggleExpanded))
        headerArea.addGestureRecognizer(click)

        contentContainer.wantsLayer = true
        contentContainer.layer?.masksToBounds = true
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        bulletDot.wantsLayer = true
        bulletDot.layer?.cornerRadius = 3.5
        bulletDot.layer?.backgroundColor = .clear
        bulletDot.layer?.borderWidth = 1.5
        bulletDot.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
        bulletDot.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(bulletDot)

        timelineLine.wantsLayer = true
        timelineLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        timelineLine.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(timelineLine)

        let reasoningDocView = FlippedView()
        reasoningDocView.translatesAutoresizingMaskIntoConstraints = false

        let reasoningSV = Self.makeOverlayScrollView(documentView: reasoningDocView)
        contentContainer.addSubview(reasoningSV)
        reasoningScrollView = reasoningSV
        reasoningScrollAnchor = ScrollAnchor(scrollView: reasoningSV)

        markdownView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        markdownView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        reasoningDocView.addSubview(markdownView)

        let tlBottom = timelineLine.bottomAnchor.constraint(equalTo: reasoningSV.bottomAnchor)
        timelineBottomConstraint = tlBottom

        let reasoningHC = reasoningSV.heightAnchor.constraint(equalToConstant: 0)
        reasoningHeightConstraint = reasoningHC

        let heightC = contentContainer.heightAnchor.constraint(equalToConstant: 0)
        containerHeightConstraint = heightC

        let topC = contentContainer.topAnchor.constraint(equalTo: headerArea.bottomAnchor, constant: 0)
        contentTopConstraint = topC

        let mdLeadingBullet = reasoningSV.leadingAnchor.constraint(equalTo: bulletDot.trailingAnchor, constant: 6)
        markdownLeadingToBullet = mdLeadingBullet

        let mdLeadingContainer = reasoningSV.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor)
        markdownLeadingToContainer = mdLeadingContainer

        NSLayoutConstraint.activate([
            markdownView.topAnchor.constraint(equalTo: reasoningDocView.topAnchor),
            markdownView.leadingAnchor.constraint(equalTo: reasoningDocView.leadingAnchor),
            markdownView.trailingAnchor.constraint(equalTo: reasoningDocView.trailingAnchor),
            markdownView.bottomAnchor.constraint(equalTo: reasoningDocView.bottomAnchor),

            reasoningDocView.widthAnchor.constraint(equalTo: reasoningSV.widthAnchor),

            headerArea.topAnchor.constraint(equalTo: topAnchor),
            headerArea.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -6),
            headerArea.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            headerArea.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: headerArea.leadingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: headerArea.centerYAnchor),

            chevronIcon.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            chevronIcon.centerYAnchor.constraint(equalTo: headerArea.centerYAnchor),
            chevronIcon.trailingAnchor.constraint(equalTo: headerArea.trailingAnchor, constant: -6),
            chevronIcon.widthAnchor.constraint(equalToConstant: 12),

            topC,
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightC,

            bulletDot.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            bulletDot.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 5),
            bulletDot.widthAnchor.constraint(equalToConstant: 7),
            bulletDot.heightAnchor.constraint(equalToConstant: 7),

            timelineLine.widthAnchor.constraint(equalToConstant: 1.5),
            timelineLine.centerXAnchor.constraint(equalTo: bulletDot.centerXAnchor),
            timelineLine.topAnchor.constraint(equalTo: bulletDot.bottomAnchor, constant: 4),
            tlBottom,

            reasoningSV.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            reasoningSV.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            reasoningHC,
        ])
    }

    @objc private func toggleExpanded() {
        autoExpanded = false
        setExpanded(!isExpanded, animated: true)
    }

    private func updateReasoningLayout() {
        bulletDot.isHidden = !hasReasoning
        timelineLine.isHidden = !hasReasoning
        if hasReasoning {
            markdownLeadingToContainer.isActive = false
            markdownLeadingToBullet.isActive = true
        } else {
            markdownLeadingToBullet.isActive = false
            markdownLeadingToContainer.isActive = true
        }
    }

    // MARK: - Header Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = headerTrackingArea { headerArea.removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        headerArea.addTrackingArea(area)
        headerTrackingArea = area
        refreshHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyHeaderHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHeaderHover(false)
    }

    private func refreshHoverState() {
        guard let window else {
            isHovering = false
            applyHeaderHover(false)
            return
        }
        let mouse = headerArea.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = headerArea.bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        applyHeaderHover(isHovering)
    }

    private func applyHeaderHover(_ on: Bool) {
        guard let layer = headerArea.layer else { return }
        if on {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.06).cgColor
                : NSColor.black.withAlphaComponent(0.04).cgColor
        } else {
            layer.backgroundColor = nil
        }
    }

    // MARK: - Header Animations

    private func startHeaderAnimations() {
        shimmer.start(on: titleLabel)
    }

    private func stopHeaderAnimations() {
        shimmer.stop(from: titleLabel)
    }

    private static func extractTitle(_ text: String) -> String? {
        guard text.hasPrefix("**"), text.count > 4 else { return nil }
        guard let closeRange = text.range(of: "**", range: text.index(text.startIndex, offsetBy: 2)..<text.endIndex) else {
            return nil
        }
        let title = text[text.index(text.startIndex, offsetBy: 2)..<closeRange.lowerBound]
        return title.isEmpty ? nil : String(title)
    }

    private static func stripTitle(_ text: String) -> String {
        guard text.hasPrefix("**") else { return text }
        guard text.count > 4 else { return "" }
        guard let closeRange = text.range(of: "**", range: text.index(text.startIndex, offsetBy: 2)..<text.endIndex) else {
            return ""
        }
        let afterTitle = text[closeRange.upperBound...]
        let trimmed = afterTitle.drop(while: { $0 == "\n" || $0 == "\r" })
        return String(trimmed)
    }
}

// MARK: - Scroll Tracking

/// Tracks user scroll position for an NSScrollView, supporting auto-scroll-to-bottom
/// with suppression during programmatic scrolls.
@MainActor
private final class ScrollAnchor {

    private let scrollView: NSScrollView
    private var userScrolled = false
    private var suppressTracking = false
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init(scrollView: NSScrollView) {
        self.scrollView = scrollView

        scrollView.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.suppressTracking else { return }
                self.userScrolled = !self.isNearBottom()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func resetUserScroll() {
        userScrolled = false
    }

    func scrollToBottom(layout: () -> Void) {
        guard let documentView = scrollView.documentView,
              !userScrolled else { return }

        suppressTracking = true
        layout()

        let contentHeight = documentView.frame.height
        let visibleHeight = scrollView.contentView.bounds.height
        guard contentHeight > visibleHeight else {
            suppressTracking = false
            return
        }

        let bottomPoint = NSPoint(x: 0, y: contentHeight - visibleHeight)
        scrollView.contentView.scroll(to: bottomPoint)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                self?.suppressTracking = false
            }
        }
    }

    private func isNearBottom(threshold: CGFloat = 30) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let contentHeight = documentView.frame.height
        let visibleHeight = scrollView.contentView.bounds.height
        let scrollY = scrollView.contentView.bounds.origin.y
        return contentHeight - scrollY - visibleHeight <= threshold
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
