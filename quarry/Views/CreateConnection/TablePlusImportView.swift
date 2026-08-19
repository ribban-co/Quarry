import SwiftUI
import SwiftData
import AppKit

// MARK: - Window Controller

@MainActor
final class TablePlusImportWindowController {
    static let shared = TablePlusImportWindowController()
    private var windowController: NSWindowController?

    func show(modelContainer: ModelContainer) {
        guard TablePlusImportService.isTablePlusDataAvailable else {
            let alert = NSAlert()
            alert.messageText = "No TablePlus Data Found"
            alert.informativeText = "Quarry couldn't find any TablePlus connections on this Mac."
            alert.runModal()
            return
        }

        if let windowController {
            windowController.window?.makeKeyAndOrderFront(nil)
            return
        }

        let view = TablePlusImportView(onClose: { [weak self] in
            self?.windowController?.close()
        })
        .frame(width: 480, height: 520)
        .modelContainer(modelContainer)

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Import from TablePlus"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 480, height: 520))
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.windowController = nil
            }
        }

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - View

struct TablePlusImportView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var existingConnections: [Connection]

    @State private var candidates: [TablePlusImportCandidate] = []
    @State private var selectedIds: Set<String> = []
    @State private var loadError: String?
    @State private var didImportCount: Int?

    private func isDuplicate(_ candidate: TablePlusImportCandidate) -> Bool {
        guard let databaseType = candidate.databaseType else { return false }
        return existingConnections.contains { existing in
            existing.databaseType == databaseType
                && (existing.hostname ?? "") == candidate.host
                && (existing.port ?? "") == candidate.port
                && (existing.defaultDatabase ?? "") == candidate.database
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let loadError {
                ContentUnavailableView(
                    "Couldn't Read TablePlus Data",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .frame(maxHeight: .infinity)
            } else if candidates.isEmpty {
                ContentUnavailableView(
                    "No Connections Found",
                    systemImage: "tray",
                    description: Text("TablePlus has no saved connections to import.")
                )
                .frame(maxHeight: .infinity)
            } else {
                candidateList
            }

            Divider()

            footer
        }
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Import from TablePlus")
                .font(.body)
                .bold()
            Text("Passwords aren't imported — Quarry will ask when you first connect.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var candidateList: some View {
        List {
            ForEach(candidates) { candidate in
                candidateRow(candidate)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func candidateRow(_ candidate: TablePlusImportCandidate) -> some View {
        let duplicate = isDuplicate(candidate)
        let selectable = candidate.isSupported

        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selectedIds.contains(candidate.id) },
                set: { isOn in
                    if isOn {
                        selectedIds.insert(candidate.id)
                    } else {
                        selectedIds.remove(candidate.id)
                    }
                }
            ))
            .labelsHidden()
            .disabled(!selectable)

            if let databaseType = candidate.databaseType {
                Image(databaseType.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "cylinder.split.1x2")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(candidate.name)
                        .fontWeight(.medium)
                    if let groupName = candidate.groupName {
                        Text(groupName)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(candidate.unsupportedReason ?? candidate.displayDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if duplicate {
                Text("Already added")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(selectable ? 1 : 0.5)
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            if let didImportCount {
                Label("Imported \(didImportCount) connection\(didImportCount == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }

            Spacer()

            Button("Cancel", action: onClose)
                .keyboardShortcut(.cancelAction)

            Button(importButtonTitle, action: importSelected)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIds.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var importButtonTitle: String {
        selectedIds.isEmpty ? "Import" : "Import \(selectedIds.count)"
    }

    private func load() {
        do {
            candidates = try TablePlusImportService.loadCandidates()
            selectedIds = Set(
                candidates
                    .filter { $0.isSupported && !isDuplicate($0) }
                    .map(\.id)
            )
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func importSelected() {
        let toImport = candidates.filter { selectedIds.contains($0.id) }
        var imported = 0
        for candidate in toImport {
            guard let connection = TablePlusImportService.makeConnection(from: candidate) else { continue }
            modelContext.insert(connection)
            imported += 1
        }
        try? modelContext.save()
        didImportCount = imported

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            onClose()
        }
    }
}
