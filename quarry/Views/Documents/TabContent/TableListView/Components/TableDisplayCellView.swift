import AppKit
import CoreText

@MainActor
protocol TableForeignKeyCell: AnyObject {
    var isForeignKeyCell: Bool { get }
    func containsForeignKeyHit(point: NSPoint) -> Bool
}

@MainActor
final class TableDisplayCellView: NSView, TableForeignKeyCell {
    private static let previewFont = NSFont.preferredFont(forTextStyle: .body)
    private static let cellHorizontalInset: CGFloat = 8
    private static let ellipsisLine = makeLine(text: "\u{2026}", font: previewFont, color: .controlTextColor)
    private static let foreignKeyImage: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(hierarchicalColor: NSColor.secondaryLabelColor))
        return NSImage(systemSymbolName: "arrow.right.circle", accessibilityDescription: "Foreign Key")?
            .withSymbolConfiguration(config)
    }()

    private var displayText = ""
    private var textColor = NSColor.controlTextColor
    private var cachedLine: CTLine?

    private(set) var rowIndex = -1
    private(set) var columnName = ""
    private(set) var tableName = ""
    private(set) var constraintInfo: ConstraintInfo?

    private var isMarkedForDeletion = false
    private var isModified = false
    private var shouldHighlight = false
    private var hasValue = false
    private var placeholder = ""
    private var isEditing = false

    var isForeignKeyCell: Bool {
        constraintInfo?.isForeignKey ?? false
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = false
    }

    override func prepareForReuse() {
        rowIndex = -1
        columnName = ""
        tableName = ""
        constraintInfo = nil
        displayText = ""
        cachedLine = nil
        isMarkedForDeletion = false
        isModified = false
        shouldHighlight = false
        hasValue = false
        placeholder = ""
        isEditing = false
    }

    func configure(
        displayText: String,
        placeholder: String,
        hasValue: Bool,
        rowIndex: Int,
        columnName: String,
        tableName: String,
        constraintInfo: ConstraintInfo?,
        isModified: Bool,
        isMarkedForDeletion: Bool,
        shouldHighlight: Bool
    ) {
        self.rowIndex = rowIndex
        self.columnName = columnName
        self.tableName = tableName
        self.constraintInfo = constraintInfo
        self.isModified = isModified
        self.isMarkedForDeletion = isMarkedForDeletion
        self.shouldHighlight = shouldHighlight
        self.hasValue = hasValue
        self.placeholder = placeholder

        let nextDisplayText = hasValue ? displayText : placeholder
        let nextTextColor = hasValue ? NSColor.controlTextColor : NSColor.placeholderTextColor
        if self.displayText != nextDisplayText || !self.textColor.isEqual(nextTextColor) {
            self.displayText = nextDisplayText
            self.textColor = nextTextColor
            cachedLine = nil
        }
        needsDisplay = true
    }

    func setEditing(_ isEditing: Bool) {
        guard self.isEditing != isEditing else { return }
        self.isEditing = isEditing
        needsDisplay = true
    }

    func containsForeignKeyHit(point: NSPoint) -> Bool {
        guard isForeignKeyCell else { return false }
        return foreignKeyRect().insetBy(dx: -4, dy: -4).contains(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isMarkedForDeletion {
            NSColor.red.withAlphaComponent(0.3).setFill()
            bounds.insetBy(dx: 0, dy: 0).fill()
        } else if isModified {
            NSColor.cellModificationColor.setFill()
            bounds.fill()
        } else if shouldHighlight {
            NSColor.systemOrange.withAlphaComponent(0.28).setFill()
            bounds.fill()
        }

        if !isEditing {
            drawText()
        }
        drawForeignKeyIconIfNeeded()
        drawBordersIfNeeded()
    }

    private func drawText() {
        guard !displayText.isEmpty else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let totalAvailable = bounds.width - 2 * Self.cellHorizontalInset
        guard totalAvailable > 0 else { return }

        let trailingGap: CGFloat = isForeignKeyCell ? 24 : 0
        let availableWidth = max(0, totalAvailable - trailingGap)
        let fullLine = cachedCTLine()
        let typographicWidth = CTLineGetTypographicBounds(fullLine, nil, nil, nil)
        let ellipsisWidth = CTLineGetTypographicBounds(Self.ellipsisLine, nil, nil, nil)
        guard Double(availableWidth) >= ellipsisWidth else { return }

        let lineToDraw: CTLine
        if typographicWidth > Double(availableWidth) {
            lineToDraw = CTLineCreateTruncatedLine(fullLine, Double(availableWidth), .end, Self.ellipsisLine) ?? Self.ellipsisLine
        } else {
            lineToDraw = fullLine
        }

        let font = Self.previewFont
        let baselineY = (bounds.height - font.ascender + font.descender - font.leading) / 2 + font.ascender

        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: Self.cellHorizontalInset, y: baselineY)
        CTLineDraw(lineToDraw, context)
        context.restoreGState()
    }

    private func drawForeignKeyIconIfNeeded() {
        guard isForeignKeyCell, let image = Self.foreignKeyImage else { return }
        image.draw(in: foreignKeyRect(), from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func foreignKeyRect() -> NSRect {
        NSRect(
            x: bounds.width - 22,
            y: (bounds.height - 14) / 2,
            width: 14,
            height: 14
        )
    }

    private func drawBordersIfNeeded() {
        guard !TableAppearanceSettings.alternatingRowColors else { return }

        NSColor.separatorColor.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    private func cachedCTLine() -> CTLine {
        if let cachedLine { return cachedLine }
        let line = Self.makeLine(text: displayText, font: Self.previewFont, color: textColor)
        cachedLine = line
        return line
    }

    private static func makeLine(text: String, font: NSFont, color: NSColor) -> CTLine {
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
        return CTLineCreateWithAttributedString(attributed as CFAttributedString)
    }
}
