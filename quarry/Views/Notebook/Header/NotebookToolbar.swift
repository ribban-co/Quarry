import AppKit

private enum NotebookToolbarMetrics {
    static let legacySegmentCornerRadius: CGFloat = 10
    static let legacySegmentHighlightCornerRadius: CGFloat = 7
    static let legacySegmentButtonMinHeight: CGFloat = 28
}

final class NotebookToolbarController: NSViewController {

    private let dataController: NotebookDataController

    private var containerView: NSView!

    // Normal toolbar
    private var normalToolbar: NSView!
    private var segmentView: NSView?
    // Pre-macOS 26 custom segment
    private var segmentContainer: NSView?
    private var segmentHighlight: NSView?
    private var notebookSegmentButton: NSButton?
    private var dashboardSegmentButton: NSButton?
    private var segmentHighlightLeading: NSLayoutConstraint?
    private var runAllButton: NSView!
    private var runAllSpinner: NSProgressIndicator?
    private var runAllIcon: NSImageView?
    private var runAllPublishGroup: NSView!
    private var publishButton: NSView!
    private var chatButton: NSView!
    private var scrolledTitleLabel: NSTextField!
    private var scrolledStatusLabel: NSTextField!
    private var scrolledTitleContainer: NSView!
    private var scrolledBackground: ToolbarBlurView!

    // Publish preview toolbar (shown when previewing before publish)
    private var previewToolbar: NSView!
    private var previewRunAllButton: NSView!
    private var previewRunAllSpinner: NSProgressIndicator?
    private var previewRunAllIcon: NSImageView?
    private var previewTrailingGroup: NSView!
    private var publishConfirmButton: NSView!
    private var cancelButton: NSView!
    private var previewScrolledBackground: ToolbarBlurView!
    private var shownToolbar: NSView?
    private var publishPopover: NSPopover?

    // Published toolbar (shown after confirmed publish)
    private var publishedToolbar: NSView!
    private var editButton: NSView!
    private var refreshStatusButton: RefreshStatusButton!
    private var publishedScrolledTitleContainer: NSView!
    private var publishedScrolledTitleLabel: NSTextField!
    private var publishedScrolledStatusLabel: NSTextField!
    private var publishedScrolledBackground: ToolbarBlurView!

    init(dataController: NotebookDataController) {
        self.dataController = dataController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        containerView = NSView()
        containerView.wantsLayer = true
        self.view = containerView

        setupNormalToolbar()
        setupPreviewToolbar()
        setupPublishedToolbar()
        setupContainerConstraints()
        applyState()
        observeViewMode()
        observeScrollState()
        observeTitle()
        observeStatus()
        observeRefreshingState()
    }

    // MARK: - Normal Toolbar

    private func setupNormalToolbar() {
        normalToolbar = NSView()
        normalToolbar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(normalToolbar)

        setupScrolledBackground()
        setupSegmentedControl()
        setupTrailingButtons()
        setupScrolledTitle()
        setupNormalConstraints()
    }

    private func setupScrolledBackground() {
        scrolledBackground = ToolbarBlurView()
        scrolledBackground.translatesAutoresizingMaskIntoConstraints = false
        scrolledBackground.isHidden = true
        normalToolbar.addSubview(scrolledBackground, positioned: .below, relativeTo: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    private func setupSegmentedControl() {
        if #available(macOS 26, *) {
            setupGlassSegment()
        } else {
            setupCustomSegment()
        }
        updateSegmentSelection(animated: false)
    }

    @available(macOS 26, *)
    private func setupGlassSegment() {
        let glass = CapsuleGlassView()
        glass.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: glass.topAnchor),
            stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])

        let nbButton = GlassSegmentButton(title: "Notebook", target: self, action: #selector(selectNotebook))
        let dbButton = GlassSegmentButton(title: "Dashboard", target: self, action: #selector(selectDashboard))
        stack.addArrangedSubview(nbButton)
        stack.addArrangedSubview(dbButton)

        normalToolbar.addSubview(glass)
        notebookSegmentButton = nbButton
        dashboardSegmentButton = dbButton
        segmentView = glass
    }

    private func setupCustomSegment() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = NotebookToolbarMetrics.legacySegmentCornerRadius
        container.translatesAutoresizingMaskIntoConstraints = false
        normalToolbar.addSubview(container)
        segmentContainer = container

        updateSegmentContainerColor()

        let highlight = NSView()
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = NotebookToolbarMetrics.legacySegmentHighlightCornerRadius
        highlight.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(highlight)
        segmentHighlight = highlight

        updateSegmentHighlightColor()
        updateSegmentHighlightShadow()

        let nbButton = makeSegmentButton(title: "Notebook", action: #selector(selectNotebook))
        let dbButton = makeSegmentButton(title: "Dashboard", action: #selector(selectDashboard))
        container.addSubview(nbButton)
        container.addSubview(dbButton)
        notebookSegmentButton = nbButton
        dashboardSegmentButton = dbButton

        let highlightLeading = highlight.leadingAnchor.constraint(equalTo: nbButton.leadingAnchor)
        segmentHighlightLeading = highlightLeading

        NSLayoutConstraint.activate([
            nbButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            nbButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            nbButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),

            dbButton.leadingAnchor.constraint(equalTo: nbButton.trailingAnchor),
            dbButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            dbButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            dbButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),

            highlightLeading,
            highlight.topAnchor.constraint(equalTo: nbButton.topAnchor),
            highlight.bottomAnchor.constraint(equalTo: nbButton.bottomAnchor),
            highlight.widthAnchor.constraint(equalTo: nbButton.widthAnchor),
        ])

        segmentView = container
    }

    private func makeSegmentButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        (button.cell as? NSButtonCell)?.highlightsBy = []
        button.contentTintColor = .secondaryLabelColor
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: NotebookToolbarMetrics.legacySegmentButtonMinHeight).isActive = true
        return button
    }

    private func setupTrailingButtons() {
        if #available(macOS 26, *) {
            let runAllGlass = makeGlassCapsule()
            let runAll = makeGlassRunAllIcon(action: #selector(runAllTapped))
            runAllGlass.contentView = runAll.click
            runAllButton = runAll.click
            runAllIcon = runAll.icon
            runAllSpinner = runAll.spinner

            NSLayoutConstraint.activate([
                runAll.click.widthAnchor.constraint(equalToConstant: 36),
                runAll.click.heightAnchor.constraint(equalToConstant: 36),
            ])

            publishButton = makeGlassIconLabelButton(icon: "paperplane.fill", label: "Publish", action: #selector(publishTapped))

            let stack = NSStackView(views: [runAllGlass, publishButton])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            runAllPublishGroup = stack
        } else {
            let runAll = makeRunAllButton(action: #selector(runAllTapped))
            runAllButton = runAll.button
            runAllSpinner = runAll.spinner
            runAllIcon = runAll.icon

            publishButton = makeLegacyTextButton(label: "Publish", action: #selector(publishTapped))

            let stack = NSStackView(views: [runAllButton, publishButton])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            runAllPublishGroup = stack
        }
        normalToolbar.addSubview(runAllPublishGroup)

        chatButton = makeIconLabelButton(icon: "bubble.fill", label: "Chat", action: #selector(chatTapped))
        normalToolbar.addSubview(chatButton)
    }

    private func makeIconLabelButton(icon: String, label: String, action: Selector) -> NSView {
        if #available(macOS 26, *) {
            return makeGlassIconLabelButton(icon: icon, label: label, action: action)
        } else {
            return makeLegacyIconLabelButton(icon: icon, label: label, action: action)
        }
    }

    @available(macOS 26, *)
    private func makeGlassCapsule() -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.cornerRadius = 18
        glass.tintColor = nil
        return glass
    }

    @available(macOS 26, *)
    private func makeGlassRunAllIcon(action: Selector) -> (click: ToolbarClickView, icon: NSImageView, spinner: NSProgressIndicator) {
        let click = ToolbarClickView(target: self, action: action)
        click.translatesAutoresizingMaskIntoConstraints = false

        let image = NSImageView()
        image.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run all")
        image.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        image.contentTintColor = .labelColor
        image.translatesAutoresizingMaskIntoConstraints = false
        click.addSubview(image)
        click.installCustomTooltip("Run all")

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        click.addSubview(spinner)

        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: click.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: click.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: click.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: click.centerYAnchor),
        ])

        return (click, image, spinner)
    }

    private func makeRunAllButton(action: Selector) -> (button: NSView, spinner: NSProgressIndicator, icon: NSImageView) {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run all")
        icon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let textField = NSTextField(labelWithString: "Run all")
        textField.font = .systemFont(ofSize: 12)
        textField.textColor = .labelColor
        textField.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = ToolbarButtonView(target: self, action: action)
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(spinner)
        wrapper.addSubview(icon)
        wrapper.addSubview(textField)

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        wrapper.layer?.backgroundColor = isDark
            ? NSColor.white.withAlphaComponent(0.04).cgColor
            : NSColor.black.withAlphaComponent(0.04).cgColor

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8),
            spinner.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            textField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            textField.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -8),
            wrapper.heightAnchor.constraint(equalToConstant: 28),
        ])

        return (wrapper, spinner, icon)
    }

    @available(macOS 26, *)
    private func makeGlassTextButton(label: String, action: Selector, weight: NSFont.Weight = .regular, color: NSColor = .labelColor, tint: NSColor? = nil, hoverColor: NSColor? = nil) -> NSView {
        let glass = GlassToolbarButton(target: self, action: action, hoverColor: hoverColor)
        glass.translatesAutoresizingMaskIntoConstraints = false
        if let tint { glass.setBaseTint(tint) }
        let inner = glass.innerView

        let textField = NSTextField(labelWithString: label)
        textField.font = .systemFont(ofSize: 13, weight: weight)
        textField.textColor = color
        textField.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 14),
            textField.centerYAnchor.constraint(equalTo: inner.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -14),
        ])

        return glass
    }

    private func makePrimaryButton(label: String, action: Selector) -> NSView {
        let wrapper = PrimaryToolbarButtonView(target: self, action: action)
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let textField = NSTextField(labelWithString: label)
        textField.font = .systemFont(ofSize: 12, weight: .semibold)
        textField.textColor = .white
        textField.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
            textField.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
            wrapper.heightAnchor.constraint(equalToConstant: 28),
        ])

        return wrapper
    }

    private func makeLegacyTextButton(label: String, action: Selector, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSView {
        let wrapper = ToolbarButtonView(target: self, action: action)
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let textField = NSTextField(labelWithString: label)
        textField.font = .systemFont(ofSize: 12, weight: weight)
        textField.textColor = color
        textField.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
            textField.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
            wrapper.heightAnchor.constraint(equalToConstant: 28),
        ])

        return wrapper
    }

    @available(macOS 26, *)
    private func makeGlassIconButton(icon: String, label: String, action: Selector) -> NSView {
        let glass = GlassToolbarButton(target: self, action: action)
        glass.translatesAutoresizingMaskIntoConstraints = false
        let inner = glass.innerView

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: icon, accessibilityDescription: label)
        imageView.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: inner.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: inner.centerYAnchor),
            glass.widthAnchor.constraint(equalTo: glass.heightAnchor),
        ])

        return glass
    }

    @available(macOS 26, *)
    private func makeGlassIconLabelButton(icon: String, label: String, action: Selector) -> NSView {
        let glass = GlassToolbarButton(target: self, action: action)
        glass.translatesAutoresizingMaskIntoConstraints = false
        let inner = glass.innerView

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: icon, accessibilityDescription: label)
        imageView.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(imageView)

        let textField = NSTextField(labelWithString: label)
        textField.font = .systemFont(ofSize: 13, weight: .regular)
        textField.textColor = .labelColor
        textField.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(textField)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 12),
            imageView.centerYAnchor.constraint(equalTo: inner.centerYAnchor),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
            textField.centerYAnchor.constraint(equalTo: inner.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -12),
        ])

        return glass
    }

    private func makeLegacyIconLabelButton(icon: String, label: String, action: Selector) -> NSView {
        let wrapper = ToolbarButtonView(target: self, action: action)
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: icon, accessibilityDescription: label)
        imageView.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(imageView)

        let textField = NSTextField(labelWithString: label)
        textField.font = .systemFont(ofSize: 12)
        textField.textColor = .labelColor
        textField.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(textField)

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        wrapper.layer?.backgroundColor = isDark
            ? NSColor.white.withAlphaComponent(0.04).cgColor
            : NSColor.black.withAlphaComponent(0.04).cgColor

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8),
            imageView.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            textField.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -8),
            wrapper.heightAnchor.constraint(equalToConstant: 28),
        ])

        return wrapper
    }

    private func setupScrolledTitle() {
        scrolledTitleContainer = NSView()
        scrolledTitleContainer.translatesAutoresizingMaskIntoConstraints = false
        scrolledTitleContainer.isHidden = true
        normalToolbar.addSubview(scrolledTitleContainer)

        scrolledTitleLabel = NSTextField(labelWithString: "")
        scrolledTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        scrolledTitleLabel.textColor = .labelColor
        scrolledTitleLabel.lineBreakMode = .byTruncatingTail
        scrolledTitleLabel.maximumNumberOfLines = 1
        scrolledTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        scrolledTitleContainer.addSubview(scrolledTitleLabel)

        scrolledStatusLabel = NSTextField(labelWithString: "")
        scrolledStatusLabel.font = .systemFont(ofSize: 11)
        scrolledStatusLabel.textColor = .secondaryLabelColor
        scrolledStatusLabel.lineBreakMode = .byTruncatingTail
        scrolledStatusLabel.maximumNumberOfLines = 1
        scrolledStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        scrolledTitleContainer.addSubview(scrolledStatusLabel)

        NSLayoutConstraint.activate([
            scrolledTitleLabel.topAnchor.constraint(equalTo: scrolledTitleContainer.topAnchor),
            scrolledTitleLabel.leadingAnchor.constraint(equalTo: scrolledTitleContainer.leadingAnchor),
            scrolledTitleLabel.trailingAnchor.constraint(equalTo: scrolledTitleContainer.trailingAnchor),

            scrolledStatusLabel.topAnchor.constraint(equalTo: scrolledTitleLabel.bottomAnchor, constant: 1),
            scrolledStatusLabel.leadingAnchor.constraint(equalTo: scrolledTitleContainer.leadingAnchor),
            scrolledStatusLabel.trailingAnchor.constraint(equalTo: scrolledTitleContainer.trailingAnchor),
            scrolledStatusLabel.bottomAnchor.constraint(equalTo: scrolledTitleContainer.bottomAnchor),
        ])
    }

    private func setupNormalConstraints() {
        var constraints = [
            scrolledTitleContainer.leadingAnchor.constraint(equalTo: normalToolbar.leadingAnchor, constant: 16),
            scrolledTitleContainer.centerYAnchor.constraint(equalTo: normalToolbar.centerYAnchor),

            chatButton.trailingAnchor.constraint(equalTo: normalToolbar.trailingAnchor, constant: -8),
            chatButton.centerYAnchor.constraint(equalTo: normalToolbar.centerYAnchor),

            runAllPublishGroup.trailingAnchor.constraint(equalTo: chatButton.leadingAnchor, constant: -8),
            runAllPublishGroup.centerYAnchor.constraint(equalTo: normalToolbar.centerYAnchor),

            scrolledBackground.topAnchor.constraint(equalTo: normalToolbar.topAnchor),
            scrolledBackground.leadingAnchor.constraint(equalTo: normalToolbar.leadingAnchor),
            scrolledBackground.trailingAnchor.constraint(equalTo: normalToolbar.trailingAnchor),
            scrolledBackground.bottomAnchor.constraint(equalTo: normalToolbar.bottomAnchor),
        ]

        if let segmentView {
            constraints += [
                segmentView.centerXAnchor.constraint(equalTo: normalToolbar.centerXAnchor),
                segmentView.centerYAnchor.constraint(equalTo: normalToolbar.centerYAnchor),
                scrolledTitleContainer.trailingAnchor.constraint(lessThanOrEqualTo: segmentView.leadingAnchor, constant: -8),
            ]
            if #available(macOS 26, *) {
                constraints += [
                    chatButton.heightAnchor.constraint(equalTo: segmentView.heightAnchor),
                    publishButton.heightAnchor.constraint(equalTo: chatButton.heightAnchor),
                ]
            }
        } else {
            constraints.append(
                scrolledTitleContainer.trailingAnchor.constraint(lessThanOrEqualTo: runAllPublishGroup.leadingAnchor, constant: -8)
            )
        }

        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Published Toolbar

    private func setupPreviewToolbar() {
        previewToolbar = NSView()
        previewToolbar.translatesAutoresizingMaskIntoConstraints = false
        previewToolbar.isHidden = true
        containerView.addSubview(previewToolbar)

        previewScrolledBackground = ToolbarBlurView()
        previewScrolledBackground.translatesAutoresizingMaskIntoConstraints = false
        previewToolbar.addSubview(previewScrolledBackground, positioned: .below, relativeTo: nil)

        let previewTitleLabel = NSTextField(labelWithString: "Dashboard Preview")
        previewTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        previewTitleLabel.textColor = .labelColor
        previewTitleLabel.lineBreakMode = .byTruncatingTail
        previewTitleLabel.maximumNumberOfLines = 1
        previewTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        previewToolbar.addSubview(previewTitleLabel)

        if #available(macOS 26, *) {
            // Separate glass for icon button (Run all) and text buttons (Cancel | Publish)
            let runAllGlass = makeGlassCapsule()
            let runAll = makeGlassRunAllIcon(action: #selector(runAllTapped))
            runAllGlass.contentView = runAll.click
            previewRunAllButton = runAllGlass
            previewRunAllIcon = runAll.icon
            previewRunAllSpinner = runAll.spinner

            NSLayoutConstraint.activate([
                runAll.click.widthAnchor.constraint(equalToConstant: 36),
                runAll.click.heightAnchor.constraint(equalToConstant: 36),
            ])

            let textGlass = makeGlassCapsule()

            let textContent = NSView()
            textContent.translatesAutoresizingMaskIntoConstraints = false

            let cancelClick = ToolbarClickView(target: self, action: #selector(cancelPublishTapped))
            cancelClick.translatesAutoresizingMaskIntoConstraints = false
            let cancelLabel = NSTextField(labelWithString: "Cancel")
            cancelLabel.font = .systemFont(ofSize: 13)
            cancelLabel.textColor = .labelColor
            cancelLabel.translatesAutoresizingMaskIntoConstraints = false
            cancelClick.addSubview(cancelLabel)
            textContent.addSubview(cancelClick)
            cancelButton = cancelClick

            let publishClick = ToolbarClickView(target: self, action: #selector(confirmPublishTapped))
            publishClick.translatesAutoresizingMaskIntoConstraints = false
            let publishLabel = NSTextField(labelWithString: "Publish")
            publishLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            publishLabel.textColor = .primaryButton
            publishLabel.translatesAutoresizingMaskIntoConstraints = false
            publishClick.addSubview(publishLabel)
            textContent.addSubview(publishClick)
            publishConfirmButton = publishClick

            NSLayoutConstraint.activate([
                cancelLabel.leadingAnchor.constraint(equalTo: cancelClick.leadingAnchor, constant: 12),
                cancelLabel.trailingAnchor.constraint(equalTo: cancelClick.trailingAnchor, constant: -12),
                cancelLabel.centerYAnchor.constraint(equalTo: cancelClick.centerYAnchor),
                cancelClick.leadingAnchor.constraint(equalTo: textContent.leadingAnchor),
                cancelClick.topAnchor.constraint(equalTo: textContent.topAnchor),
                cancelClick.bottomAnchor.constraint(equalTo: textContent.bottomAnchor),

                publishLabel.leadingAnchor.constraint(equalTo: publishClick.leadingAnchor, constant: 12),
                publishLabel.trailingAnchor.constraint(equalTo: publishClick.trailingAnchor, constant: -12),
                publishLabel.centerYAnchor.constraint(equalTo: publishClick.centerYAnchor),
                publishClick.leadingAnchor.constraint(equalTo: cancelClick.trailingAnchor),
                publishClick.topAnchor.constraint(equalTo: textContent.topAnchor),
                publishClick.bottomAnchor.constraint(equalTo: textContent.bottomAnchor),
                publishClick.trailingAnchor.constraint(equalTo: textContent.trailingAnchor),

                textContent.heightAnchor.constraint(equalToConstant: 36),
            ])

            textGlass.contentView = textContent

            let group = NSStackView(views: [runAllGlass, textGlass])
            group.orientation = .horizontal
            group.spacing = 8
            group.translatesAutoresizingMaskIntoConstraints = false
            previewTrailingGroup = group
        } else {
            let previewRunAll = makeRunAllButton(action: #selector(runAllTapped))
            previewRunAllButton = previewRunAll.button
            previewRunAllSpinner = previewRunAll.spinner
            previewRunAllIcon = previewRunAll.icon

            cancelButton = makeLegacyTextButton(label: "Cancel", action: #selector(cancelPublishTapped), weight: .regular, color: .secondaryLabelColor)
            publishConfirmButton = makePrimaryButton(label: "Publish", action: #selector(confirmPublishTapped))

            let stack = NSStackView(views: [previewRunAllButton, cancelButton, publishConfirmButton])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            previewTrailingGroup = stack
        }
        previewToolbar.addSubview(previewTrailingGroup)

        let previewConstraints = [
            previewTitleLabel.centerXAnchor.constraint(equalTo: previewToolbar.centerXAnchor),
            previewTitleLabel.centerYAnchor.constraint(equalTo: previewToolbar.centerYAnchor),

            previewTrailingGroup.trailingAnchor.constraint(equalTo: previewToolbar.trailingAnchor, constant: -8),
            previewTrailingGroup.centerYAnchor.constraint(equalTo: previewToolbar.centerYAnchor),

            previewScrolledBackground.topAnchor.constraint(equalTo: previewToolbar.topAnchor),
            previewScrolledBackground.leadingAnchor.constraint(equalTo: previewToolbar.leadingAnchor),
            previewScrolledBackground.trailingAnchor.constraint(equalTo: previewToolbar.trailingAnchor),
            previewScrolledBackground.bottomAnchor.constraint(equalTo: previewToolbar.bottomAnchor),
        ]
        NSLayoutConstraint.activate(previewConstraints)
    }

    private func setupPublishedToolbar() {
        publishedToolbar = NSView()
        publishedToolbar.translatesAutoresizingMaskIntoConstraints = false
        publishedToolbar.isHidden = true
        containerView.addSubview(publishedToolbar)

        publishedScrolledBackground = ToolbarBlurView()
        publishedScrolledBackground.translatesAutoresizingMaskIntoConstraints = false
        publishedToolbar.addSubview(publishedScrolledBackground, positioned: .below, relativeTo: nil)

        // Scrolled title + status (same pattern as normal toolbar)
        publishedScrolledTitleContainer = NSView()
        publishedScrolledTitleContainer.translatesAutoresizingMaskIntoConstraints = false
        publishedScrolledTitleContainer.isHidden = true
        publishedToolbar.addSubview(publishedScrolledTitleContainer)

        publishedScrolledTitleLabel = NSTextField(labelWithString: "")
        publishedScrolledTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        publishedScrolledTitleLabel.textColor = .labelColor
        publishedScrolledTitleLabel.lineBreakMode = .byTruncatingTail
        publishedScrolledTitleLabel.maximumNumberOfLines = 1
        publishedScrolledTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        publishedScrolledTitleContainer.addSubview(publishedScrolledTitleLabel)

        publishedScrolledStatusLabel = NSTextField(labelWithString: "")
        publishedScrolledStatusLabel.font = .systemFont(ofSize: 11)
        publishedScrolledStatusLabel.textColor = .secondaryLabelColor
        publishedScrolledStatusLabel.lineBreakMode = .byTruncatingTail
        publishedScrolledStatusLabel.maximumNumberOfLines = 1
        publishedScrolledStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        publishedScrolledTitleContainer.addSubview(publishedScrolledStatusLabel)

        let publishedTitleLabel = NSTextField(labelWithString: "Dashboard")
        publishedTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        publishedTitleLabel.textColor = .labelColor
        publishedTitleLabel.lineBreakMode = .byTruncatingTail
        publishedTitleLabel.maximumNumberOfLines = 1
        publishedTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        publishedToolbar.addSubview(publishedTitleLabel)

        // Trailing buttons: refresh status + edit
        if #available(macOS 26, *) {
            editButton = makeGlassTextButton(label: "Edit", action: #selector(editTapped))
        } else {
            editButton = makeLegacyTextButton(label: "Edit", action: #selector(editTapped))
        }
        publishedToolbar.addSubview(editButton)

        refreshStatusButton = RefreshStatusButton(dataController: dataController)
        refreshStatusButton.translatesAutoresizingMaskIntoConstraints = false
        publishedToolbar.addSubview(refreshStatusButton)

        NSLayoutConstraint.activate([
            // Scrolled title container
            publishedScrolledTitleLabel.topAnchor.constraint(equalTo: publishedScrolledTitleContainer.topAnchor),
            publishedScrolledTitleLabel.leadingAnchor.constraint(equalTo: publishedScrolledTitleContainer.leadingAnchor),
            publishedScrolledTitleLabel.trailingAnchor.constraint(equalTo: publishedScrolledTitleContainer.trailingAnchor),

            publishedScrolledStatusLabel.topAnchor.constraint(equalTo: publishedScrolledTitleLabel.bottomAnchor, constant: 1),
            publishedScrolledStatusLabel.leadingAnchor.constraint(equalTo: publishedScrolledTitleContainer.leadingAnchor),
            publishedScrolledStatusLabel.trailingAnchor.constraint(equalTo: publishedScrolledTitleContainer.trailingAnchor),
            publishedScrolledStatusLabel.bottomAnchor.constraint(equalTo: publishedScrolledTitleContainer.bottomAnchor),

            publishedScrolledTitleContainer.leadingAnchor.constraint(equalTo: publishedToolbar.leadingAnchor, constant: 16),
            publishedScrolledTitleContainer.centerYAnchor.constraint(equalTo: publishedToolbar.centerYAnchor),
            publishedScrolledTitleContainer.trailingAnchor.constraint(lessThanOrEqualTo: refreshStatusButton.leadingAnchor, constant: -8),

            publishedTitleLabel.centerXAnchor.constraint(equalTo: publishedToolbar.centerXAnchor),
            publishedTitleLabel.centerYAnchor.constraint(equalTo: publishedToolbar.centerYAnchor),

            // Trailing: refresh status then edit
            editButton.trailingAnchor.constraint(equalTo: publishedToolbar.trailingAnchor, constant: -8),
            editButton.centerYAnchor.constraint(equalTo: publishedToolbar.centerYAnchor),

            refreshStatusButton.trailingAnchor.constraint(equalTo: editButton.leadingAnchor, constant: -8),
            refreshStatusButton.centerYAnchor.constraint(equalTo: publishedToolbar.centerYAnchor),
            refreshStatusButton.heightAnchor.constraint(equalToConstant: 28),

            publishedScrolledBackground.topAnchor.constraint(equalTo: publishedToolbar.topAnchor),
            publishedScrolledBackground.leadingAnchor.constraint(equalTo: publishedToolbar.leadingAnchor),
            publishedScrolledBackground.trailingAnchor.constraint(equalTo: publishedToolbar.trailingAnchor),
            publishedScrolledBackground.bottomAnchor.constraint(equalTo: publishedToolbar.bottomAnchor),
        ])

        if #available(macOS 26, *) {
            editButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        }
    }

    // MARK: - Container Constraints

    private func setupContainerConstraints() {
        NSLayoutConstraint.activate([
            normalToolbar.topAnchor.constraint(equalTo: containerView.topAnchor),
            normalToolbar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            normalToolbar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            normalToolbar.heightAnchor.constraint(equalToConstant: 44),
            normalToolbar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            previewToolbar.topAnchor.constraint(equalTo: containerView.topAnchor),
            previewToolbar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            previewToolbar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            previewToolbar.heightAnchor.constraint(equalToConstant: 44),
            previewToolbar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            publishedToolbar.topAnchor.constraint(equalTo: containerView.topAnchor),
            publishedToolbar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            publishedToolbar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            publishedToolbar.heightAnchor.constraint(equalToConstant: 44),
            publishedToolbar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
    }

    // MARK: - State

    private func applyState() {
        updateToolbarVisibility(animated: false)
        updateScrollState()
        updateScrolledTitleText()
        updateScrolledStatusText()
        updateSegmentSelection(animated: false)
        updateButtonBackgrounds()
    }

    private func updateToolbarVisibility(animated: Bool) {
        let target: NSView
        if dataController.isPublishPreviewing {
            target = previewToolbar
        } else if dataController.isDashboardPublished {
            target = publishedToolbar
        } else {
            target = normalToolbar
        }

        guard shownToolbar !== target else { return }
        let previous = shownToolbar
        shownToolbar = target

        if animated, let previous {
            NotebookTransition.crossfade(show: target, hide: previous)
        } else {
            NotebookTransition.snap(show: target, hide: [normalToolbar, previewToolbar, publishedToolbar])
        }
    }

    private func updateScrollState() {
        let scrolled = dataController.isScrolled
        scrolledTitleContainer.isHidden = !scrolled
        publishedScrolledTitleContainer.isHidden = !scrolled

        if scrolled {
            scrolledBackground.isHidden = false
            previewScrolledBackground.isHidden = false
            publishedScrolledBackground.isHidden = false
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrolledBackground.animator().alphaValue = scrolled ? 1 : 0
            previewScrolledBackground.animator().alphaValue = scrolled ? 1 : 0
            publishedScrolledBackground.animator().alphaValue = scrolled ? 1 : 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.dataController.isScrolled {
                    self.scrolledBackground.isHidden = true
                    self.previewScrolledBackground.isHidden = true
                    self.publishedScrolledBackground.isHidden = true
                }
            }
        }
    }

    private func updateScrolledTitleText() {
        let title = dataController.title
        let displayTitle = title.isEmpty ? "Untitled Notebook" : title
        scrolledTitleLabel.stringValue = displayTitle
        publishedScrolledTitleLabel.stringValue = displayTitle
    }

    private func updateScrolledStatusText() {
        let status = dataController.status.rawValue
        scrolledStatusLabel.stringValue = status
        publishedScrolledStatusLabel.stringValue = status
    }

    private func updateSegmentSelection(animated: Bool) {
        guard segmentView != nil else { return }
        let isNotebook = dataController.viewMode == .notebook

        // macOS 26 glass segment path
        if #available(macOS 26, *), segmentContainer == nil {
            (notebookSegmentButton as? GlassSegmentButton)?.isActive = isNotebook
            (dashboardSegmentButton as? GlassSegmentButton)?.isActive = !isNotebook
            return
        }

        // Pre-macOS 26 custom segment path
        guard let highlight = segmentHighlight,
              let nbButton = notebookSegmentButton,
              let dbButton = dashboardSegmentButton else { return }

        let targetButton = isNotebook ? nbButton : dbButton
        nbButton.contentTintColor = isNotebook ? .labelColor : .secondaryLabelColor
        dbButton.contentTintColor = isNotebook ? .secondaryLabelColor : .labelColor

        segmentHighlightLeading?.isActive = false
        segmentHighlightLeading = highlight.leadingAnchor.constraint(equalTo: targetButton.leadingAnchor)
        segmentHighlightLeading?.isActive = true

        for c in highlight.constraints where c.firstAttribute == .width {
            c.isActive = false
        }
        highlight.widthAnchor.constraint(equalTo: targetButton.widthAnchor).isActive = true

        if animated {
            NotebookTransition.run { [weak self] in
                self?.segmentContainer?.layoutSubtreeIfNeeded()
            }
        }
    }

    // MARK: - Actions

    @objc private func selectNotebook() {
        guard dataController.viewMode != .notebook else { return }
        dataController.viewMode = .notebook
    }

    @objc private func selectDashboard() {
        guard dataController.viewMode != .dashboard else { return }
        dataController.viewMode = .dashboard
    }

    @objc private func publishTapped() {
        dataController.beginPublishPreview()
    }

    @objc private func confirmPublishTapped() {
        showPublishConfirmation()
    }

    @objc private func cancelPublishTapped() {
        dataController.cancelPublishPreview()
    }

    private func showPublishConfirmation() {
        guard publishPopover == nil, let anchor = publishConfirmButton else { return }

        let controller = PublishConfirmationController { [weak self] in
            self?.dataController.publishDashboard()
        }
        let popover = NSPopover()
        popover.delegate = self
        popover.contentViewController = controller
        popover.behavior = .transient
        controller.popover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        publishPopover = popover
    }

    @objc private func editTapped() {
        dataController.isViewingPublished = false
        dataController.viewMode = .notebook
    }

    @objc private func runAllTapped() {
        guard !dataController.isRefreshing else { return }
        dataController.rerunAllQueries()
    }

    @objc private func chatTapped() {
        dataController.isRightSidebarVisible.toggle()
    }

    // MARK: - Appearance

    @objc private func appearanceChanged() {
        updateSegmentContainerColor()
        updateSegmentHighlightColor()
        updateButtonBackgrounds()
        scrolledBackground.updateAppearance()
        previewScrolledBackground.updateAppearance()
        publishedScrolledBackground.updateAppearance()
    }

    private func updateSegmentContainerColor() {
        guard let container = segmentContainer else { return }
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            container.layer?.backgroundColor = isDark
                ? NSColor.black.withAlphaComponent(0.2).cgColor
                : NSColor.black.withAlphaComponent(0.04).cgColor
        }
    }

    private func updateSegmentHighlightColor() {
        guard let highlight = segmentHighlight else { return }
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            highlight.layer?.backgroundColor = isDark
                ? NSColor.controlColor.withAlphaComponent(0.3).cgColor
                : NSColor.white.cgColor
        }
    }

    private func updateSegmentHighlightShadow() {
        guard let highlight = segmentHighlight else { return }
        highlight.shadow = NSShadow()
        highlight.layer?.shadowColor = NSColor.black.withAlphaComponent(0.10).cgColor
        highlight.layer?.shadowOpacity = 1
        highlight.layer?.shadowRadius = 1
        highlight.layer?.shadowOffset = .zero
    }

    private func updateButtonBackgrounds() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            let bgColor = isDark
                ? NSColor.white.withAlphaComponent(0.04).cgColor
                : NSColor.black.withAlphaComponent(0.04).cgColor
            chatButton?.layer?.backgroundColor = bgColor
            cancelButton?.layer?.backgroundColor = bgColor
            editButton?.layer?.backgroundColor = bgColor
            publishButton?.layer?.backgroundColor = bgColor
            runAllButton?.layer?.backgroundColor = bgColor
            previewRunAllButton?.layer?.backgroundColor = bgColor
            (publishConfirmButton as? PrimaryToolbarButtonView)?.updateBackground()
        }
    }

    // MARK: - Observation

    private func observeViewMode() {
        withObservationTracking {
            _ = self.dataController.viewMode
            _ = self.dataController.isDashboardPublished
            _ = self.dataController.isPublishPreviewing
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateToolbarVisibility(animated: true)
                self.updateSegmentSelection(animated: true)
                self.observeViewMode()
            }
        }
    }

    private func observeScrollState() {
        withObservationTracking {
            _ = self.dataController.isScrolled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateScrollState()
                self.observeScrollState()
            }
        }
    }

    private func observeTitle() {
        withObservationTracking {
            _ = self.dataController.title
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateScrolledTitleText()
                self.observeTitle()
            }
        }
    }

    private func observeStatus() {
        withObservationTracking {
            _ = self.dataController.status
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateScrolledStatusText()
                self.observeStatus()
            }
        }
    }

    private func observeRefreshingState() {
        withObservationTracking {
            _ = self.dataController.isRefreshing
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateRunAllButtons()
                self.observeRefreshingState()
            }
        }
    }

    private func updateRunAllButtons() {
        let refreshing = dataController.isRefreshing

        runAllIcon?.isHidden = refreshing
        runAllSpinner?.isHidden = !refreshing
        if refreshing { runAllSpinner?.startAnimation(nil) } else { runAllSpinner?.stopAnimation(nil) }

        previewRunAllIcon?.isHidden = refreshing
        previewRunAllSpinner?.isHidden = !refreshing
        if refreshing { previewRunAllSpinner?.startAnimation(nil) } else { previewRunAllSpinner?.stopAnimation(nil) }
    }

}

// MARK: - Popover Delegate

extension NotebookToolbarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        publishPopover = nil
    }
}

// MARK: - Glass Toolbar Button

@available(macOS 26, *)
private final class GlassToolbarButton: NSGlassEffectView {

    let innerView: GlassToolbarButtonInner
    private var baseTintColor: NSColor?
    private var hoverTintColor: NSColor?

    init(target: AnyObject, action: Selector, hoverColor: NSColor? = nil) {
        self.hoverTintColor = hoverColor
        innerView = GlassToolbarButtonInner(target: target, action: action, onHoverChanged: nil)
        super.init(frame: .zero)
        if hoverColor != nil {
            innerView.onHoverChanged = { [weak self] hovering in
                guard let self, let hoverTintColor else { return }
                self.tintColor = hovering
                    ? hoverTintColor.blended(withFraction: 0.35, of: .black)
                    : self.baseTintColor
            }
        }
        innerView.translatesAutoresizingMaskIntoConstraints = false
        contentView = innerView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        cornerRadius = bounds.height / 2
    }

    func setBaseTint(_ color: NSColor) {
        baseTintColor = color
        tintColor = color
    }
}

@available(macOS 26, *)
private final class GlassToolbarButtonInner: NSView {

    private weak var target: AnyObject?
    private let action: Selector
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private let hoverLayer = CALayer()

    init(target: AnyObject, action: Selector, onHoverChanged: ((Bool) -> Void)?) {
        self.target = target
        self.action = action
        self.onHoverChanged = onHoverChanged
        super.init(frame: .zero)
        wantsLayer = true
        hoverLayer.masksToBounds = true
        layer?.addSublayer(hoverLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 3
        let pillRect = bounds.insetBy(dx: inset, dy: inset)
        hoverLayer.frame = pillRect
        hoverLayer.cornerRadius = pillRect.height / 2
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
        updateHover()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateHover()
    }

    override func mouseDown(with event: NSEvent) {
        _ = target?.perform(action, with: nil)
    }

    private func refreshHoverState() {
        guard let window, bounds.width > 0 else {
            if isHovering {
                isHovering = false
                updateHover()
            }
            return
        }
        let loc = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let inside = bounds.contains(loc)
        if inside != isHovering {
            isHovering = inside
            updateHover()
        }
    }

    private func updateHover() {
        onHoverChanged?(isHovering)
        guard onHoverChanged == nil else { return }
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            if isHovering {
                hoverLayer.backgroundColor = (isDark
                    ? NSColor(white: 0.17, alpha: 1)
                    : NSColor(white: 0.949, alpha: 1)).cgColor
            } else {
                hoverLayer.backgroundColor = nil
            }
        }
    }
}

// MARK: - Capsule Glass View

@available(macOS 26, *)
private final class CapsuleGlassView: NSGlassEffectView {
    override func layout() {
        super.layout()
        cornerRadius = bounds.height / 2
    }
}

// MARK: - Glass Segment Button

@available(macOS 26, *)
private final class GlassSegmentButton: NSButton {

    var isActive = false {
        didSet { updateBackground() }
    }

    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private let backgroundLayer = CALayer()

    convenience init(title: String, target: AnyObject?, action: Selector) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.isBordered = false
        self.font = .systemFont(ofSize: 13, weight: .regular)
        self.contentTintColor = .labelColor
        (self.cell as? NSButtonCell)?.highlightsBy = []
        self.translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        backgroundLayer.masksToBounds = true
        layer?.insertSublayer(backgroundLayer, at: 0)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
        ])
    }

    override var intrinsicContentSize: NSSize {
        let titleSize = attributedTitle.size()
        return NSSize(
            width: titleSize.width + 24,
            height: titleSize.height + 18
        )
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 3
        let pillRect = bounds.insetBy(dx: 0, dy: inset)
        backgroundLayer.frame = pillRect
        backgroundLayer.cornerRadius = pillRect.height / 2
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
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateBackground()
    }

    private func updateBackground() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            if isActive {
                backgroundLayer.backgroundColor = (isDark
                    ? NSColor(white: 0.22, alpha: 1)
                    : NSColor(white: 0.898, alpha: 1)).cgColor
            } else if isHovering {
                backgroundLayer.backgroundColor = (isDark
                    ? NSColor(white: 0.17, alpha: 1)
                    : NSColor(white: 0.949, alpha: 1)).cgColor
            } else {
                backgroundLayer.backgroundColor = nil
            }
        }
    }
}

// MARK: - Toolbar Blur View

private final class ToolbarBlurView: NSView {

    private var tintLayer: CALayer?
    private var didSetup = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didSetup else { return }
        setupLayers()
    }

    func updateAppearance() {
        guard let tintLayer else { return }
        applyTintColor(tintLayer)
    }

    private func setupLayers() {
        guard let layer else { return }
        didSetup = true

        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let filterClass = NSClassFromString("CAFilter")
        else { return }

        let backdrop = backdropClass.init()
        backdrop.frame = layer.bounds
        backdrop.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backdrop.setValue(15.0, forKey: "bleedAmount")
        backdrop.setValue(0.25, forKey: "scale")
        backdrop.setValue(false, forKey: "allowsInPlaceFiltering")
        backdrop.setValue(true, forKey: "allowsGroupBlending")

        let filterSel = NSSelectorFromString("filterWithType:")

        guard let blur = (filterClass as AnyObject).perform(filterSel, with: "gaussianBlur")?
            .takeUnretainedValue() as? NSObject else { return }
        blur.setValue(2.0, forKey: "inputRadius")
        blur.setValue(false, forKey: "inputNormalizeEdges")

        guard let saturate = (filterClass as AnyObject).perform(filterSel, with: "colorSaturate")?
            .takeUnretainedValue() as? NSObject else { return }
        saturate.setValue(1.6, forKey: "inputAmount")

        backdrop.filters = [saturate, blur]
        layer.addSublayer(backdrop)

        let tint = CALayer()
        tint.frame = layer.bounds
        tint.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        applyTintColor(tint)
        layer.addSublayer(tint)
        tintLayer = tint
    }

    private func applyTintColor(_ tint: CALayer) {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            tint.backgroundColor = isDark
                ? NSColor(white: 0.15, alpha: 0.25).cgColor
                : NSColor(white: 1.0, alpha: 0.25).cgColor
        }
    }
}

// MARK: - Toolbar Click View (bare click target for glass contentView)

private final class ToolbarClickView: NSView {

    private weak var target: AnyObject?
    private let action: Selector
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private let hoverView = NSView()

    init(target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
        super.init(frame: .zero)

        hoverView.wantsLayer = true
        hoverView.layer?.masksToBounds = true
        hoverView.alphaValue = 0
        addSubview(hoverView, positioned: .below, relativeTo: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 3
        let pillRect = bounds.insetBy(dx: inset, dy: inset)
        hoverView.frame = pillRect
        hoverView.layer?.cornerRadius = pillRect.height / 2
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
        updateHover()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateHover()
    }

    override func mouseDown(with event: NSEvent) {
        // no-op, wait for mouseUp
    }

    override func mouseUp(with event: NSEvent) {
        guard let target else { return }
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    private func refreshHoverState() {
        guard let window, bounds.width > 0 else {
            if isHovering {
                isHovering = false
                updateHover()
            }
            return
        }
        let loc = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let inside = bounds.contains(loc)
        if inside != isHovering {
            isHovering = inside
            updateHover()
        }
    }

    private func updateHover() {
        if isHovering {
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                let isDark = NSAppearance.currentDrawing().isDarkMode
                hoverView.layer?.backgroundColor = (isDark
                    ? NSColor(white: 0.17, alpha: 1)
                    : NSColor(white: 0.949, alpha: 1)).cgColor
            }
            hoverView.alphaValue = 1
        } else {
            hoverView.alphaValue = 0
        }
    }
}

// MARK: - Toolbar Button View

private final class ToolbarButtonView: NSView {

    private weak var target: AnyObject?
    private let action: Selector
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
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
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        _ = target?.perform(action, with: nil)
    }

    private func updateBackground() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isHovering {
            layer?.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.10).cgColor
                : NSColor.black.withAlphaComponent(0.08).cgColor
        } else {
            layer?.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.04).cgColor
                : NSColor.black.withAlphaComponent(0.04).cgColor
        }
    }
}

private final class PrimaryToolbarButtonView: NSView {

    private weak var target: AnyObject?
    private let action: Selector
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        updateBackground()
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
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        _ = target?.perform(action, with: nil)
    }

    func updateBackground() {
        let accent = NSColor.primaryButton
        if isHovering {
            layer?.backgroundColor = accent.withAlphaComponent(0.85).cgColor
        } else {
            layer?.backgroundColor = accent.cgColor
        }
    }
}

// MARK: - Publish Confirmation Popover

private final class PublishConfirmationController: NSViewController, NSPopoverDelegate {

    private let onConfirm: @MainActor () -> Void
    weak var popover: NSPopover?

    init(onConfirm: @escaping @MainActor () -> Void) {
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Publish Dashboard")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        let desc = NSTextField(wrappingLabelWithString: "Lock the dashboard into a read-only view. You can edit again anytime.")
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = .secondaryLabelColor
        desc.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(desc)

        // Share link row (coming soon — disabled)
        let linkRow = NSView()
        linkRow.wantsLayer = true
        linkRow.layer?.cornerRadius = 8
        linkRow.layer?.borderWidth = 1
        linkRow.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        linkRow.translatesAutoresizingMaskIntoConstraints = false
        linkRow.alphaValue = 0.5
        container.addSubview(linkRow)

        let linkIcon = NSImageView()
        linkIcon.image = NSImage(systemSymbolName: "link", accessibilityDescription: "Share link")
        linkIcon.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        linkIcon.contentTintColor = .secondaryLabelColor
        linkIcon.translatesAutoresizingMaskIntoConstraints = false
        linkRow.addSubview(linkIcon)

        let linkLabel = NSTextField(labelWithString: "Share with public link")
        linkLabel.font = .systemFont(ofSize: 12)
        linkLabel.textColor = .secondaryLabelColor
        linkLabel.translatesAutoresizingMaskIntoConstraints = false
        linkRow.addSubview(linkLabel)

        let comingSoonTag = NSTextField(labelWithString: "Soon")
        comingSoonTag.font = .systemFont(ofSize: 10, weight: .medium)
        comingSoonTag.textColor = .tertiaryLabelColor
        comingSoonTag.alignment = .center
        comingSoonTag.wantsLayer = true
        comingSoonTag.layer?.cornerRadius = 4
        comingSoonTag.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        comingSoonTag.translatesAutoresizingMaskIntoConstraints = false
        linkRow.addSubview(comingSoonTag)

        // Publish button — full-width primary style
        let publishButton = PrimaryActionButton(title: "Publish Dashboard", target: self, action: #selector(confirmTapped))
        publishButton.keyEquivalent = "\r"
        publishButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(publishButton)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            desc.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            desc.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            desc.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            linkRow.topAnchor.constraint(equalTo: desc.bottomAnchor, constant: 16),
            linkRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            linkRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            linkRow.heightAnchor.constraint(equalToConstant: 36),

            linkIcon.leadingAnchor.constraint(equalTo: linkRow.leadingAnchor, constant: 10),
            linkIcon.centerYAnchor.constraint(equalTo: linkRow.centerYAnchor),

            linkLabel.leadingAnchor.constraint(equalTo: linkIcon.trailingAnchor, constant: 6),
            linkLabel.centerYAnchor.constraint(equalTo: linkRow.centerYAnchor),

            comingSoonTag.trailingAnchor.constraint(equalTo: linkRow.trailingAnchor, constant: -10),
            comingSoonTag.centerYAnchor.constraint(equalTo: linkRow.centerYAnchor),
            comingSoonTag.widthAnchor.constraint(equalToConstant: 40),
            comingSoonTag.heightAnchor.constraint(equalToConstant: 18),

            publishButton.topAnchor.constraint(equalTo: linkRow.bottomAnchor, constant: 16),
            publishButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            publishButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            publishButton.heightAnchor.constraint(equalToConstant: 36),
            publishButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),

            container.widthAnchor.constraint(equalToConstant: 280),
        ])

        self.view = container
    }

    @objc private func confirmTapped() {
        onConfirm()
        popover?.performClose(nil)
    }
}

// MARK: - Primary Action Button

private final class PrimaryActionButton: NSButton {

    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    convenience init(title: String, target: AnyObject?, action: Selector) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.isBordered = false
        self.font = .systemFont(ofSize: 13, weight: .medium)
        self.alignment = .center
        self.wantsLayer = true
        self.layer?.cornerRadius = 8
        (self.cell as? NSButtonCell)?.highlightsBy = []
        updateColors()
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
        updateColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateColors()
    }

    private static let darkColor = NSColor(red: 0xE5 / 255.0, green: 0x7E / 255.0, blue: 0x52 / 255.0, alpha: 1.0)
    private static let lightColor = NSColor(red: 0xB9 / 255.0, green: 0x55 / 255.0, blue: 0x31 / 255.0, alpha: 1.0)

    private func updateColors() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let baseColor = isDark ? Self.darkColor : Self.lightColor
        layer?.backgroundColor = isHovering
            ? baseColor.withAlphaComponent(0.85).cgColor
            : baseColor.cgColor
        contentTintColor = .white
    }
}

// MARK: - Refresh Status Button

final class RefreshStatusButton: NSView, NSPopoverDelegate {

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private let dataController: NotebookDataController
    private let warningIcon: NSImageView
    private let spinner: NSProgressIndicator
    private let timeLabel: NSTextField
    private var labelLeadingWithIcon: NSLayoutConstraint!
    private var labelLeadingWithSpinner: NSLayoutConstraint!
    private var labelLeadingWithoutIcon: NSLayoutConstraint!
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var popover: NSPopover?
    private var refreshTask: Task<Void, Never>?

    init(dataController: NotebookDataController) {
        self.dataController = dataController
        self.warningIcon = NSImageView()
        self.spinner = NSProgressIndicator()
        self.timeLabel = NSTextField(labelWithString: "")
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        warningIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Data may be stale")
        warningIcon.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        warningIcon.contentTintColor = .systemOrange
        warningIcon.translatesAutoresizingMaskIntoConstraints = false
        warningIcon.isHidden = true
        addSubview(warningIcon)

        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        addSubview(spinner)

        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        labelLeadingWithIcon = timeLabel.leadingAnchor.constraint(equalTo: warningIcon.trailingAnchor, constant: 4)
        labelLeadingWithSpinner = timeLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 4)
        labelLeadingWithoutIcon = timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        labelLeadingWithoutIcon.isActive = true

        NSLayoutConstraint.activate([
            warningIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            warningIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            warningIcon.widthAnchor.constraint(equalToConstant: 14),

            spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),

            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])

        updateDisplay()
        observeRefreshState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        refreshTask?.cancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateDisplay()
        } else {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    func updateDisplay() {
        let refreshing = dataController.isRefreshing
        if refreshing {
            popover?.performClose(nil)
            setLeadingMode(.spinner)
            refreshTask?.cancel()
            refreshTask = nil
            return
        }

        guard let refreshedAt = dataController.lastRefreshedAt else {
            setLeadingMode(.warning)
            timeLabel.stringValue = "Never refreshed"
            timeLabel.textColor = .tertiaryLabelColor
            refreshTask?.cancel()
            refreshTask = nil
            return
        }

        let elapsed = Date().timeIntervalSince(refreshedAt)
        let isStale = elapsed > 24 * 60 * 60
        setLeadingMode(isStale ? .warning : .plain)

        if elapsed < 60 {
            timeLabel.stringValue = "Just now"
        } else {
            timeLabel.stringValue = Self.relativeFormatter.localizedString(for: refreshedAt, relativeTo: Date())
        }
        timeLabel.textColor = isStale ? .systemOrange : .tertiaryLabelColor

        scheduleNextUpdate(elapsed: elapsed)
    }

    private func scheduleNextUpdate(elapsed: TimeInterval) {
        refreshTask?.cancel()
        guard window != nil else { return }

        let interval: TimeInterval
        if elapsed < 60 {
            interval = 61 - elapsed
        } else if elapsed < 3600 {
            interval = 60
        } else {
            interval = 300
        }

        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.updateDisplay()
        }
    }

    private enum LeadingMode { case plain, warning, spinner }

    private func setLeadingMode(_ mode: LeadingMode) {
        warningIcon.isHidden = mode != .warning
        spinner.isHidden = mode != .spinner
        if mode == .spinner {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        labelLeadingWithIcon.isActive = mode == .warning
        labelLeadingWithSpinner.isActive = mode == .spinner
        labelLeadingWithoutIcon.isActive = mode == .plain
    }

    // MARK: - Tracking

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
        applyHoverBackground(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(false)
    }

    override func mouseDown(with event: NSEvent) {
        if popover != nil {
            popover?.performClose(nil)
            return
        }
        showRefreshPopover()
    }

    // MARK: - Popover

    private func showRefreshPopover() {
        let vc = RefreshPopoverController(dataController: dataController)
        let pop = NSPopover()
        pop.delegate = self
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        self.popover = pop
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }

    // MARK: - Observation

    private func observeRefreshState() {
        withObservationTracking {
            _ = self.dataController.isRefreshing
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateDisplay()
                self.observeRefreshState()
            }
        }
    }
}

// MARK: - Refresh Popover Controller

private final class RefreshPopoverController: NSViewController {

    private let dataController: NotebookDataController
    private var refreshButton: PrimaryActionButton?

    init(dataController: NotebookDataController) {
        self.dataController = dataController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Title: "Data refreshed: 1h ago"
        let refreshedAt = dataController.lastRefreshedAt
        let timeText: String
        if let refreshedAt {
            timeText = RefreshStatusButton.relativeFormatter.localizedString(for: refreshedAt, relativeTo: Date())
        } else {
            timeText = "never"
        }

        let title = NSTextField(labelWithString: "Data refreshed:  \(timeText)")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        let desc = NSTextField(wrappingLabelWithString: "This dashboard automatically fetches new data after 24 hours.")
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = .secondaryLabelColor
        desc.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(desc)

        let button = PrimaryActionButton(title: "Refresh data now", target: self, action: #selector(refreshTapped))
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        refreshButton = button

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            desc.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            desc.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            desc.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            button.topAnchor.constraint(equalTo: desc.bottomAnchor, constant: 14),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            button.heightAnchor.constraint(equalToConstant: 34),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            container.widthAnchor.constraint(equalToConstant: 260),
        ])

        self.view = container

        if dataController.isRefreshing {
            setRefreshing(true)
        }
        observeRefreshState()
    }

    @objc private func refreshTapped() {
        dataController.rerunAllQueries()
        setRefreshing(true)
    }

    private func setRefreshing(_ refreshing: Bool) {
        refreshButton?.isEnabled = !refreshing
        refreshButton?.title = refreshing ? "Refreshing…" : "Refresh data now"
    }

    private func observeRefreshState() {
        withObservationTracking {
            _ = self.dataController.isRefreshing
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setRefreshing(self.dataController.isRefreshing)
                if !self.dataController.isRefreshing {
                    return
                }
                self.observeRefreshState()
            }
        }
    }
}
