import AppKit

@MainActor
protocol MarkdownTextViewDelegate: AnyObject {
    func markdownTextViewDidChange(_ textView: MarkdownTextView)
}


@MainActor
final class MarkdownTextView: NSView, NSTextViewDelegate {

    weak var delegate: MarkdownTextViewDelegate?

    private let scrollView: NSScrollView
    private let textView: NSTextView
    private let codeBlockTracker = MarkdownCodeBlockTracker()
    private var isUpdatingText = false
    private var activeLine: Int = -1
    private var pendingText: String?

    private let defaultFont = NSFont.systemFont(ofSize: 14)
    private let defaultTextColor = NSColor.labelColor
    private let defaultParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        return style
    }()

    var string: String {
        get { pendingText ?? textView.string }
        set {
            guard newValue != string else { return }
            if bounds.width > 0, bounds.height > 0 {
                commitText(newValue)
            } else {
                pendingText = newValue
            }
            updatePlaceholder()
        }
    }

    override init(frame: NSRect) {
        textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView = PassthroughScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        super.init(frame: frame)

        textView.delegate = self
        wantsLayer = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setupPlaceholder()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func focus() {
        window?.makeFirstResponder(textView)
    }

    func setNeedsTextLayoutRefresh() {
        flushPendingText()
    }

    override func layout() {
        super.layout()
        flushPendingText()
    }

    private func commitText(_ text: String) {
        pendingText = nil
        isUpdatingText = true
        textView.string = text
        applyMarkdownStyling()
        isUpdatingText = false
    }

    private func flushPendingText() {
        guard let text = pendingText, bounds.width > 0, bounds.height > 0 else { return }
        commitText(text)
        updatePlaceholder()
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !isUpdatingText else { return }
        applyMarkdownStyling()
        updatePlaceholder()
        delegate?.markdownTextViewDidChange(self)
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
        addSubview(field)

        let insets = textView.textContainerInset
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: topAnchor, constant: insets.height),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.width),
        ])

        placeholderField = field
    }

    private func updatePlaceholder() {
        let isEmpty = (pendingText ?? textView.string).isEmpty
        placeholderField?.isHidden = !isEmpty
    }
}
