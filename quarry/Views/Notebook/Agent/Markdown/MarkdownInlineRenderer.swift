import AppKit

@MainActor
enum MarkdownInlineRenderer {

    private static let boldItalicPattern = try! NSRegularExpression(pattern: #"\*{3}(.+?)\*{3}"#)
    private static let boldPattern = try! NSRegularExpression(pattern: #"\*{2}(.+?)\*{2}"#)
    private static let italicPattern = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    private static let strikethroughPattern = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
    private static let inlineCodePattern = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    private static let linkPattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)

    static func render(
        _ text: String,
        font: NSFont = .systemFont(ofSize: NSFont.systemFontSize),
        color: NSColor = .labelColor
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        var matches: [InlineMatch] = []

        for match in linkPattern.matches(in: text, range: fullRange) {
            let linkText = nsText.substring(with: match.range(at: 1))
            let urlString = nsText.substring(with: match.range(at: 2))
            var attrs = baseAttributes
            attrs[.foregroundColor] = NSColor.controlAccentColor
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            if let url = URL(string: urlString) { attrs[.link] = url }
            matches.append(InlineMatch(range: match.range, replacement: NSAttributedString(string: linkText, attributes: attrs)))
        }

        collectMatches(pattern: boldItalicPattern, in: text, nsText: nsText, fullRange: fullRange, baseAttributes: baseAttributes, overrides: [.font: boldItalicFont(size: font.pointSize)], into: &matches)
        collectMatches(pattern: boldPattern, in: text, nsText: nsText, fullRange: fullRange, baseAttributes: baseAttributes, overrides: [.font: NSFont.boldSystemFont(ofSize: font.pointSize)], into: &matches)
        collectMatches(pattern: italicPattern, in: text, nsText: nsText, fullRange: fullRange, baseAttributes: baseAttributes, overrides: [.font: makeItalicFont(from: font)], into: &matches)
        collectMatches(pattern: strikethroughPattern, in: text, nsText: nsText, fullRange: fullRange, baseAttributes: baseAttributes, overrides: [.strikethroughStyle: NSUnderlineStyle.single.rawValue], into: &matches)
        for match in inlineCodePattern.matches(in: text, range: fullRange) {
            guard !overlaps(match.range, with: matches) else { continue }
            let content = nsText.substring(with: match.range(at: 1))
            let codeFont = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            let cell = InlineCodeAttachmentCell(text: content, font: codeFont, lineFont: font)
            let attachment = NSTextAttachment()
            attachment.attachmentCell = cell
            let attachStr = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            attachStr.addAttributes(baseAttributes, range: NSRange(location: 0, length: attachStr.length))
            matches.append(InlineMatch(range: match.range, replacement: attachStr))
        }

        matches.sort(by: >)
        for m in matches {
            result.replaceCharacters(in: m.range, with: m.replacement)
        }

        return result
    }

    private static func collectMatches(
        pattern: NSRegularExpression,
        in text: String,
        nsText: NSString,
        fullRange: NSRange,
        baseAttributes: [NSAttributedString.Key: Any],
        overrides: [NSAttributedString.Key: Any],
        into matches: inout [InlineMatch]
    ) {
        for match in pattern.matches(in: text, range: fullRange) {
            guard !overlaps(match.range, with: matches) else { continue }
            let content = nsText.substring(with: match.range(at: 1))
            let attrs = baseAttributes.merging(overrides) { _, new in new }
            matches.append(InlineMatch(range: match.range, replacement: NSAttributedString(string: content, attributes: attrs)))
        }
    }

    private static func overlaps(_ range: NSRange, with existing: [InlineMatch]) -> Bool {
        existing.contains { NSIntersectionRange(range, $0.range).length > 0 }
    }

    private struct InlineMatch: Comparable {
        let range: NSRange
        let replacement: NSAttributedString
        static func < (lhs: InlineMatch, rhs: InlineMatch) -> Bool {
            lhs.range.location < rhs.range.location
        }
    }

    private static func makeItalicFont(from font: NSFont) -> NSFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    private static func boldItalicFont(size: CGFloat) -> NSFont {
        let descriptor = NSFont.systemFont(ofSize: size, weight: .bold)
            .fontDescriptor
            .withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: size) ?? NSFont.boldSystemFont(ofSize: size)
    }
}

// MARK: - Inline Code Attachment

private final class InlineCodeAttachmentCell: NSTextAttachmentCell {

    private let text: String
    private let codeFont: NSFont
    private let lineFont: NSFont
    private static let hPad: CGFloat = 5
    private static let vPad: CGFloat = 1.5
    private static let cornerRadius: CGFloat = 4

    init(text: String, font: NSFont, lineFont: NSFont) {
        self.text = text
        self.codeFont = font
        self.lineFont = lineFont
        super.init()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func cellSize() -> NSSize {
        MainActor.assumeIsolated {
            let textSize = (text as NSString).size(withAttributes: [.font: codeFont])
            return NSSize(
                width: ceil(textSize.width) + Self.hPad * 2,
                height: ceil(lineFont.ascender - lineFont.descender + Self.vPad * 2)
            )
        }
    }

    override func cellBaselineOffset() -> NSPoint {
        MainActor.assumeIsolated {
            NSPoint(x: 0, y: lineFont.descender - Self.vPad)
        }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let isDark = (controlView ?? NSApp.mainWindow?.contentView)?.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let bgColor = isDark
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.white
        let borderColor = isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.1)

        let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        bgColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let textSize = (text as NSString).size(withAttributes: [.font: codeFont])
        let textRect = NSRect(
            x: cellFrame.origin.x + Self.hPad,
            y: cellFrame.origin.y + (cellFrame.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: [
            .font: codeFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }
}

extension NSTextField {

    func configureForMarkdownDisplay() {
        isEditable = false
        isSelectable = true
        allowsEditingTextAttributes = true
        isBordered = false
        isBezeled = false
        drawsBackground = false
        lineBreakMode = .byCharWrapping
        maximumNumberOfLines = 0
        cell?.wraps = true
        cell?.isScrollable = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}
