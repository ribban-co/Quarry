import AppKit

struct ERDNodeRenderer {
    static let headerHeight: CGFloat = 40
    static let rowHeight: CGFloat = 28
    static let cornerRadius: CGFloat = 14
    static let horizontalPadding: CGFloat = 16

    static let accent = NSColor(red: 248/255.0, green: 148/255.0, blue: 99/255.0, alpha: 1.0)

    private static let bgColorDark = NSColor(white: 0.114, alpha: 1)
    private static let bgColorLight = NSColor(white: 0.999, alpha: 1)
    private static let headerColorDark = NSColor(white: 0.20, alpha: 1)
    private static let headerColorLight = NSColor(white: 0.975, alpha: 1)
    private static let subtleBorderColor = NSColor(white: 0.26, alpha: 1)
    private static let dividerColorLight = NSColor(white: 0.90, alpha: 1)
    private static let colNameColorDark = NSColor.white
    private static let colNameColorLight = NSColor(white: 0.15, alpha: 1)
    private static let typeColorDark = NSColor(white: 0.42, alpha: 1)
    private static let typeColorLight = NSColor(white: 0.55, alpha: 1)
    private static let titleColorDark = NSColor.white
    private static let titleColorLight = NSColor(white: 0.1, alpha: 1)

    nonisolated(unsafe) private static let nameFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    nonisolated(unsafe) private static let colNameFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    nonisolated(unsafe) private static let typeFont = NSFont.systemFont(ofSize: 12, weight: .regular)

    private static nonisolated(unsafe) var symbolCache: [String: NSImage] = [:]

    private static func cachedSymbol(_ name: String, color: NSColor, pointSize: CGFloat) -> NSImage? {
        let key = "\(name)-\(pointSize)-\(color.hashValue)"
        if let cached = symbolCache[key] { return cached }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(.init(paletteColors: [color]))
        let result = image.withSymbolConfiguration(config) ?? image
        symbolCache[key] = result
        return result
    }

    static func draw(
        node: CanvasNode,
        tableData: ERDTableData,
        in context: CGContext,
        isSelected: Bool,
        hoveredColumnIndex: Int? = nil,
        isDark: Bool
    ) {
        let rect = node.frame
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Shadow
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -2),
            blur: 8,
            color: NSColor.black.withAlphaComponent(isDark ? 0.4 : 0.2).cgColor
        )
        let bgColor = isDark ? bgColorDark : bgColorLight
        context.setFillColor(bgColor.cgColor)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        // Header background
        let headerColor = isDark ? headerColorDark : headerColorLight
        let headerRect = CGRect(x: rect.minX, y: rect.maxY - headerHeight, width: rect.width, height: headerHeight)
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.setFillColor(headerColor.cgColor)
        context.fill(headerRect)
        context.restoreGState()

        // Selection glow
        if isSelected {
            let glowInset: CGFloat = -3.0
            let glowRect = rect.insetBy(dx: glowInset, dy: glowInset)
            let glowPath = CGPath(roundedRect: glowRect, cornerWidth: cornerRadius - glowInset, cornerHeight: cornerRadius - glowInset, transform: nil)
            context.setStrokeColor(accent.withAlphaComponent(0.20).cgColor)
            context.setLineWidth(3.0)
            context.addPath(glowPath)
            context.strokePath()
        }

        let borderColor = isSelected
            ? accent
            : (isDark ? subtleBorderColor : NSColor.white)
        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(isSelected ? 2.0 : 1.0)
        context.setLineDash(phase: 0, lengths: [])
        context.addPath(path)
        context.strokePath()

        let dividerColor = isDark ? subtleBorderColor : dividerColorLight
        context.setStrokeColor(dividerColor.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: rect.minX + 1.5, y: headerRect.minY))
        context.addLine(to: CGPoint(x: rect.maxX - 1.5, y: headerRect.minY))
        context.strokePath()

        let titleColor = isDark ? titleColorDark : titleColorLight
        let iconImage = cachedSymbol("tablecells", color: NSColor.secondaryLabelColor, pointSize: 14)
        let iconImageSize = iconImage?.size ?? CGSize(width: 16, height: 16)
        let iconRect = CGRect(
            x: rect.minX + horizontalPadding,
            y: headerRect.midY - iconImageSize.height / 2 - 0.5,
            width: iconImageSize.width,
            height: iconImageSize.height
        )
        if let iconImage {
            drawImage(iconImage, in: iconRect, context: context)
        }

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .foregroundColor: titleColor
        ]
        let nameX = iconRect.maxX + 6
        let nameSize = (tableData.tableName as NSString).size(withAttributes: nameAttrs)
        (tableData.tableName as NSString).draw(
            at: CGPoint(x: nameX, y: headerRect.midY - nameSize.height / 2),
            withAttributes: nameAttrs
        )

        for (i, column) in tableData.columns.enumerated() {
            let rowY = rect.maxY - headerHeight - 8 - CGFloat(i + 1) * rowHeight
            let rowRect = CGRect(x: rect.minX, y: rowY, width: rect.width, height: rowHeight)

            if hoveredColumnIndex == i {
                let hoverInset: CGFloat = 6
                let hoverRect = CGRect(
                    x: rowRect.minX + hoverInset,
                    y: rowRect.minY,
                    width: rowRect.width - hoverInset * 2,
                    height: rowRect.height
                )
                let hoverPath = CGPath(roundedRect: hoverRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                let hoverColor = isDark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.04)
                context.setFillColor(hoverColor.cgColor)
                context.addPath(hoverPath)
                context.fillPath()
            }

            let iconX = rowRect.minX + 14
            let iconSymbolSize: CGFloat = 10
            if column.isPrimaryKey {
                drawCachedSymbolCentered("key.fill", color: .systemYellow, centerY: rowRect.midY, x: iconX, size: iconSymbolSize, in: context)
            } else if column.isForeignKey {
                drawCachedSymbolCentered("link", color: accent, centerY: rowRect.midY, x: iconX, size: iconSymbolSize, in: context)
            }
            let xOffset = iconX + 22

            let colNameColor = isDark ? colNameColorDark : colNameColorLight
            let colNameAttrs: [NSAttributedString.Key: Any] = [
                .font: colNameFont,
                .foregroundColor: column.isNullable ? colNameColor.withAlphaComponent(0.55) : colNameColor
            ]
            (column.name as NSString).draw(
                at: CGPoint(x: xOffset, y: rowRect.minY + 7),
                withAttributes: colNameAttrs
            )

            let typeColor = isDark ? typeColorDark : typeColorLight
            let typeAttrs: [NSAttributedString.Key: Any] = [
                .font: typeFont,
                .foregroundColor: typeColor
            ]
            let typeStr = column.dataType as NSString
            let typeSize = typeStr.size(withAttributes: typeAttrs)
            typeStr.draw(
                at: CGPoint(
                    x: rowRect.maxX - horizontalPadding - typeSize.width,
                    y: rowRect.minY + 8
                ),
                withAttributes: typeAttrs
            )
        }
    }

    // MARK: - Drawing Helpers

    private static func drawCachedSymbolCentered(_ name: String, color: NSColor, centerY: CGFloat, x: CGFloat, size: CGFloat, in context: CGContext) {
        guard let tinted = cachedSymbol(name, color: color, pointSize: size) else { return }
        let imageSize = tinted.size
        let drawRect = CGRect(
            x: x,
            y: centerY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        drawImage(tinted, in: drawRect, context: context)
    }

    private static func drawImage(_ image: NSImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    // MARK: - Port Positions

    static func portPosition(for columnName: String, in node: CanvasNode, tableData: ERDTableData, side: PortSide) -> CGPoint? {
        guard let colIndex = tableData.columns.firstIndex(where: { $0.name == columnName }) else {
            return nil
        }
        let rowY = node.frame.maxY - headerHeight - 8 - CGFloat(colIndex) * rowHeight - rowHeight / 2
        let x: CGFloat = side == .left ? node.frame.minX : node.frame.maxX
        return CGPoint(x: x, y: rowY)
    }

    enum PortSide {
        case left, right
    }
}
