//
//  SettingsWindowController.swift
//  Quarry
//

import Cocoa
import SwiftUI

// MARK: - Window Controller

@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    static let shared = SettingsWindowController()

    private var splitViewController: SettingsSplitViewController?
    private var navigationHistory = SettingsNavigationHistory()

    private static let defaultWindowSize = NSSize(width: 780, height: 570)
    private static let minimumWindowSize = NSSize(width: 680, height: 536)
    private static let windowFrameAutosaveName = "SettingsWindowFrame"

    private static let backForwardIdentifier = NSToolbarItem.Identifier("backForward")

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .visible
        window.toolbarStyle = .automatic
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .automatic
        window.contentMinSize = Self.minimumWindowSize
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        restoreWindowFrame(window)

        let splitVC = SettingsSplitViewController(
            onPaneChange: { [weak self] pane, isUserSelection in
                self?.updateTitle(pane.rawValue)
                if isUserSelection {
                    self?.navigationHistory.push(pane)
                }
                self?.updateToolbarButtons()
            }
        )
        splitViewController = splitVC
        window.contentViewController = splitVC

        navigationHistory.push(.general)
        updateTitle(SettingsPane.general.rawValue)
        updateToolbarButtons()
    }

    private func restoreWindowFrame(_ window: NSWindow) {
        let restoredFrame = window.setFrameUsingName(Self.windowFrameAutosaveName)
        window.setFrameAutosaveName(Self.windowFrameAutosaveName)

        if !restoredFrame {
            window.setContentSize(Self.defaultWindowSize)
            window.center()
        }
    }

    private func updateTitle(_ title: String) {
        window?.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func show(pane: SettingsPane) {
        splitViewController?.navigateTo(pane)
        show()
    }

    private func updateToolbarButtons() {
        window?.toolbar?.items.forEach { item in
            if item.itemIdentifier == Self.backForwardIdentifier,
               let segmented = item.view as? NSSegmentedControl {
                segmented.setEnabled(navigationHistory.canGoBack, forSegment: 0)
                segmented.setEnabled(navigationHistory.canGoForward, forSegment: 1)
            }
        }
    }

    private func navigateHistory(selectedSegment: Int) {
        if selectedSegment == 0 {
            guard let pane = navigationHistory.goBack() else { return }
            splitViewController?.navigateTo(pane)
            updateTitle(pane.rawValue)
            updateToolbarButtons()
            return
        }

        guard let pane = navigationHistory.goForward() else { return }
        splitViewController?.navigateTo(pane)
        updateTitle(pane.rawValue)
        updateToolbarButtons()
    }

    @objc private func backForwardAction(_ sender: NSSegmentedControl) {
        navigateHistory(selectedSegment: sender.selectedSegment)
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, Self.backForwardIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, Self.backForwardIdentifier, .flexibleSpace]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.backForwardIdentifier else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.isNavigational = true

        let segmented = NSSegmentedControl()
        segmented.segmentStyle = .automatic
        segmented.trackingMode = .momentary
        segmented.segmentCount = 2
        segmented.controlSize = .small

        segmented.setImage(
            NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .medium)),
            forSegment: 0
        )
        segmented.setImage(
            NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .medium)),
            forSegment: 1
        )

        segmented.setWidth(24, forSegment: 0)
        segmented.setWidth(24, forSegment: 1)
        segmented.setEnabled(false, forSegment: 0)
        segmented.setEnabled(false, forSegment: 1)
        segmented.target = self
        segmented.action = #selector(backForwardAction(_:))

        item.view = segmented
        return item
    }
}

// MARK: - Navigation History

@MainActor
final class SettingsNavigationHistory {
    private var history: [SettingsPane] = []
    private var currentIndex: Int = -1

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < history.count - 1 }

    func push(_ pane: SettingsPane) {
        if currentIndex >= 0 && currentIndex < history.count && history[currentIndex] == pane {
            return
        }

        if currentIndex < history.count - 1 {
            history.removeLast(history.count - currentIndex - 1)
        }

        history.append(pane)
        currentIndex = history.count - 1
    }

    func goBack() -> SettingsPane? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return history[currentIndex]
    }

    func goForward() -> SettingsPane? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return history[currentIndex]
    }
}

// MARK: - Split View Controller

final class SettingsSplitViewController: NSSplitViewController {
    private let sidebarViewModel: SettingsSidebarViewModel
    private let detailHostingController: NSHostingController<SettingsDetailView>

    init(onPaneChange: @escaping (SettingsPane, Bool) -> Void) {
        let sidebarViewModel = SettingsSidebarViewModel()
        self.sidebarViewModel = sidebarViewModel
        detailHostingController = NSHostingController(
            rootView: SettingsDetailView(viewModel: sidebarViewModel)
        )
        super.init(nibName: nil, bundle: nil)
        sidebarViewModel.setOnPaneChange { pane, isUserSelection in
            onPaneChange(pane, isUserSelection)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: NSHostingController(
            rootView: SettingsSidebarView(viewModel: sidebarViewModel)
        ))
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 180
        addSplitViewItem(sidebarItem)

        let detailItem = NSSplitViewItem(viewController: detailHostingController)
        detailItem.minimumThickness = 400
        addSplitViewItem(detailItem)
    }

    func navigateTo(_ pane: SettingsPane) {
        sidebarViewModel.selectPane(pane, isUserSelection: false)
    }
}

// MARK: - View Model

@Observable
@MainActor
final class SettingsSidebarViewModel {
    var selectedPane: SettingsPane = .general

    private var onPaneChange: ((SettingsPane, Bool) -> Void)?
    private var isUserSelection = true

    init(onPaneChange: ((SettingsPane, Bool) -> Void)? = nil) {
        self.onPaneChange = onPaneChange
    }

    func setOnPaneChange(_ onPaneChange: ((SettingsPane, Bool) -> Void)?) {
        self.onPaneChange = onPaneChange
    }

    func selectPane(_ pane: SettingsPane, isUserSelection: Bool) {
        self.isUserSelection = isUserSelection
        selectedPane = pane
        onPaneChange?(pane, isUserSelection)
        self.isUserSelection = true
    }
}

// MARK: - Settings Pane

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case keymap = "Keymap"
    case ai = "AI"
    case about = "About"

    // MARK: - Future Settings Panes (uncomment to enable)
    // These panes have UI implemented but are disabled for initial release.
    // To enable: uncomment the case, add to icon switch, and uncomment in SettingsDetailView
    //
    // case tabs = "Tabs"           // TabsSettingsView.swift - Tab behavior, restoration, display
    // case fontIcons = "Font & Icons"  // FontIconsSettingsView.swift - Editor fonts, icons, themes
    // case security = "Security"   // SecuritySettingsView.swift - Credentials, SSL, privacy

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gear"
        case .keymap: "keyboard"
        case .ai: "sparkles"
        case .about: "info.circle"
        }
    }
}

// MARK: - Sidebar View

struct SettingsSidebarView: View {
    @Bindable var viewModel: SettingsSidebarViewModel

    var body: some View {
        List(SettingsPane.allCases, selection: Binding(
            get: { viewModel.selectedPane },
            set: { newValue in
                if let pane = newValue {
                    viewModel.selectPane(pane, isUserSelection: true)
                }
            }
        )) { pane in
            Label(pane.rawValue, systemImage: pane.icon)
                .tag(pane)
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Detail View

struct SettingsDetailView: View {
    var viewModel: SettingsSidebarViewModel

    var body: some View {
        switch viewModel.selectedPane {
        case .general:
            GeneralSettingsView()
        case .keymap:
            KeymapSettingsView()
        case .ai:
            AISettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}
