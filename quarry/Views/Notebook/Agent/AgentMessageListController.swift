import AppKit

final class AgentMessageListController: NSViewController {

    private let chatController: AgentChatController

    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    private var streamingRow: AgentMessageRowView?
    private var errorBanner: NSView?
    private var renderedMessageIds: [UUID] = []
    private weak var lastAssistantRow: AgentMessageRowView?
    private var userScrolledAway = false
    private var suppressScrollTracking = false
    private var scrollFlushPending = false
    nonisolated(unsafe) private var scrollObserver: NSObjectProtocol?

    init(chatController: AgentChatController) {
        self.chatController = chatController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }

    override func loadView() {
        let root = NSView()
        self.view = root
        setupScrollView()
        observeMessages()
        observeStreamingParts()
        observeError()
    }

    // MARK: - Setup

    private func setupScrollView() {
        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 56, right: 0)
        stackView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedView()
        documentView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        documentView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)

        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = documentView

        scrollView = NSScrollView()
        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -56),

            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.suppressScrollTracking else { return }
                self.userScrolledAway = !self.isNearBottom()
            }
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    // MARK: - Observation

    private func observeMessages() {
        withObservationTracking {
            _ = self.chatController.messages.count
            _ = self.chatController.isStreaming
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncMessageRows()
                self.observeMessages()
            }
        }
    }

    private func observeStreamingParts() {
        withObservationTracking {
            _ = self.chatController.streamingParts
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateStreamingRow()
                self.observeStreamingParts()
            }
        }
    }

    private func observeError() {
        withObservationTracking {
            _ = self.chatController.error
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateErrorBanner()
                self.observeError()
            }
        }
    }

    // MARK: - Row Management

    private func syncMessageRows() {
        suppressScrollTracking = true
        let messages = chatController.messages
        let currentIds = messages.map(\.id)

        let needsFullRebuild = currentIds.count < renderedMessageIds.count
            || (!currentIds.isEmpty && !renderedMessageIds.isEmpty && currentIds.first != renderedMessageIds.first)

        if needsFullRebuild {
            removeStreamingRow()
            for v in stackView.arrangedSubviews {
                stackView.removeArrangedSubview(v)
                v.removeFromSuperview()
            }
            renderedMessageIds = []
            lastAssistantRow = nil

            for message in messages {
                let row = makeRow(for: message)
                if message.role == .assistant {
                    lastAssistantRow?.setActionBarAlwaysVisible(false)
                    lastAssistantRow = row
                }
                addRow(row)
                renderedMessageIds.append(message.id)
            }
            lastAssistantRow?.setActionBarAlwaysVisible(true)
        } else {
            let newMessages = messages.dropFirst(renderedMessageIds.count)
            for message in newMessages {
                if message.role == .assistant, let existingRow = streamingRow {
                    lastAssistantRow?.setActionBarAlwaysVisible(false)
                    existingRow.markFinalized(content: message.content, createdAt: message.createdAt, feedback: message.feedback)
                    wireCallbacks(on: existingRow, message: message)
                    existingRow.setActionBarAlwaysVisible(true)
                    lastAssistantRow = existingRow
                    streamingRow = nil
                } else {
                    if message.role == .assistant {
                        lastAssistantRow?.setActionBarAlwaysVisible(false)
                    }
                    let row = makeRow(for: message)
                    if message.role == .assistant {
                        row.setActionBarAlwaysVisible(true)
                        lastAssistantRow = row
                    }
                    addRow(row, animated: true)
                }
                renderedMessageIds.append(message.id)
            }
        }

        if chatController.isStreaming && streamingRow == nil {
            userScrolledAway = false
            let row = AgentMessageRowView(role: .assistant, content: "", isStreaming: true)
            addRow(row, animated: true)
            row.updateParts(chatController.streamingParts)
            streamingRow = row
        } else if !chatController.isStreaming {
            removeStreamingRow()
        }

        scrollToBottom()
    }

    private func removeStreamingRow() {
        guard let row = streamingRow else { return }
        stackView.removeArrangedSubview(row)
        row.removeFromSuperview()
        streamingRow = nil
    }

    private func updateStreamingRow() {
        streamingRow?.updateParts(chatController.streamingParts)
        scheduleScrollToBottom()
    }

    /// Coalesces per-token scroll requests into a bounded ~30Hz cadence so each
    /// streaming delta doesn't force a full layout pass. Stream end flushes
    /// immediately via syncMessageRows' direct scrollToBottom().
    private func scheduleScrollToBottom() {
        guard !scrollFlushPending else { return }
        scrollFlushPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(33))
            guard let self else { return }
            self.scrollFlushPending = false
            self.scrollToBottom()
        }
    }

    // MARK: - Row Factory

    private func makeRow(for message: AgentMessage) -> AgentMessageRowView {
        let row = AgentMessageRowView(
            role: message.role,
            content: message.content,
            createdAt: message.createdAt,
            feedback: message.feedback
        )
        wireCallbacks(on: row, message: message)
        return row
    }

    private func wireCallbacks(on row: AgentMessageRowView, message: AgentMessage) {
        row.onRetry = { [weak self] in
            self?.chatController.retry(from: message.id)
        }
        row.onFeedbackChanged = { [weak self] feedback in
            self?.chatController.setFeedback(feedback, for: message.id)
        }
    }

    // MARK: - Error Banner

    private func updateErrorBanner() {
        if let errorText = chatController.error {
            showErrorBanner(errorText, isSetupIssue: chatController.errorIsSetupIssue)
        } else {
            removeErrorBanner()
        }
    }

    private func showErrorBanner(_ text: String, isSetupIssue: Bool) {
        removeErrorBanner()

        let banner = NSView()
        banner.wantsLayer = true
        banner.layer?.cornerRadius = 14
        banner.layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 1.0, green: 0.35, blue: 0.3, alpha: 0.08)
                : NSColor(red: 0.9, green: 0.2, blue: 0.15, alpha: 0.06)
        }.cgColor
        banner.translatesAutoresizingMaskIntoConstraints = false

        let iconPill = NSView()
        iconPill.wantsLayer = true
        iconPill.layer?.cornerRadius = 8
        iconPill.layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 1.0, green: 0.35, blue: 0.3, alpha: 0.15)
                : NSColor(red: 0.9, green: 0.2, blue: 0.15, alpha: 0.1)
        }.cgColor
        iconPill.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(iconPill)

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: isSetupIssue ? "sparkles" : "exclamationmark.circle",
            accessibilityDescription: nil
        )
        icon.contentTintColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 1.0, green: 0.45, blue: 0.4, alpha: 1.0)
                : NSColor(red: 0.85, green: 0.2, blue: 0.15, alpha: 1.0)
        }
        icon.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconPill.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: isSetupIssue ? AISetup.title : "Something went wrong")
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(titleLabel)

        let detailLabel = NSTextField(wrappingLabelWithString: text)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 3
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            iconPill.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            iconPill.topAnchor.constraint(equalTo: banner.topAnchor, constant: 12),
            iconPill.widthAnchor.constraint(equalToConstant: 30),
            iconPill.heightAnchor.constraint(equalToConstant: 30),

            icon.centerXAnchor.constraint(equalTo: iconPill.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconPill.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconPill.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: iconPill.topAnchor, constant: -1),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: banner.trailingAnchor, constant: -14),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),

            banner.heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
        ])

        if isSetupIssue {
            let settingsButton = NSButton(
                title: AISetup.actionTitle,
                target: self,
                action: #selector(openAISettings)
            )
            settingsButton.bezelStyle = .rounded
            settingsButton.controlSize = .small
            settingsButton.translatesAutoresizingMaskIntoConstraints = false
            banner.addSubview(settingsButton)

            NSLayoutConstraint.activate([
                settingsButton.leadingAnchor.constraint(equalTo: detailLabel.leadingAnchor),
                settingsButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 8),
                settingsButton.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -12),
            ])
        } else {
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: banner.bottomAnchor, constant: -12).isActive = true
        }

        stackView.addArrangedSubview(banner)
        banner.leadingAnchor.constraint(equalTo: stackView.leadingAnchor).isActive = true
        banner.trailingAnchor.constraint(equalTo: stackView.trailingAnchor).isActive = true

        banner.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            banner.animator().alphaValue = 1
        }

        errorBanner = banner
        scrollToBottom()
    }

    @objc private func openAISettings() {
        AISetup.openSettings()
    }

    private func removeErrorBanner() {
        guard let banner = errorBanner else { return }
        stackView.removeArrangedSubview(banner)
        banner.removeFromSuperview()
        errorBanner = nil
    }

    // MARK: - Helpers

    private func addRow(_ row: AgentMessageRowView, animated: Bool = false) {
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.translatesAutoresizingMaskIntoConstraints = false
        // Separate each user bubble from the assistant message above it — the
        // stack's 2pt spacing reads cramped between conversation turns.
        if row.role == .user, let previous = stackView.arrangedSubviews.last {
            stackView.setCustomSpacing(6, after: previous)
        }
        stackView.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
        ])

        if animated {
            row.wantsLayer = true
            row.alphaValue = 0
            row.layer?.transform = CATransform3DMakeTranslation(0, 20, 0)

            stackView.layoutSubtreeIfNeeded()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                row.animator().alphaValue = 1
                row.layer?.transform = CATransform3DIdentity
            }
        }
    }

    private func isNearBottom(threshold: CGFloat = 60) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let contentHeight = documentView.frame.height
        let visibleHeight = scrollView.contentView.bounds.height
        let scrollY = scrollView.contentView.bounds.origin.y
        return contentHeight - scrollY - visibleHeight <= threshold
    }

    private func scrollToBottom() {
        guard !userScrolledAway else {
            suppressScrollTracking = false
            return
        }
        guard let documentView = scrollView.documentView else {
            suppressScrollTracking = false
            return
        }
        suppressScrollTracking = true
        documentView.layoutSubtreeIfNeeded()
        let contentHeight = documentView.frame.height
        let visibleHeight = scrollView.contentView.bounds.height
        if contentHeight > visibleHeight {
            let bottomPoint = NSPoint(x: 0, y: contentHeight - visibleHeight)
            scrollView.contentView.scroll(to: bottomPoint)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        Task { @MainActor [weak self] in
            self?.suppressScrollTracking = false
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
