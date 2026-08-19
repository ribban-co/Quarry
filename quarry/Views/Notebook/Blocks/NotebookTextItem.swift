import AppKit

final class NotebookTextItem: NotebookBaseItem, NSTextViewDelegate {

    static let identifier = NSUserInterfaceItemIdentifier("NotebookTextItem")

    private weak var hostedController: TextBlockController?
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var isUpdatingText = false
    private var activeLine: Int = -1

    private let codeBlockTracker = MarkdownCodeBlockTracker()

    private let defaultFont = NSFont.systemFont(ofSize: 14)
    private let defaultTextColor = NSColor.labelColor
    private let defaultParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        return style
    }()

    override func setupContent() {
        scrollView = PassthroughScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(scrollView)

        textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = defaultFont
        textView.textColor = defaultTextColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self
        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: blockContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),
        ])

        setupPlaceholder()
    }

    func configure(block: NotebookBlock, controller: TextBlockController) {
        configureBase(block: block)
        hostedController = controller
        activeLine = -1

        isUpdatingText = true
        textView.string = block.textContent
        applyMarkdownStyling()
        isUpdatingText = false
        updatePlaceholder()
    }

    func focusEditor() {
        view.window?.makeFirstResponder(textView)
    }

    override func prepareForReuse() {
        hostedController = nil
        isUpdatingText = true
        textView?.string = ""
        isUpdatingText = false
        activeLine = -1
        updatePlaceholder()
        super.prepareForReuse()
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !isUpdatingText else { return }
        applyMarkdownStyling()
        updatePlaceholder()
        if let controller = hostedController {
            controller.handleTextChange(textView.string)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isUpdatingText else { return }
        let cursorLine = currentCursorLine()
        if cursorLine != activeLine {
            activeLine = cursorLine
            applyMarkdownStyling()
        }
    }

    // MARK: - Markdown Styling

    private func currentCursorLine() -> Int {
        let text = textView.string as NSString
        guard text.length > 0 else { return 0 }

        let cursorLocation = textView.selectedRange().location
        var lineIndex = 0
        var lineStart = 0

        while lineStart < text.length {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))

            if cursorLocation >= lineStart && cursorLocation < lineEnd {
                return lineIndex
            }

            lineIndex += 1
            lineStart = lineEnd
        }

        return max(0, lineIndex - 1)
    }

    private func applyMarkdownStyling() {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        let selectedRanges = textView.selectedRanges

        textStorage.beginEditing()
        textStorage.setAttributes([
            .font: defaultFont,
            .foregroundColor: defaultTextColor,
            .paragraphStyle: defaultParagraphStyle,
        ], range: fullRange)

        codeBlockTracker.update(text: textStorage.string)
        applyCodeBlockBodyStyling(textStorage)

        let styledRanges = MarkdownParser.styledRanges(for: textStorage.string, defaultFont: defaultFont)
        let text = textStorage.string as NSString

        for styled in styledRanges {
            guard styled.range.location + styled.range.length <= textStorage.length else { continue }

            let lineIndex = lineIndexForLocation(styled.range.location, in: text)
            if codeBlockTracker.isInsideCodeBlock(lineIndex: lineIndex) { continue }

            if styled.isMarker && lineIndex != activeLine {
                textStorage.addAttributes(MarkdownParser.hiddenMarkerAttributes, range: styled.range)
            } else {
                textStorage.addAttributes(styled.attributes, range: styled.range)
            }
        }

        textStorage.endEditing()
        textView.selectedRanges = selectedRanges
    }

    private func lineIndexForLocation(_ location: Int, in text: NSString) -> Int {
        var lineIndex = 0
        var lineStart = 0
        while lineStart < text.length && lineStart < location {
            var lineEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: nil, for: NSRange(location: lineStart, length: 0))
            if lineEnd <= location {
                lineIndex += 1
                lineStart = lineEnd
            } else {
                break
            }
        }
        return lineIndex
    }

    private func applyCodeBlockBodyStyling(_ textStorage: NSTextStorage) {
        let text = textStorage.string as NSString
        var lineIndex = 0
        var lineStart = 0
        let codeFont = NSFont.monospacedSystemFont(ofSize: defaultFont.pointSize - 1, weight: .regular)
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        while lineStart < text.length {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))

            if codeBlockTracker.isInsideCodeBlock(lineIndex: lineIndex) {
                let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
                if lineRange.length > 0 {
                    textStorage.addAttributes(codeAttrs, range: lineRange)
                }
            }

            lineIndex += 1
            lineStart = lineEnd
        }
    }

    // MARK: - Placeholder

    private var placeholderField: NSTextField?

    private func setupPlaceholder() {
        let field = NSTextField(labelWithString: "Write something...")
        field.font = defaultFont
        field.textColor = .placeholderTextColor
        field.backgroundColor = .clear
        field.isBordered = false
        field.isBezeled = false
        field.isEditable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(field)

        let insets = textView.textContainerInset
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: blockContainer.topAnchor, constant: insets.height),
            field.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor, constant: insets.width),
        ])

        placeholderField = field
    }

    private func updatePlaceholder() {
        placeholderField?.isHidden = !(textView?.string.isEmpty ?? true)
    }
}
