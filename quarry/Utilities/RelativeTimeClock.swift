//
//  RelativeTimeClock.swift
//  Quarry
//

import AppKit
import Foundation
import Observation

/// Shared ticking clock for relative timestamps ("2 minutes ago").
///
/// Views that format a date against `Date()` only re-render when some other
/// piece of state changes, so a row can sit at "a moment ago" for hours. Reading
/// `RelativeTimeClock.shared.now` inside `body` ties the view to this clock
/// instead: it ticks every 30s and on app activation, so the text stays honest.
@MainActor @Observable
final class RelativeTimeClock {
    static let shared = RelativeTimeClock()

    private(set) var now = Date()

    @ObservationIgnored private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in RelativeTimeClock.shared.tick() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in RelativeTimeClock.shared.tick() }
        }
    }

    private func tick() {
        now = Date()
    }
}
