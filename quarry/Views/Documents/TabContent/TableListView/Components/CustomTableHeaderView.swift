//
//  CustomTableHeaderView.swift
//  Quarry
//
//  Created by Assistant on 7/5/25.
//

import AppKit

@MainActor
class CustomTableHeaderView: NSTableHeaderView {
    private var trackingArea: NSTrackingArea?
    private var currentHoveredColumn: Int = -1

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupTrackingArea()
    }

    private func setupTrackingArea() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect]
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )

        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateTooltip(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        Task { @MainActor in
            TooltipCoordinator.shared.hideTooltip()
        }
        currentHoveredColumn = -1
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateTooltip(with: event)
    }

    private func updateTooltip(with event: NSEvent) {
        guard let tableView = tableView else {
            Task { @MainActor in
                TooltipCoordinator.shared.hideTooltip()
            }
            return
        }

        let locationInView = convert(event.locationInWindow, from: nil)
        let columnIndex = column(at: locationInView)

        if columnIndex >= 0 && columnIndex < tableView.numberOfColumns {
            let column = tableView.tableColumns[columnIndex]
            if let headerCell = column.headerCell as? CustomTableHeaderCell {
                let headerRect = headerRect(ofColumn: columnIndex)

                if let fieldType = headerCell.getFieldType() {
                    let iconX = headerRect.minX + 8
                    let iconSize: CGFloat = 20

                    let iconRect = NSRect(
                        x: iconX,
                        y: headerRect.minY,
                        width: iconSize,
                        height: headerRect.height
                    )

                    if iconRect.contains(locationInView) {
                        if currentHoveredColumn != columnIndex {
                            let iconCenterX = iconRect.midX
                            let tooltipY = self.bounds.maxY

                            let tooltipPoint = NSPoint(
                                x: iconCenterX,
                                y: tooltipY
                            )
                            Task { @MainActor in
                                TooltipCoordinator.shared.showTooltipImmediately(
                                    text: fieldType,
                                    at: tooltipPoint,
                                    relativeTo: self
                                )
                            }
                            currentHoveredColumn = columnIndex
                        }
                        return
                    }
                }
            }
        }

        Task { @MainActor in
            TooltipCoordinator.shared.hideTooltip()
        }
        currentHoveredColumn = -1
    }
}
