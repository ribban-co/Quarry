//
//  NSTextFieldCell.swift
//  Quarry
//
//  Created by Fauzaan on 6/24/25.
//

import Foundation
import AppKit

// MARK: - Custom NSTextFieldCell with internal padding
class PaddedTextFieldCell: NSTextFieldCell {
    let textPadding: NSEdgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
    
    override init(textCell string: String) {
        super.init(textCell: string)
        setupCell()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }
    
    private func setupCell() {
        applyDisplayMode()
    }

    private func applyDisplayMode() {
        lineBreakMode = .byTruncatingTail
        wraps = false
        isScrollable = false
        usesSingleLineMode = true
    }

    private func applyEditingMode() {
        lineBreakMode = .byClipping
        wraps = false
        isScrollable = true
        usesSingleLineMode = true
    }
    
    // Rest of your existing methods remain the same...
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var paddedRect = super.titleRect(forBounds: rect)
        paddedRect.origin.x += textPadding.left
        paddedRect.origin.y += textPadding.top
        paddedRect.size.width -= (textPadding.left + textPadding.right)
        paddedRect.size.height -= (textPadding.top + textPadding.bottom)
        return paddedRect
    }
    
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        applyEditingMode()

        var paddedRect = rect
        paddedRect.origin.x += textPadding.left - 2
        paddedRect.origin.y += textPadding.top
        paddedRect.size.width -= (textPadding.left + textPadding.right) - 4
        paddedRect.size.height -= (textPadding.top + textPadding.bottom)

        super.edit(withFrame: paddedRect, in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        applyEditingMode()

        var paddedRect = rect
        paddedRect.origin.x += textPadding.left - 2
        paddedRect.origin.y += textPadding.top
        paddedRect.size.width -= (textPadding.left + textPadding.right) - 4
        paddedRect.size.height -= (textPadding.top + textPadding.bottom)

        super.select(withFrame: paddedRect, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
    
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        applyDisplayMode()
        let paddedRect = titleRect(forBounds: cellFrame)
        super.drawInterior(withFrame: paddedRect, in: controlView)
    }
}

// MARK: - NSTextField
public extension NSTextField {
    func configureForTableCell() {
        // Content and appearance
        stringValue = ""
        textColor = .disabledControlTextColor
        font = .systemFont(ofSize: 12)
        
        // Disable expensive features for table cells
        isEditable = false  // Will be enabled on click
        isSelectable = true
        isBordered = false
        backgroundColor = .clear
        drawsBackground = false
        
        // Optimize text rendering
        allowsEditingTextAttributes = false
        importsGraphics = false
        
        isAutomaticTextCompletionEnabled = false
        allowsCharacterPickerTouchBarItem = false
        allowsDefaultTighteningForTruncation = false
        
        placeholderString = "(EMPTY)"
        
        isBordered = false
        isBezeled = false
        bezelStyle = .squareBezel  // Reset bezel style
        focusRingType = .none  // Disable the white focus ring
    }
}
