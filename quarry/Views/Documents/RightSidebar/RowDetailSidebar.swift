//
//  RowDetailSidebar.swift
//  Quarry
//
//  Created by Claude on 1/21/26.
//

import SwiftUI
import AppKit
import QuartzCore

struct RowDetailSidebar: View {
    @Environment(ConnectionInstance.self) private var instance
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(\.colorScheme) var colorScheme

    @State private var isScrolled = false
    @State private var isEditing = false
    @State private var editedValues: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String?

    private let minWidth: CGFloat = 200
    private let maxWidth: CGFloat = 500

    var body: some View {
        @Bindable var appViewModel = appViewModel

        HStack(spacing: 0) {
            ResizeDivider(width: $appViewModel.rightSidebarWidth, minWidth: minWidth, maxWidth: maxWidth)
                .frame(width: 6)

            // Main content
            VStack(alignment: .leading, spacing: 0) {
                if let rowData = instance.selectedTab?.selectedRowData, !rowData.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        // Sticky header
                        HStack {
                            Text("FIELDS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if isScrolled {
                                Divider()
                            }
                        }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                RowFieldsSection(
                                    rowData: rowData,
                                    columnOrder: instance.selectedTab?.selectedColumnOrder,
                                    isEditing: isEditing,
                                    editedValues: $editedValues
                                )
                                RowActionsMenu(
                                    isEditing: $isEditing,
                                    editedValues: $editedValues,
                                    isSaving: $isSaving,
                                    saveError: $saveError
                                )
                            }
                            .padding(.vertical, 8)
                        }
                        .onScrollGeometryChange(for: Bool.self) { geo in
                            geo.contentOffset.y > 1
                        } action: { _, isScrolled in
                            self.isScrolled = isScrolled
                        }
                    }
                    .transition(.opacity)
                } else {
                    // Empty state
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "rectangle.and.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("Select a row to view details")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: instance.selectedTab?.selectedRowData == nil)
        }
        .frame(width: appViewModel.rightSidebarWidth)
    }
}

// MARK: - Row Fields Section

private struct RowFieldsSection: View {
    let rowData: [String: QueryRowInfo]
    let columnOrder: [String]?
    let isEditing: Bool
    @Binding var editedValues: [String: String]

    private var orderedKeys: [String] {
        if let order = columnOrder {
            return order.filter { rowData.keys.contains($0) }
        }
        return Array(rowData.keys)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(orderedKeys, id: \.self) { key in
                if let info = rowData[key] {
                    RowDetailField(
                        columnName: key,
                        rowInfo: info,
                        isEditing: isEditing,
                        editedValue: Binding(
                            get: { editedValues[key] ?? displayValue(for: info) },
                            set: { editedValues[key] = $0 }
                        )
                    )
                }
            }
        }
    }

    private func displayValue(for info: QueryRowInfo) -> String {
        guard let value = info.value else {
            return "NULL"
        }

        switch value {
        case .string(let stringValue), .decimalString(let stringValue), .objectID(let stringValue):
            return stringValue.isEmpty ? "" : stringValue
        case .int(let intValue):
            return String(intValue)
        case .int64(let intValue):
            return String(intValue)
        case .double(let doubleValue):
            return doubleValue.formatted()
        case .bool(let boolValue):
            return boolValue ? "true" : "false"
        case .date(let dateValue):
            return dateValue.formatted(date: .abbreviated, time: .standard)
        case .array, .object:
            return formatJSON(value.anyValue ?? NSNull())
        case .data(let dataValue):
            return dataValue.base64EncodedString()
        case .uuid(let uuidValue):
            return uuidValue.uuidString
        case .null:
            return "NULL"
        }
    }

    private func formatJSON(_ value: Any) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? String(describing: value)
        } catch {
            return String(describing: value)
        }
    }
}

// MARK: - Row Actions Menu

private struct RowActionsMenu: View {
    @Environment(ConnectionInstance.self) private var instance
    @Binding var isEditing: Bool
    @Binding var editedValues: [String: String]
    @Binding var isSaving: Bool
    @Binding var saveError: String?
    @State private var isExpanded = true
    @State private var isCopied = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("ACTIONS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Actions
            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    if isEditing {
                        ActionMenuItem(
                            title: isSaving ? "Saving..." : "Save Changes",
                            isPrimary: true,
                            isDisabled: isSaving
                        ) { saveChanges() }

                        ActionMenuItem(
                            title: "Cancel",
                            isDisabled: isSaving
                        ) { cancelEditing() }
                    } else if isConfirmingDelete {
                        ActionMenuItem(
                            title: isDeleting ? "Deleting..." : "Confirm Delete",
                            isDestructive: true,
                            isPrimary: true,
                            isDisabled: isDeleting
                        ) { executeDelete() }

                        ActionMenuItem(
                            title: "Cancel",
                            isDisabled: isDeleting
                        ) { cancelDelete() }
                    } else {
                        ActionMenuItem(
                            icon: "pencil.line",
                            title: "Edit"
                        ) { startEditing() }

                        ActionMenuItem(
                            icon: isCopied ? "checkmark" : "doc.plaintext",
                            title: isCopied ? "Copied!" : "Copy as JSON"
                        ) { copyRowAsJSON() }

                        ActionMenuItem(
                            icon: "trash",
                            title: "Delete",
                            isDestructive: true
                        ) { confirmDelete() }
                    }

                    if let error = saveError ?? deleteError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .animation(.easeInOut(duration: 0.2), value: isConfirmingDelete)
    }

    private func startEditing() {
        guard let rowData = instance.selectedTab?.selectedRowData else { return }

        editedValues = [:]
        for (key, info) in rowData {
            editedValues[key] = displayValue(for: info)
        }
        saveError = nil
        isEditing = true
    }

    private func cancelEditing() {
        editedValues = [:]
        saveError = nil
        isEditing = false
    }

    private func saveChanges() {
        guard let tab = instance.selectedTab,
              let rowData = tab.selectedRowData,
              let rawRowData = tab.selectedRawRowData,
              let columnOrder = tab.selectedColumnOrder else { return }

        guard let id = selectedRowRecordID(from: rawRowData, columnOrder: columnOrder) else {
            saveError = "Cannot find row identifier"
            return
        }

        var updateData: [String: Any] = [:]
        for (key, stringValue) in editedValues {
            if let originalInfo = rowData[key] {
                let originalValue = displayValue(for: originalInfo)
                if stringValue != originalValue {
                    updateData[key] = convertToOriginalType(stringValue, dataType: originalInfo.dataType)
                }
            }
        }

        guard !updateData.isEmpty else {
            isEditing = false
            return
        }

        isSaving = true
        saveError = nil

        Task {
            do {
                try await instance.databaseService.updateDocument(
                    in: tab.name,
                    databaseSchema: tab.databaseSchema,
                    id: id,
                    data: updateData
                )

                await MainActor.run {
                    isSaving = false
                    isEditing = false
                    editedValues = [:]

                    NotificationCenter.default.post(
                        name: .tableRefresh,
                        object: nil,
                        userInfo: ["tableName": tab.name]
                    )
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }

    private func convertToOriginalType(_ value: String, dataType: String) -> Any {
        let type = dataType.lowercased()

        if value == "NULL" || value.isEmpty {
            return NSNull()
        }

        if type.contains("int") || type.contains("serial") {
            return Int(value) ?? value
        } else if type.contains("double") || type.contains("float") || type.contains("decimal") || type.contains("numeric") || type.contains("real") {
            return Double(value) ?? value
        } else if type.contains("bool") {
            return value.lowercased() == "true"
        }

        return value
    }

    private func displayValue(for info: QueryRowInfo) -> String {
        guard let value = info.value else {
            return "NULL"
        }

        switch value {
        case .string(let value), .decimalString(let value), .objectID(let value):
            return value
        case .int(let value):
            return String(value)
        case .int64(let value):
            return String(value)
        case .double(let value):
            return value.formatted()
        case .bool(let value):
            return value ? "true" : "false"
        case .date(let value):
            return value.formatted(date: .abbreviated, time: .standard)
        case .array, .object:
            return formatJSON(value.anyValue ?? NSNull())
        case .data(let value):
            return value.base64EncodedString()
        case .uuid(let value):
            return value.uuidString
        case .null:
            return "NULL"
        }
    }

    private func formatJSON(_ value: Any) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? String(describing: value)
        } catch {
            return String(describing: value)
        }
    }

    private func copyRowAsJSON() {
        guard let rowData = instance.selectedTab?.selectedRowData else { return }

        var jsonDict: [String: Any] = [:]
        for (key, info) in rowData {
            jsonDict[key] = info.value?.anyValue ?? NSNull()
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(jsonString, forType: .string)

                isCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    await MainActor.run {
                        isCopied = false
                    }
                }
            }
        } catch {
            print("Failed to serialize JSON: \(error)")
        }
    }

    private func confirmDelete() {
        deleteError = nil
        isConfirmingDelete = true
    }

    private func cancelDelete() {
        deleteError = nil
        isConfirmingDelete = false
    }

    private func executeDelete() {
        guard let tab = instance.selectedTab,
              let rawRowData = tab.selectedRawRowData,
              let columnOrder = tab.selectedColumnOrder else { return }

        guard let id = selectedRowRecordID(from: rawRowData, columnOrder: columnOrder) else {
            deleteError = "Cannot find row identifier"
            return
        }

        isDeleting = true
        deleteError = nil

        Task {
            do {
                try await instance.databaseService.deleteDocument(
                    in: tab.name,
                    databaseSchema: tab.databaseSchema,
                    id: id
                )

                await MainActor.run {
                    isDeleting = false
                    isConfirmingDelete = false

                    // Clear selection
                    instance.selectedTab?.selectedRowIndex = nil
                    instance.selectedTab?.selectedRowData = nil
                    instance.selectedTab?.selectedRawRowData = nil

                    // Refresh the table
                    NotificationCenter.default.post(
                        name: .tableRefresh,
                        object: nil,
                        userInfo: ["tableName": tab.name]
                    )
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = error.localizedDescription
                }
            }
        }
    }

    private func selectedRowRecordID(from rawRowData: DatabaseRawRow, columnOrder: [String]) -> DatabaseRecordID? {
        if let value = rawRowData["_id"] ?? nil {
            return DatabaseRecordID(columnName: "_id", value: value)
        }
        if let value = rawRowData["id"] ?? nil {
            return DatabaseRecordID(columnName: "id", value: value)
        }
        guard let firstColumn = columnOrder.first,
              let value = rawRowData[firstColumn] ?? nil else {
            return nil
        }
        return DatabaseRecordID(columnName: firstColumn, value: value)
    }
}

private struct ActionMenuItem: View {
    static let primaryColor = Color.primaryButton

    var icon: String? = nil
    let title: String
    var isDestructive: Bool = false
    var isPrimary: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    private var foregroundColor: Color {
        if isDestructive && isPrimary {
            return isDisabled ? .secondary : .white
        } else if isPrimary {
            return isDisabled ? .secondary : Color(.textBackgroundColor)
        } else if isDisabled {
            return .secondary
        } else if isDestructive {
            return .red
        } else {
            return .primary
        }
    }

    private var backgroundColor: Color {
        if isDestructive && isPrimary {
            let baseColor = isDisabled ? Color.white.opacity(0.1) : Color.red
            return isHovering ? baseColor.opacity(0.85) : baseColor
        } else if isPrimary {
            let baseColor = isDisabled ? Color.white.opacity(0.1) : Self.primaryColor
            return isHovering ? baseColor.opacity(0.85) : baseColor
        } else if isDestructive {
            return isHovering ? Color.red.opacity(0.15) : Color.red.opacity(0.10)
        } else {
            return isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)
        }
    }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(foregroundColor)
                        .frame(width: 16, height: 16)
                }

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(foregroundColor)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .padding(.horizontal, 12)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - AppKit-based Resize Divider

private struct ResizeDivider: NSViewRepresentable {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    func makeNSView(context: Context) -> ResizeDividerView {
        let view = ResizeDividerView()
        view.onDrag = { delta in
            let newWidth = max(minWidth, min(maxWidth, width - delta))
            // Update without animation for smooth dragging
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                width = newWidth
            }
        }
        return view
    }

    func updateNSView(_ nsView: ResizeDividerView, context: Context) {
        nsView.onDrag = { delta in
            let newWidth = max(minWidth, min(maxWidth, width - delta))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                width = newWidth
            }
        }
    }
}

private class ResizeDividerView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isDragging = false
    private var isHovering = false
    private var lastX: CGFloat = 0

    // Display link for smooth, vsync'd updates
    private var displayLink: CADisplayLink?
    private var pendingDelta: CGFloat = 0
    private let deltaLock = NSLock()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupDisplayLink()
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func setupDisplayLink() {
        guard displayLink == nil, let window = window else { return }
        displayLink = window.displayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.isPaused = true
        displayLink?.add(to: .main, forMode: .common)
    }

    private func startDisplayLink() {
        displayLink?.isPaused = false
    }

    private func stopDisplayLink() {
        displayLink?.isPaused = true
    }

    @objc private func displayLinkFired() {
        deltaLock.lock()
        let delta = pendingDelta
        pendingDelta = 0
        deltaLock.unlock()

        guard delta != 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        onDrag?(delta)
        CATransaction.commit()
    }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 6, height: NSView.noIntrinsicMetric)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.resizeLeftRight.push()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        if !isDragging {
            NSCursor.pop()
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        lastX = event.locationInWindow.x
        startDisplayLink()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let currentX = event.locationInWindow.x
        let delta = currentX - lastX
        lastX = currentX

        // Accumulate delta for the display link to process
        deltaLock.lock()
        pendingDelta += delta
        deltaLock.unlock()
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        stopDisplayLink()

        // Flush any remaining delta
        deltaLock.lock()
        let remainingDelta = pendingDelta
        pendingDelta = 0
        deltaLock.unlock()

        if remainingDelta != 0 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            onDrag?(remainingDelta)
            CATransaction.commit()
        }

        let point = convert(event.locationInWindow, from: nil)
        if !bounds.contains(point) {
            isHovering = false
            NSCursor.pop()
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw subtle highlight when hovered or dragging
        if isHovering || isDragging {
            let highlightRect = NSRect(
                x: (bounds.width - 2) / 2,
                y: 0,
                width: 2,
                height: bounds.height
            )
            NSColor.separatorColor.setFill()
            highlightRect.fill()
        }
    }
}
