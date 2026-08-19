//
//  CustomTableHeaderCell.swift
//  Quarry
//
//  Created by Fauzaan on 6/4/25.
//

import Foundation
import AppKit
import ObjectiveC

// Associated object keys
nonisolated(unsafe) private var fieldTypeKey: UInt8 = 0
nonisolated(unsafe) private var tooltipTextKey: UInt8 = 0
nonisolated(unsafe) private var isForeignKeyKey: UInt8 = 0
nonisolated(unsafe) private var isActiveSortColumnKey: UInt8 = 0
nonisolated(unsafe) private var sortAscendingKey: UInt8 = 0

class CustomTableHeaderCell: NSTableHeaderCell {
    private var titleLabel: NSTextField?

    // Use associated objects instead of stored properties to avoid copying issues
    private var fieldType: String? {
        get { objc_getAssociatedObject(self, &fieldTypeKey) as? String }
        set { objc_setAssociatedObject(self, &fieldTypeKey, newValue, .OBJC_ASSOCIATION_COPY) }
    }

    private var tooltipText: String? {
        get { objc_getAssociatedObject(self, &tooltipTextKey) as? String }
        set { objc_setAssociatedObject(self, &tooltipTextKey, newValue, .OBJC_ASSOCIATION_COPY) }
    }

    private var isForeignKey: Bool {
        get { (objc_getAssociatedObject(self, &isForeignKeyKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &isForeignKeyKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    // Sort state
    private var isActiveSortColumn: Bool {
        get { (objc_getAssociatedObject(self, &isActiveSortColumnKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &isActiveSortColumnKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    private var sortAscending: Bool {
        get { (objc_getAssociatedObject(self, &sortAscendingKey) as? Bool) ?? true }
        set { objc_setAssociatedObject(self, &sortAscendingKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    // Image cache to prevent over-release
    private var cachedSortIconUp: NSImage?
    private var cachedSortIconDown: NSImage?
    private var cachedTypeIcon: NSImage?
    
    override init(textCell string: String) {
        super.init(textCell: string)
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func configure(title: String, fieldType: String? = nil, tooltip: String? = nil, isForeignKey: Bool = false) {
        titleLabel?.stringValue = title
        // Associated objects handle memory safely
        self.fieldType = fieldType
        self.tooltipText = tooltip
        self.isForeignKey = isForeignKey
    }
    
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawCustomBackground(in: cellFrame)
        
        // Only draw content if this is a valid column header (not empty space)
        if !title.isEmpty {
            let typeIconData = getDataTypeIcon()
            drawTitle(in: cellFrame, sortIcon: getSortIcon(), typeIconData: typeIconData)
        }
    }
    
    private func getSortIcon() -> NSImage? {
        guard isActiveSortColumn else { return nil }

        // Use cached icon if available
        if sortAscending {
            if cachedSortIconUp == nil {
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                    .applying(.init(hierarchicalColor: .secondaryLabelColor))
                cachedSortIconUp = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
            }
            return cachedSortIconUp
        } else {
            if cachedSortIconDown == nil {
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                    .applying(.init(hierarchicalColor: .secondaryLabelColor))
                cachedSortIconDown = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
            }
            return cachedSortIconDown
        }
    }
    
    private func getDataTypeIcon() -> (icon: NSImage, size: CGFloat)? {
        if isForeignKey {
            let customSize: CGFloat = 12
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                .applying(.init(hierarchicalColor: .tertiaryLabelColor))
            guard let icon = NSImage(systemSymbolName: ColumnTypeIcon.foreignKeySymbol, accessibilityDescription: "Foreign Key")?
                .withSymbolConfiguration(config) else { return nil }
            return (icon, customSize)
        }
        guard let fieldType = fieldType else { return nil }

        let (symbolName, customSize) = ColumnTypeIcon.icon(forType: fieldType)

        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            .applying(.init(hierarchicalColor: .tertiaryLabelColor))
        
        guard let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: fieldType)?
            .withSymbolConfiguration(config) else { return nil }
        
        return (icon, customSize)
    }
    
    private func drawTitle(in rect: NSRect, sortIcon: NSImage?, typeIconData: (icon: NSImage, size: CGFloat)?) {
        var textRect = rect.insetBy(dx: 2, dy: 0)
        textRect.size.width -= 20 // Space for sort indicator
        
        // Create text attributes
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = self.alignment
        
        let textColor = NSColor.secondaryLabelColor
        let fontWeight: NSFont.Weight = .regular
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: fontWeight),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
        
        // Draw the text
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        let titleSize = attributedTitle.size()
        
        // Calculate space needed for icons
        var iconSpace: CGFloat = 0
        let currentX: CGFloat = textRect.minX + 6
        
        // Draw type icon
        if let typeIconData = typeIconData {
            let typeIcon = typeIconData.icon
            let targetHeight = typeIconData.size
            let naturalSize = typeIcon.size
            let scale = targetHeight / naturalSize.height
            let scaledWidth = naturalSize.width * scale
            let scaledHeight = targetHeight
            
            let iconRect = NSRect(
                x: currentX,
                y: rect.midY - scaledHeight / 2,
                width: scaledWidth,
                height: scaledHeight
            )
            
            typeIcon.draw(in: iconRect)
            iconSpace += scaledWidth + 4
        }
        
        // Draw title (offset if there's a type icon)
        let titleRect = NSRect(
            x: textRect.minX + 6 + iconSpace,
            y: textRect.midY - titleSize.height / 2,
            width: textRect.width - iconSpace,
            height: titleSize.height
        )
        
        attributedTitle.draw(in: titleRect)
        
        if let sortIcon = sortIcon {
            let naturalSize = sortIcon.size
            let maxIconHeight = rect.height * 0.25
            
            let scale = maxIconHeight / naturalSize.height
            let scaledWidth = naturalSize.width * scale
            let scaledHeight = naturalSize.height * scale
            
            let iconRect = NSRect(
                x: rect.maxX - scaledWidth - 8,
                y: rect.midY - scaledHeight / 2,
                width: scaledWidth,
                height: scaledHeight
            )
            
            sortIcon.draw(in: iconRect)
        }
    }
    
    private func drawCustomBackground(in frame: NSRect) {
        frame.fill(using: .clear)
        
        NSColor.separatorColor.setStroke()
        
        let verticalInset: CGFloat = 6
        let rightBorder = NSBezierPath()
        rightBorder.move(to: NSPoint(x: frame.maxX - 0.5, y: frame.minY + verticalInset))
        rightBorder.line(to: NSPoint(x: frame.maxX - 0.5, y: frame.maxY - verticalInset))
        rightBorder.lineWidth = 1
        rightBorder.stroke()
        
        let bottomBorder = NSBezierPath()
        bottomBorder.move(to: NSPoint(x: frame.minX, y: frame.maxY - 0.5))
        bottomBorder.line(to: NSPoint(x: frame.maxX, y: frame.maxY - 0.5))
        bottomBorder.lineWidth = 2
        bottomBorder.stroke()
    }
    
    
    
    override func cellSize(forBounds rect: NSRect) -> NSSize {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attributes = [NSAttributedString.Key.font: font]
        
        let titleSize = (title as NSString).size(withAttributes: attributes)
        
        // Add padding for your custom drawing including type icon
        let width = titleSize.width + 60 // Space for borders, type icon, sort icon, etc.
        let height = max(titleSize.height + 8, 32) // Minimum height
        
        return NSSize(width: width, height: height)
    }
    
    
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        drawCustomBackground(in: cellFrame)
        
        // Only draw content if this is a valid column header (not empty space)
        if !title.isEmpty {
            let typeIconData = getDataTypeIcon()
            drawTitle(in: cellFrame, sortIcon: getSortIcon(), typeIconData: typeIconData)
        }
    }
    
    func updateSortIndicator(isActive: Bool, ascending: Bool) {
        isActiveSortColumn = isActive
        sortAscending = ascending

        // Trigger redraw only if controlView is still valid
        guard let controlView = controlView, controlView.window != nil else {
            return
        }
        controlView.setNeedsDisplay(controlView.bounds)
    }
    
    // MARK: - Tooltip Support
    func getFieldType() -> String? {
        return tooltipText ?? fieldType
    }
}
