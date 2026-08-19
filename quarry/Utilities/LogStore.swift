//
//  LogStore.swift
//  Quarry
//

import Foundation
import Observation
import os

struct LogEntry: Identifiable, Sendable {
    let id: UInt64
    let timestamp: Date
    let message: String
}

private struct PendingLogItem: Sendable {
    let timestamp: Date
    let message: String
}

private struct LogStaging: Sendable {
    var items: [PendingLogItem] = []
    var drainScheduled = false
}

/// In-memory ring buffer of app log messages, fed by `debugLog`.
///
/// `record(_:)` is safe to call from any thread/actor and never blocks the
/// caller on the main actor: messages are appended to an unfair-lock-guarded
/// staging buffer, and a single coalesced hop to the main actor drains them
/// into the observable `entries` array.
@MainActor @Observable
final class LogStore {
    static let shared = LogStore()
    static let capacity = 5000

    private(set) var entries: [LogEntry] = []

    private nonisolated static let staging = OSAllocatedUnfairLock(initialState: LogStaging())
    private var nextID: UInt64 = 0

    private init() {}

    /// Thread-safe, cheap entry point. Timestamps at call time.
    nonisolated static func record(_ message: String) {
        let shouldScheduleDrain = staging.withLock { state in
            state.items.append(PendingLogItem(timestamp: Date(), message: message))
            if state.drainScheduled { return false }
            state.drainScheduled = true
            return true
        }
        guard shouldScheduleDrain else { return }
        Task { @MainActor in
            shared.drain()
        }
    }

    private func drain() {
        let batch = Self.staging.withLock { state in
            state.drainScheduled = false
            let items = state.items
            state.items.removeAll(keepingCapacity: true)
            return items
        }
        guard !batch.isEmpty else { return }

        for item in batch {
            nextID &+= 1
            entries.append(LogEntry(id: nextID, timestamp: item.timestamp, message: item.message))
        }
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }

    func exportText(_ selection: [LogEntry]? = nil) -> String {
        let list = selection ?? entries
        return list
            .map { "\(Self.exportTimestampFormatter.string(from: $0.timestamp)) \($0.message)" }
            .joined(separator: "\n")
    }

    static let displayTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static let exportTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}
