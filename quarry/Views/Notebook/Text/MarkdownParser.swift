import AppKit

struct MarkdownStyledRange {
    let range: NSRange
    let attributes: [NSAttributedString.Key: Any]
    let isMarker: Bool
}

@MainActor
enum MarkdownParser {

    // MARK: - Cached Patterns

    private static let taskListPattern = try! NSRegularExpression(pattern: #"^(\s*)- \[([ xX])\] "#)
    private static let unorderedListPattern = try! NSRegularExpression(pattern: #"^(\s*)[-*+] "#)
    private static let orderedListPattern = try! NSRegularExpression(pattern: #"^(\s*)\d+[.)]\s"#)
    private static let boldItalicPattern = try! NSRegularExpression(pattern: #"\*{3}(.+?)\*{3}"#)
    private static let boldPattern = try! NSRegularExpression(pattern: #"\*{2}(.+?)\*{2}"#)
    private static let italicPattern = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    private static let strikethroughPattern = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
    private static let inlineCodePattern = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    private static let linkPattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)
    private static let imagePattern = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#)

    // MARK: - Hidden marker attributes (near-invisible when cursor is elsewhere)

    static let hiddenMarkerAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 0.01),
        .foregroundColor: NSColor.clear,
    ]

    // MARK: - Public

    static func styledRanges(for text: String, defaultFont: NSFont) -> [MarkdownStyledRange] {
        var results: [MarkdownStyledRange] = []
        let nsText = text as NSString

        var lineStart = 0
        while lineStart < nsText.length {
            var lineEnd = 0
            var contentsEnd = 0
            nsText.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let lineString = nsText.substring(with: lineRange)

            parseBlockLevel(lineString, lineRange: lineRange, defaultFont: defaultFont, into: &results)

            lineStart = lineEnd
        }

        return results
    }

    // MARK: - Block-Level

    private static func parseBlockLevel(_ line: String, lineRange: NSRange, defaultFont: NSFont, into results: inout [MarkdownStyledRange]) {
        let trimmed = line.trimmingLeadingWhitespace()

        // Headings
        if let headingResult = parseHeading(trimmed, lineRange: lineRange, defaultFont: defaultFont) {
            results.append(contentsOf: headingResult)
            return
        }

        // Horizontal rule
        if isHorizontalRule(trimmed) {
            results.append(MarkdownStyledRange(
                range: lineRange,
                attributes: [.foregroundColor: NSColor.tertiaryLabelColor],
                isMarker: false
            ))
            return
        }

        // Blockquote
        if trimmed.hasPrefix(">") {
            let italicFont = makeItalicFont(from: defaultFont)
            results.append(MarkdownStyledRange(
                range: lineRange,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: italicFont],
                isMarker: false
            ))
            // Mark the `> ` prefix as a marker
            let prefixOffset = line.count - trimmed.count
            let markerLen = trimmed.hasPrefix("> ") ? 2 : 1
            results.append(MarkdownStyledRange(
                range: NSRange(location: lineRange.location + prefixOffset, length: markerLen),
                attributes: [.foregroundColor: NSColor.tertiaryLabelColor],
                isMarker: true
            ))
            parseInlineElements(line, lineRange: lineRange, defaultFont: defaultFont, into: &results)
            return
        }

        // Code block fence
        if trimmed.hasPrefix("```") {
            results.append(MarkdownStyledRange(
                range: lineRange,
                attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: monoFont(size: defaultFont.pointSize),
                ],
                isMarker: true
            ))
            return
        }

        // Task list
        let nsLine = line as NSString
        let taskMatches = taskListPattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        if let taskMatch = taskMatches.first {
            let markerRange = NSRange(location: lineRange.location + taskMatch.range.location, length: taskMatch.range.length)
            let checkRange = taskMatch.range(at: 2)
            let checkChar = nsLine.substring(with: checkRange)
            let isChecked = checkChar != " "
            results.append(MarkdownStyledRange(
                range: markerRange,
                attributes: [.foregroundColor: isChecked ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor],
                isMarker: false
            ))
            parseInlineElements(line, lineRange: lineRange, defaultFont: defaultFont, into: &results)
            return
        }

        // Unordered list
        let ulMatches = unorderedListPattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        if let ulMatch = ulMatches.first {
            let bulletRange = NSRange(location: lineRange.location + ulMatch.range.location, length: ulMatch.range.length)
            results.append(MarkdownStyledRange(
                range: bulletRange,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor],
                isMarker: false
            ))
            parseInlineElements(line, lineRange: lineRange, defaultFont: defaultFont, into: &results)
            return
        }

        // Ordered list
        let olMatches = orderedListPattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        if let olMatch = olMatches.first {
            let numRange = NSRange(location: lineRange.location + olMatch.range.location, length: olMatch.range.length)
            results.append(MarkdownStyledRange(
                range: numRange,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor],
                isMarker: false
            ))
            parseInlineElements(line, lineRange: lineRange, defaultFont: defaultFont, into: &results)
            return
        }

        // Table row
        if trimmed.hasPrefix("|") {
            results.append(MarkdownStyledRange(
                range: lineRange,
                attributes: [.font: monoFont(size: defaultFont.pointSize - 1)],
                isMarker: false
            ))
            for i in 0..<nsLine.length where nsLine.character(at: i) == 0x7C {
                results.append(MarkdownStyledRange(
                    range: NSRange(location: lineRange.location + i, length: 1),
                    attributes: [.foregroundColor: NSColor.tertiaryLabelColor],
                    isMarker: false
                ))
            }
            return
        }

        // Regular paragraph
        parseInlineElements(line, lineRange: lineRange, defaultFont: defaultFont, into: &results)
    }

    // MARK: - Headings

    private static func parseHeading(_ trimmed: String, lineRange: NSRange, defaultFont: NSFont) -> [MarkdownStyledRange]? {
        guard trimmed.hasPrefix("#") else { return nil }

        let level: Int
        if trimmed.hasPrefix("### ") { level = 3 }
        else if trimmed.hasPrefix("## ") { level = 2 }
        else if trimmed.hasPrefix("# ") { level = 1 }
        else { return nil }

        let fontSize: CGFloat
        let weight: NSFont.Weight
        switch level {
        case 1:
            fontSize = 24
            weight = .bold
        case 2:
            fontSize = 20
            weight = .semibold
        default:
            fontSize = 16
            weight = .semibold
        }

        let hashCount = level + 1
        var ranges: [MarkdownStyledRange] = []

        // Style the whole line with heading font + extra spacing after
        let headingParagraph = NSMutableParagraphStyle()
        headingParagraph.lineSpacing = 6
        headingParagraph.paragraphSpacing = 8
        ranges.append(MarkdownStyledRange(
            range: lineRange,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                .paragraphStyle: headingParagraph,
            ],
            isMarker: false
        ))

        // The hash prefix is a marker — hidden when cursor is not on this line
        ranges.append(MarkdownStyledRange(
            range: NSRange(location: lineRange.location, length: hashCount),
            attributes: [.foregroundColor: NSColor.tertiaryLabelColor],
            isMarker: true
        ))

        return ranges
    }

    // MARK: - Inline Elements

    private static func parseInlineElements(_ line: String, lineRange: NSRange, defaultFont: NSFont, into results: inout [MarkdownStyledRange]) {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        // Bold italic (***text***)
        applyInlinePattern(
            nsLine, lineOffset: lineRange.location, fullRange: fullRange,
            pattern: boldItalicPattern,
            fullAttributes: [.font: boldItalicFont(size: defaultFont.pointSize)],
            markerLengths: (3, 3),
            into: &results
        )

        // Bold (**text**)
        applyInlinePattern(
            nsLine, lineOffset: lineRange.location, fullRange: fullRange,
            pattern: boldPattern,
            fullAttributes: [.font: NSFont.boldSystemFont(ofSize: defaultFont.pointSize)],
            markerLengths: (2, 2),
            into: &results
        )

        // Italic (*text*)
        applyInlinePattern(
            nsLine, lineOffset: lineRange.location, fullRange: fullRange,
            pattern: italicPattern,
            fullAttributes: [.font: makeItalicFont(from: defaultFont)],
            markerLengths: (1, 1),
            into: &results
        )

        // Strikethrough (~~text~~)
        applyInlinePattern(
            nsLine, lineOffset: lineRange.location, fullRange: fullRange,
            pattern: strikethroughPattern,
            fullAttributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue],
            markerLengths: (2, 2),
            into: &results
        )

        // Inline code (`code`)
        applyInlinePattern(
            nsLine, lineOffset: lineRange.location, fullRange: fullRange,
            pattern: inlineCodePattern,
            fullAttributes: [
                .font: monoFont(size: defaultFont.pointSize - 1),
                .foregroundColor: NSColor.systemPink,
                .backgroundColor: NSColor.quaternaryLabelColor,
            ],
            markerLengths: (1, 1),
            into: &results
        )

        // Links [text](url)
        let linkMatches = linkPattern.matches(in: line, range: fullRange)
        for match in linkMatches {
            let textRange = match.range(at: 1)
            let urlRange = match.range(at: 2)

            // Link text — styled, not a marker
            let styledTextRange = NSRange(location: lineRange.location + textRange.location, length: textRange.length)
            results.append(MarkdownStyledRange(
                range: styledTextRange,
                attributes: [
                    .foregroundColor: NSColor.controlAccentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                isMarker: false
            ))

            // All syntax around the link — markers
            let openBracket = NSRange(location: lineRange.location + match.range.location, length: 1)
            let closeBracketParen = NSRange(location: lineRange.location + textRange.location + textRange.length, length: 2)
            let urlStyleRange = NSRange(location: lineRange.location + urlRange.location, length: urlRange.length)
            let closeParen = NSRange(location: lineRange.location + match.range.location + match.range.length - 1, length: 1)

            for r in [openBracket, closeBracketParen, urlStyleRange, closeParen] {
                results.append(MarkdownStyledRange(range: r, attributes: [.foregroundColor: NSColor.tertiaryLabelColor], isMarker: true))
            }
        }

        // Images ![alt](url)
        let imgMatches = imagePattern.matches(in: line, range: fullRange)
        for match in imgMatches {
            let imgFullRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
            results.append(MarkdownStyledRange(range: imgFullRange, attributes: [.foregroundColor: NSColor.systemTeal], isMarker: false))
        }
    }

    // MARK: - Inline Pattern Helper

    private static func applyInlinePattern(
        _ nsLine: NSString,
        lineOffset: Int,
        fullRange: NSRange,
        pattern: NSRegularExpression,
        fullAttributes: [NSAttributedString.Key: Any],
        markerLengths: (Int, Int),
        into results: inout [MarkdownStyledRange]
    ) {
        let matches = pattern.matches(in: nsLine as String, range: fullRange)
        for match in matches {
            let matchRange = NSRange(location: lineOffset + match.range.location, length: match.range.length)

            // Apply formatting to full match — not a marker
            results.append(MarkdownStyledRange(range: matchRange, attributes: fullAttributes, isMarker: false))

            // Opening markers
            let openRange = NSRange(location: matchRange.location, length: markerLengths.0)
            results.append(MarkdownStyledRange(range: openRange, attributes: [.foregroundColor: NSColor.tertiaryLabelColor], isMarker: true))

            // Closing markers
            let closeRange = NSRange(location: matchRange.location + matchRange.length - markerLengths.1, length: markerLengths.1)
            results.append(MarkdownStyledRange(range: closeRange, attributes: [.foregroundColor: NSColor.tertiaryLabelColor], isMarker: true))
        }
    }

    // MARK: - Horizontal Rule

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let cleaned = trimmed.replacing(" ", with: "")
        guard cleaned.count >= 3 else { return false }
        return cleaned.allSatisfy({ $0 == "-" }) ||
               cleaned.allSatisfy({ $0 == "*" }) ||
               cleaned.allSatisfy({ $0 == "_" })
    }

    // MARK: - Fonts

    private static func monoFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
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

// MARK: - Code Block State Tracker

@MainActor
final class MarkdownCodeBlockTracker {
    private var fenceLineIndices: Set<Int> = []
    private var codeBlockRanges: [(start: Int, end: Int)] = []

    func update(text: String) {
        fenceLineIndices.removeAll()
        codeBlockRanges.removeAll()

        let nsText = text as NSString
        var lineIndex = 0
        var lineStart = 0
        var insideCodeBlock = false
        var codeBlockStart = 0

        while lineStart < nsText.length {
            var lineEnd = 0
            var contentsEnd = 0
            nsText.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
            let lineString = nsText.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))

            if lineString.trimmingLeadingWhitespace().hasPrefix("```") {
                fenceLineIndices.insert(lineIndex)
                if insideCodeBlock {
                    codeBlockRanges.append((start: codeBlockStart, end: lineIndex))
                    insideCodeBlock = false
                } else {
                    codeBlockStart = lineIndex
                    insideCodeBlock = true
                }
            }

            lineIndex += 1
            lineStart = lineEnd
        }
    }

    func isInsideCodeBlock(lineIndex: Int) -> Bool {
        codeBlockRanges.contains { lineIndex > $0.start && lineIndex < $0.end }
    }

    func isFenceLine(lineIndex: Int) -> Bool {
        fenceLineIndices.contains(lineIndex)
    }
}

private extension String {
    func trimmingLeadingWhitespace() -> String {
        guard let idx = firstIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(self[idx...])
    }
}
