//
//  AppDelegate.swift
//  Quarry
//
//  Created by Fauzaan on 1/3/25.
//
import Cocoa
import OSLog
import SwiftData
import SwiftUI

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var systemAppearanceObservation: NSKeyValueObservation?
    private var menuBarController: MenuBarController?
    private var windowShortcutMonitor: Any?
    private weak var lastUserActiveWindow: NSWindow?
    private var keyWindowObserver: NSObjectProtocol?
    private var externalSQLiteConnectionSheetController: NSWindowController?

    static func appearance(for value: Int) -> NSAppearance? {
        switch value {
        case 1: NSAppearance(named: .aqua)
        case 2: NSAppearance(named: .darkAqua)
        default: nil
        }
    }

    static func userPreferredAppearance() -> NSAppearance? {
        let value = UserDefaults.standard.object(forKey: "appearance") as? Int ?? 0
        return appearance(for: value)
    }

    lazy var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Connection.self,
            QueryHistoryEntry.self,
            Notebook.self,
            NotebookBlock.self,
            AgentChat.self,
            AgentMessage.self,
            RecentTableEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: SandboxStoreMigrator.destinationStoreURL
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            try SandboxStoreMigrator.migrateIfNeeded()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Quarry could not migrate your existing data"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        NSApp.appearance = Self.userPreferredAppearance()

        // Ensure the app has a basic main menu and is frontmost
        if NSApp.mainMenu == nil {
            let mainMenu = NSMenu()
            let appMenuItem = NSMenuItem()
            mainMenu.addItem(appMenuItem)
            let appMenu = NSMenu()
            appMenu.addItem(
                withTitle: "Quit Quarry", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
            appMenuItem.submenu = appMenu
            NSApp.mainMenu = mainMenu
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        windowShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            self.handleWindowShortcut(event) ? nil : event
        }

        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in
                self?.lastUserActiveWindow = window
            }
        }

        if #available(macOS 26, *) {
            configureMenuItemImages()
        }

        systemAppearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in
                NotificationCenter.default.post(name: .appAppearanceDidChange, object: nil)
            }
        }

        menuBarController = MenuBarController(modelContainer: sharedModelContainer)

        // Create the main window using WindowController (which loads TerminalTabsTitlebarVentura.xib)
        let windowController = WindowController(tabType: .home)
        windowController.showWindow(nil)

        // Let the WindowController handle sizing through its configureWindow method
        // It already has logic for saved frames and constraints
        if let window = windowController.window {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // Ensure toolbar items are enabled
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        return true
    }

    // Also validate via NSUserInterfaceValidations to be safe
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        return true
    }

    // Handle the toggleSidebar: action from menu
    @objc func toggleSidebar(_ sender: Any?) {
        if let window = NSApp.keyWindow,
            let windowController = WindowController.getController(for: window)
        {
            windowController.toggleSidebarNatively(sender)
        }
    }

    // Handle the toggleRightSidebar: action from menu
    @objc func toggleRightSidebar(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleRightSidebar, object: nil)
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        true
    }

    // Show custom About window
    @objc func showAboutPanel(_ sender: Any?) {
        let aboutWindowController = AboutWindowController()
        aboutWindowController.window?.center()
        aboutWindowController.showWindow(nil)
    }

    // Show Settings window
    @IBAction func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    // Show Logs window
    @IBAction func showLogs(_ sender: Any?) {
        LogWindowController.shared.show()
    }

    // Import connections from TablePlus
    @IBAction func importFromTablePlus(_ sender: Any?) {
        TablePlusImportWindowController.shared.show(modelContainer: sharedModelContainer)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if let windowShortcutMonitor {
            NSEvent.removeMonitor(windowShortcutMonitor)
            self.windowShortcutMonitor = nil
        }
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Clicking the Dock icon with no main window open brings Quarry back instead
    // of leaving the app running with nothing on screen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if WindowController.hasVisibleManagedWindow {
            bringAppToFront()
        } else {
            _ = WindowController.showHome()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        bringAppToFront()
        for url in urls {
            if url.isFileURL {
                handleOpenedFile(url)
            } else {
                handleURLCallback(url)
            }
        }
    }

    private func bringAppToFront() {
        NSApp.activate(ignoringOtherApps: true)
        let target = NSApp.keyWindow
            ?? lastUserActiveWindow.flatMap { $0.isVisible ? $0 : nil }
            ?? NSApp.orderedWindows.first(where: { $0.isVisible && $0.canBecomeKey })
            ?? NSApp.mainWindow
        target?.makeKeyAndOrderFront(nil)
    }

    private func handleURLCallback(_ url: URL) {
        // OAuth callbacks require a code parameter
        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let code = queryItems.first(where: { $0.name == "code" })?.value
        else {
            return
        }

        NotificationCenter.default.post(
            name: .convexOAuthCallback,
            object: nil,
            userInfo: ["code": code]
        )
    }

    private func handleOpenedFile(_ url: URL) {
        guard isSupportedSQLiteDatabaseURL(url) else { return }

        let normalizedPath = normalizedSQLitePath(url.path)
        if let connection = existingSQLiteConnection(for: normalizedPath) {
            openSQLiteConnection(connection)
            return
        }

        askToCreateSQLiteConnection(for: url)
    }

    private func isSupportedSQLiteDatabaseURL(_ url: URL) -> Bool {
        let supportedExtensions = ["db", "sqlite", "sqlite3"]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func existingSQLiteConnection(for normalizedPath: String) -> Connection? {
        let descriptor = FetchDescriptor<Connection>()
        let connections = (try? sharedModelContainer.mainContext.fetch(descriptor)) ?? []
        return connections.first { connection in
            guard connection.databaseType == .sqlite,
                  let storedPath = sqlitePath(from: connection.url) else {
                return false
            }
            return normalizedSQLitePath(storedPath) == normalizedPath
        }
    }

    private func sqlitePath(from connectionString: String?) -> String? {
        guard let connectionString, !connectionString.isEmpty else { return nil }

        if let (_, path) = BookmarkManager.shared.decodeBookmark(connectionString) {
            return path
        }

        if connectionString.hasPrefix("sqlite://") {
            let path = String(connectionString.dropFirst(9))
            return path.isEmpty ? nil : path
        }

        if connectionString.hasPrefix("file:") {
            return String(connectionString.dropFirst(5))
        }

        return connectionString
    }

    private func normalizedSQLitePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func askToCreateSQLiteConnection(for url: URL) {
        let controller = WindowController.showHome()
        guard let parentWindow = controller.window ?? NSApp.keyWindow else { return }

        let alert = NSAlert()
        alert.messageText = "Create SQLite Connection?"
        alert.informativeText = "\(url.lastPathComponent) is not in your Quarry connections yet. Create a new SQLite connection for this file?"
        alert.addButton(withTitle: "Create Connection")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: parentWindow) { [weak self, weak parentWindow] response in
            Task { @MainActor in
                guard response == .alertFirstButtonReturn,
                      let parentWindow else {
                    return
                }
                self?.presentCreateSQLiteConnectionSheet(for: url, parentWindow: parentWindow)
            }
        }
    }

    private func presentCreateSQLiteConnectionSheet(for url: URL, parentWindow: NSWindow) {
        var sheetWindow: NSWindow?
        let form = CreateConnectionForm(
            initialSQLiteFileURL: url,
            onSavedConnection: { [weak self] connection, _ in
                self?.openSQLiteConnection(connection)
            },
            onClose: { [weak parentWindow] in
                guard let sheetWindow else { return }
                parentWindow?.endSheet(sheetWindow)
            }
        )
        .frame(width: 480, height: 640)
        .modelContainer(sharedModelContainer)

        let hostingController = NSHostingController(rootView: form)
        let window = NSWindow(contentViewController: hostingController)
        sheetWindow = window
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 480, height: 640))
        window.isReleasedWhenClosed = false

        externalSQLiteConnectionSheetController = NSWindowController(window: window)
        parentWindow.beginSheet(window) { [weak self] _ in
            Task { @MainActor in
                self?.externalSQLiteConnectionSheetController = nil
            }
        }
    }

    private func openSQLiteConnection(_ connection: Connection) {
        connection.lastOpenedAt = Date()

        if let existingInstance = ConnectionService.shared.getExistingInstance(for: connection) {
            ConnectionService.shared.activeConnectionInstanceId = existingInstance.id
            WindowController.switchToTab(.connection(existingInstance.id))
            try? sharedModelContainer.mainContext.save()
            return
        }

        let instanceId = ConnectionService.shared.createNewConnectionInstance(for: connection)
        guard let connectionInstance = ConnectionService.shared.getInstance(instanceId) else { return }

        WindowController.newTab(
            tabType: .connection(instanceId),
            connectionInstance: connectionInstance
        )
        try? sharedModelContainer.mainContext.save()
    }

    @available(macOS 26, *)
    private func configureMenuItemImages() {
        guard let mainMenu = NSApp.mainMenu else { return }

        let symbolsByTitle: [String: String] = [
            "Settings…": "gearshape.fill",
            "Import from TablePlus…": "square.and.arrow.down",
            "Toggle Row Details": "sidebar.right",
        ]

        applyMenuItemImages(to: mainMenu, using: symbolsByTitle)
    }

    @available(macOS 26, *)
    private func applyMenuItemImages(to menu: NSMenu, using symbolsByTitle: [String: String]) {
        for item in menu.items {
            if let symbolName = symbolsByTitle[item.title] {
                item.image = NSImage(
                    systemSymbolName: symbolName, accessibilityDescription: item.title)
            }
            if let submenu = item.submenu {
                applyMenuItemImages(to: submenu, using: symbolsByTitle)
            }
        }
    }

    private func handleWindowShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == [.command, .option],
              let key = event.charactersIgnoringModifiers,
              let digit = Int(key),
              (1...9).contains(digit) else {
            return false
        }

        return WindowController.activateWindow(at: digit - 1)
    }
}
