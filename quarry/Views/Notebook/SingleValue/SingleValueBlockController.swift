import AppKit
import SwiftUI

final class SingleValueBlockController: NSViewController, NSTextFieldDelegate {

    let viewModel: SingleValueBlockViewModel
    private let dataController: NotebookDataController
    private let showChrome: Bool

    private(set) var titleLabel: NSTextField!
    private var runButton: NSButton!
    private var configButton: NSButton!
    private var blockContainer: NSView!
    private var menuButton: NSButton!
    private var resizeHandle: NSView!
    private var blockHeightConstraint: NSLayoutConstraint!
    private var configController: SingleValueConfigController?
    private var configPopover: NSPopover?

    init(block: NotebookBlock, dataController: NotebookDataController, showChrome: Bool = true) {
        self.dataController = dataController
        self.viewModel = dataController.singleValueViewModel(for: block)
        self.showChrome = showChrome
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        if showChrome {
            let wrapper = BlockHoverTrackingView { [weak self] isHovered in
                guard let self,
                      let blockIndex = self.dataController.blocks.firstIndex(where: { $0.id == self.viewModel.block.id }) else { return }
                let showButtons = isHovered || self.configPopover?.isShown == true || self.popover?.isShown == true
                self.runButton.isHidden = !showButtons
                self.configButton.isHidden = !showButtons
                self.menuButton.isHidden = !showButtons
                NotificationCenter.default.post(
                    name: .notebookBlockHoverChanged,
                    object: nil,
                    userInfo: ["blockIndex": blockIndex, "isHovered": isHovered]
                )
            }
            wrapper.wantsLayer = true
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            self.view = wrapper

            setupTitleLabel()
            setupRunButton()
            setupConfigButton()
            setupBlockContainer()
            setupMenuButton()
            setupResizeHandle()
            setupWrapperConstraints()
            setupConfigView()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppearanceChange),
                name: .appAppearanceDidChange,
                object: nil
            )
        } else {
            let wrapper = NSView()
            wrapper.wantsLayer = true
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            self.view = wrapper

            setupBlockContainer()
            blockContainer.layer?.borderWidth = 0

            NSLayoutConstraint.activate([
                blockContainer.topAnchor.constraint(equalTo: view.topAnchor),
                blockContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                blockContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                blockContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            setupConfigView()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    private func setupTitleLabel() {
        let text = viewModel.block.title.isEmpty ? "Untitled Single Value" : viewModel.block.title
        titleLabel = NSTextField(string: text)
        titleLabel.placeholderString = "Untitled Single Value"
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.backgroundColor = .clear
        titleLabel.isBordered = false
        titleLabel.isBezeled = false
        titleLabel.focusRingType = .none
        titleLabel.isEditable = true
        titleLabel.delegate = self
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
    }

    private func setupRunButton() {
        runButton = NSButton(frame: .zero)
        runButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run")
        runButton.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        runButton.bezelStyle = .accessoryBar
        runButton.isBordered = false
        runButton.imagePosition = .imageOnly
        runButton.contentTintColor = .white
        runButton.wantsLayer = true
        runButton.layer?.cornerRadius = 4
        runButton.layer?.backgroundColor = NSColor.primaryButton.cgColor
        runButton.translatesAutoresizingMaskIntoConstraints = false
        runButton.isHidden = true
        runButton.target = self
        runButton.action = #selector(handleRunTapped)
        view.addSubview(runButton)

    }

    @objc private func handleRunTapped() {
        Task { await viewModel.fetchSingleValue() }
    }

    private func setupConfigButton() {
        configButton = NSButton(frame: .zero)
        configButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Configure single value")
        configButton.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        configButton.bezelStyle = .accessoryBar
        configButton.isBordered = false
        configButton.imagePosition = .imageOnly
        configButton.contentTintColor = .tertiaryLabelColor
        configButton.translatesAutoresizingMaskIntoConstraints = false
        configButton.isHidden = true
        configButton.target = self
        configButton.action = #selector(showConfigPopover(_:))
        view.addSubview(configButton)
    }

    @objc private func showConfigPopover(_ sender: NSButton) {
        let popoverVC = SingleValueConfigPopoverController(
            viewModel: viewModel,
            connections: dataController.connections,
            dataController: dataController
        )

        let pop = NSPopover()
        pop.contentViewController = popoverVC
        pop.behavior = .transient
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        configPopover = pop
    }

    private func setupBlockContainer() {
        blockContainer = NSView()
        blockContainer.wantsLayer = true
        blockContainer.layer?.cornerRadius = 10
        blockContainer.layer?.borderWidth = 1
        blockContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blockContainer)
        updateBorderColor()
    }

    private func setupMenuButton() {
        menuButton = NSButton(frame: .zero)
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Block menu")
        menuButton.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        menuButton.bezelStyle = .accessoryBar
        menuButton.isBordered = false
        menuButton.imagePosition = .imageOnly
        menuButton.contentTintColor = .tertiaryLabelColor
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.isHidden = true
        menuButton.target = self
        menuButton.action = #selector(showBlockMenu(_:))
        view.addSubview(menuButton)
    }

    private func setupResizeHandle() {
        resizeHandle = BlockResizeHandle(onDrag: { [weak self] delta in
            self?.handleResize(delta: delta)
        })
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resizeHandle)
    }

    private func handleResize(delta: CGFloat) {
        let newHeight = max(140, blockHeightConstraint.constant + delta)
        blockHeightConstraint.constant = newHeight
        viewModel.block.blockHeight = newHeight
        dataController.updateBlock(viewModel.block)
    }

    private func setupWrapperConstraints() {
        let savedHeight = max(140, viewModel.block.blockHeight)
        blockHeightConstraint = blockContainer.heightAnchor.constraint(equalToConstant: savedHeight)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            menuButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            menuButton.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 24),
            menuButton.heightAnchor.constraint(equalToConstant: 24),

            runButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            runButton.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor),
            runButton.widthAnchor.constraint(equalToConstant: 18),
            runButton.heightAnchor.constraint(equalToConstant: 12),

            configButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            configButton.trailingAnchor.constraint(equalTo: runButton.leadingAnchor),
            configButton.widthAnchor.constraint(equalToConstant: 20),
            configButton.heightAnchor.constraint(equalToConstant: 20),

            blockContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            blockContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blockContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blockHeightConstraint,

            resizeHandle.topAnchor.constraint(equalTo: blockContainer.bottomAnchor),
            resizeHandle.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            resizeHandle.heightAnchor.constraint(equalToConstant: 12),
            resizeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === titleLabel else { return }
        viewModel.block.title = field.stringValue
        dataController.updateBlock(viewModel.block)
    }

    // MARK: - Block Menu

    @objc private func showBlockMenu(_ sender: NSButton) {
        let block = viewModel.block
        let dc = dataController
        let dismiss = { [weak self] in self?.popover?.performClose(nil) }

        let blockIndex = dc.blocks.firstIndex(where: { $0.id == block.id }) ?? 0
        let isFirst = blockIndex == 0
        let isLast = blockIndex == dc.blocks.count - 1

        let popoverVC = BlockMenuPopoverController(
            canMoveUp: !isFirst,
            canMoveDown: !isLast,
            onAddAbove: { dismiss(); dc.insertSingleValueBlock(at: blockIndex) },
            onAddBelow: { dismiss(); dc.insertSingleValueBlock(at: blockIndex + 1) },
            onMoveUp: { dismiss(); dc.moveBlockUp(block) },
            onMoveDown: { dismiss(); dc.moveBlockDown(block) },
            onDuplicate: { dismiss(); dc.duplicateBlock(block) },
            onCopy: { [weak self] in dismiss(); self?.copyBlockConfig() },
            onDelete: { dismiss(); dc.deleteBlock(block) }
        )

        let pop = NSPopover()
        pop.contentViewController = popoverVC
        pop.behavior = .transient
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        self.popover = pop
    }

    private var popover: NSPopover?

    private func copyBlockConfig() {
        let json = viewModel.block.configJSON
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    // MARK: - Block Styling

    private func updateBorderColor() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            blockContainer.layer?.borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.1).cgColor
                : NSColor.black.withAlphaComponent(0.08).cgColor
        }
    }

    @objc private func handleAppearanceChange() {
        updateBorderColor()
    }

    // MARK: - Content

    private func setupConfigView() {
        let configVC = SingleValueConfigController(viewModel: viewModel, connections: dataController.connections, dataController: dataController)
        addChild(configVC)
        configVC.view.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(configVC.view)
        configController = configVC

        NSLayoutConstraint.activate([
            configVC.view.topAnchor.constraint(equalTo: blockContainer.topAnchor),
            configVC.view.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            configVC.view.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            configVC.view.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),
        ])
    }

    // MARK: - Cleanup

    func cleanupSession() {
        Task { await viewModel.cleanup() }
    }
}
