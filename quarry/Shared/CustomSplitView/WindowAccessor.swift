//
//  AppKitSplitView.swift
//  Collection
//
//  Created by Fauzaan on 1/16/25.
//
import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            callback(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            callback(nsView?.window)
        }
    }
}

struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {
        nsView.onChange = onChange
    }

    final class ReportingView: NSView {
        var onChange: ((NSWindow?) -> Void)?
        private weak var lastWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportIfNeeded()
        }

        func reportIfNeeded() {
            guard lastWindow !== window else { return }
            lastWindow = window
            onChange?(window)
        }
    }
}
