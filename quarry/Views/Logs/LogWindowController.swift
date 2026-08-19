//
//  LogWindowController.swift
//  Quarry
//

import Cocoa
import SwiftUI

@MainActor
final class LogWindowController: NSWindowController {
    static let shared = LogWindowController()

    private static let defaultWindowSize = NSSize(width: 720, height: 480)
    private static let minimumWindowSize = NSSize(width: 480, height: 300)
    private static let windowFrameAutosaveName = "LogWindowFrame"

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Logs"
        window.contentMinSize = Self.minimumWindowSize
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let restoredFrame = window.setFrameUsingName(Self.windowFrameAutosaveName)
        window.setFrameAutosaveName(Self.windowFrameAutosaveName)
        if !restoredFrame {
            window.setContentSize(Self.defaultWindowSize)
            window.center()
        }

        window.contentViewController = NSHostingController(rootView: LogViewerView())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
