import AppKit

final class DashboardTextItem: DashboardBaseItem {

    static let identifier = NSUserInterfaceItemIdentifier("DashboardTextItem")

    private var scrollView: NSScrollView!
    private var textView: NSTextView!

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
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: blockContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),
        ])
    }

    func configure(block: NotebookBlock, isPublished: Bool = false) {
        configureBase(block: block, isPublished: isPublished)
        scrollView.hasVerticalScroller = !isPublished
        (scrollView as? PassthroughScrollView)?.isScrollingEnabled = !isPublished

        let text = block.textContent
        let defaultFont = NSFont.systemFont(ofSize: 14)
        let attrString = NSMutableAttributedString(string: text, attributes: [
            .font: defaultFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: defaultParagraphStyle,
        ])

        let styledRanges = MarkdownParser.styledRanges(for: text, defaultFont: defaultFont)
        for styled in styledRanges {
            if styled.isMarker {
                attrString.addAttributes(MarkdownParser.hiddenMarkerAttributes, range: styled.range)
            } else {
                attrString.addAttributes(styled.attributes, range: styled.range)
            }
        }

        textView.textStorage?.setAttributedString(attrString)
        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        resetScrollPosition()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        resetScrollPosition()
    }

    private func resetScrollPosition() {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
