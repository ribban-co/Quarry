import AppKit
import CodeEditorView
import SwiftUI

@MainActor
final class QuickLookViewController: NSViewController {
    private static let defaultContentSize = NSSize(width: 450, height: 150)
    private static var lastUsedContentSize: NSSize?
    private static let minimumContentSize = NSSize(width: 220, height: 140)
    fileprivate static var resizeHandleEdgeInset: CGFloat {
        if #available(macOS 26, *) {
            3
        } else {
            2
        }
    }
    private static let resizeHandleSize: CGFloat = 28
    private static var resizeHandleHitOutset: CGFloat {
        if #available(macOS 26, *) {
            8
        } else {
            6
        }
    }
    private static var resizeHandleScrollerInset: CGFloat {
        if #available(macOS 26, *) {
            16
        } else {
            14
        }
    }
    private static var resizeHandleTextOverlap: CGFloat {
        resizeHandleSize - resizeHandleHitOutset
    }
    fileprivate static let editorCornerRadius: CGFloat = 12
    fileprivate static let contentInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    fileprivate static let contentSpacing: CGFloat = 6
    fileprivate static let footerHeight: CGFloat = 28
    fileprivate static let editorLineHeight: CGFloat = 17
    fileprivate static var editorBackgroundColor: NSColor {
        let isDark = NSAppearance.currentDrawing().isDarkMode
        return isDark
            ? NSColor.black.withAlphaComponent(0.6)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.86)
    }
    private static let contentWidthDefaultsKey = "quickLookPopover.contentWidth"
    private static let contentHeightDefaultsKey = "quickLookPopover.contentHeight"

    private let displayedInitialContent: String
    private let allowsSaveWithoutTextChanges: Bool
    private let onResizeStart: () -> Void
    private let onResize: (NSSize) -> Void
    private let onResizeEnd: () -> Void
    private let onSave: (String) -> Void
    private let onDismiss: () -> Void

    private weak var positioningView: NSView?
    private var positioningRect: NSRect = .zero
    private var isEditorHovered = false
    private var textView: QuickLookGripAwareTextView!
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    private var resizeHandleBottomConstraint: NSLayoutConstraint!
    private var resizeHandle: QuickLookResizeHandleView!
    private weak var gripClipView: QuickLookGripAwareClipView?
    private weak var editorHoverTrackingView: QuickLookEditorContainerView?
    private var isResizeHandleHovered = false
    private var lockedResizeHandlePlacement: ResizeHandlePlacement?
    private let buttonState = QuickLookButtonState()
    private var pendingEditedRange: NSRange?

    init(
        content: String,
        onResizeStart: @escaping () -> Void,
        onResize: @escaping (NSSize) -> Void,
        onResizeEnd: @escaping () -> Void,
        onSave: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.displayedInitialContent = Self.prettyJSON(content)
        self.allowsSaveWithoutTextChanges = self.displayedInitialContent != content
        self.onResizeStart = onResizeStart
        self.onResize = onResize
        self.onResizeEnd = onResizeEnd
        self.onSave = onSave
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        buttonState.isSaveEnabled = allowsSaveWithoutTextChanges
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func loadView() {
        let container = NSView()
        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        let footerContainer = NSView()
        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        let editorContainer = QuickLookEditorContainerView()
        editorContainer.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.onHoverChange = { [weak self] isHovered in
            self?.isEditorHovered = isHovered
            self?.updateResizeHandleVisibility()
        }
        self.editorHoverTrackingView = editorContainer

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: max(Self.resizeHandleScrollerInset, Self.resizeHandleTextOverlap), right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = QuickLookGripAwareClipView()
        clipView.drawsBackground = false
        clipView.gripExclusionSize = NSSize(width: Self.resizeHandleTextOverlap, height: Self.resizeHandleTextOverlap)
        scrollView.contentView = clipView
        self.gripClipView = clipView

        let textView = QuickLookGripAwareTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        let textViewFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.font = textViewFont
        textView.string = displayedInitialContent
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        self.textView = textView

        let buttonBar = QuickLookButtonBar(
            state: buttonState,
            onSave: { [weak self] in self?.saveAction() },
            onCancel: { [weak self] in self?.cancelAction() }
        )
        let buttonHostingView = NSHostingView(rootView: buttonBar)
        buttonHostingView.translatesAutoresizingMaskIntoConstraints = false

        let resizeHandle = QuickLookResizeHandleView()
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.currentSize = { [weak self] in
            self?.currentContentSize ?? Self.defaultContentSize
        }
        resizeHandle.onResizeStart = { [weak self] in
            self?.onResizeStart()
        }
        resizeHandle.onResize = { [weak self] proposedSize in
            self?.updateContentSize(to: proposedSize)
        }
        resizeHandle.onResizeEnd = { [weak self] in
            self?.onResizeEnd()
            self?.editorHoverTrackingView?.refreshHoverState()
        }
        resizeHandle.onDragStateChange = { [weak self] _ in
            self?.updateResizeHandleVisibility()
        }
        resizeHandle.onHoverChange = { [weak self] isHovered in
            self?.isResizeHandleHovered = isHovered
            self?.updateResizeHandleVisibility()
        }
        resizeHandle.visualInsets = NSEdgeInsets(
            top: Self.resizeHandleHitOutset + Self.resizeHandleEdgeInset,
            left: 0,
            bottom: Self.resizeHandleHitOutset + Self.resizeHandleEdgeInset,
            right: Self.resizeHandleHitOutset + Self.resizeHandleEdgeInset
        )
        self.resizeHandle = resizeHandle
        textView.gripExclusionSize = NSSize(width: Self.resizeHandleTextOverlap, height: Self.resizeHandleTextOverlap)
        textView.gripView = resizeHandle
        clipView.gripView = resizeHandle

        container.addSubview(contentContainer)
        contentContainer.addSubview(editorContainer)
        contentContainer.addSubview(footerContainer)
        contentContainer.addSubview(resizeHandle)
        editorContainer.addSubview(scrollView)
        footerContainer.addSubview(buttonHostingView)

        let initialSize = Self.lastUsedContentSize ?? Self.restoredContentSize ?? Self.defaultContentSize
        widthConstraint = container.widthAnchor.constraint(equalToConstant: initialSize.width)
        heightConstraint = container.heightAnchor.constraint(equalToConstant: initialSize.height)
        resizeHandleBottomConstraint = resizeHandle.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor, constant: Self.resizeHandleHitOutset)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.contentInsets.top),
            contentContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.contentInsets.left),
            contentContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.contentInsets.right),
            contentContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.contentInsets.bottom),

            editorContainer.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            editorContainer.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            editorContainer.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            editorContainer.bottomAnchor.constraint(equalTo: footerContainer.topAnchor, constant: -Self.contentSpacing),

            scrollView.topAnchor.constraint(equalTo: editorContainer.topAnchor, constant: 1),
            scrollView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor, constant: 1),
            scrollView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor, constant: -1),
            scrollView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor, constant: -1),

            footerContainer.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            footerContainer.heightAnchor.constraint(equalToConstant: Self.footerHeight),

            buttonHostingView.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            buttonHostingView.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor),

            resizeHandle.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor, constant: Self.resizeHandleHitOutset),
            resizeHandle.widthAnchor.constraint(equalToConstant: Self.resizeHandleSize),
            resizeHandle.heightAnchor.constraint(equalToConstant: Self.resizeHandleSize),

            widthConstraint,
            heightConstraint,
        ])

        resizeHandleBottomConstraint.isActive = true
        preferredContentSize = initialSize
        self.view = container
        applyEditorAttributesAndHighlighting()
        updateResizeHandleVisibility()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateContentSize(to: currentContentSize)
        resolveInitialResizeBehaviorIfNeeded()
        applyEditorAttributesAndHighlighting()
        editorHoverTrackingView?.refreshHoverState()
        updateResizeHandleVisibility()
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        resolveInitialResizeBehaviorIfNeeded()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancelAction()
            return
        }

        super.keyDown(with: event)
    }

    private func saveAction() {
        onSave(Self.compactJSON(textView.string))
        onDismiss()
    }

    private func cancelAction() {
        onDismiss()
    }

    private var currentContentSize: NSSize {
        NSSize(width: widthConstraint.constant, height: heightConstraint.constant)
    }

    private func updateContentSize(to proposedSize: NSSize) {
        resolveInitialResizeBehaviorIfNeeded()
        let clampedSize = clampedContentSize(for: proposedSize)
        guard clampedSize != currentContentSize else {
            return
        }

        widthConstraint.constant = clampedSize.width
        heightConstraint.constant = clampedSize.height
        preferredContentSize = clampedSize
        Self.lastUsedContentSize = clampedSize
        Self.persistContentSize(clampedSize)
        onResize(clampedSize)
    }

    private func clampedContentSize(for proposedSize: NSSize) -> NSSize {
        let visibleFrame = view.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 900)

        let maximumWidth = max(Self.minimumContentSize.width, min(visibleFrame.width * 0.75, 1000))
        let generalMaximumHeight = max(Self.minimumContentSize.height, min(visibleFrame.height * 0.7, 720))
        let maximumHeight = min(generalMaximumHeight, maximumContentHeight(for: visibleFrame))
        let minimumHeight = min(Self.minimumContentSize.height, maximumHeight)

        return NSSize(
            width: min(max(proposedSize.width, Self.minimumContentSize.width), maximumWidth),
            height: min(max(proposedSize.height, minimumHeight), maximumHeight)
        )
    }

    func configureResizeBehavior(relativeTo positioningRect: NSRect, of positioningView: NSView) {
        self.positioningRect = positioningRect
        self.positioningView = positioningView
        resolveInitialResizeBehaviorIfNeeded()
    }

    private func resolveInitialResizeBehaviorIfNeeded() {
        guard lockedResizeHandlePlacement == nil else {
            return
        }

        guard let popoverWindow = view.window,
              let positioningView,
              let anchorWindow = positioningView.window else {
            return
        }

        let resolvedPositioningRect = positioningRect.isEmpty ? positioningView.bounds : positioningRect
        let anchorRectInWindow = positioningView.convert(resolvedPositioningRect, to: nil)
        let anchorRectOnScreen = anchorWindow.convertToScreen(anchorRectInWindow)

        let placement: ResizeHandlePlacement
        if popoverWindow.frame.minY >= anchorRectOnScreen.maxY {
            placement = .topTrailing
        } else if popoverWindow.frame.maxY <= anchorRectOnScreen.minY {
            placement = .bottomTrailing
        } else {
            placement = popoverWindow.frame.midY >= anchorRectOnScreen.midY
                ? .topTrailing
                : .bottomTrailing
        }

        lockedResizeHandlePlacement = placement
        updateResizeHandlePlacement()
    }

    private func updateResizeHandlePlacement() {
        resizeHandle.verticalResizeDirection = ResizeHandlePlacement.bottomTrailing.verticalResizeDirection
        resizeHandle.drawsFromTop = false
        resizeHandleBottomConstraint.isActive = true
        resizeHandle.window?.invalidateCursorRects(for: resizeHandle)
        resizeHandle.needsDisplay = true
        view.layoutSubtreeIfNeeded()
    }

    private func updateResizeHandleVisibility() {
        let isVisible = isEditorHovered || isResizeHandleHovered || resizeHandle.isDragging
        resizeHandle.setGripVisible(isVisible)
        resizeHandle.window?.invalidateCursorRects(for: resizeHandle)
        if let gripClipView {
            gripClipView.window?.invalidateCursorRects(for: gripClipView)
        }
        textView.window?.invalidateCursorRects(for: textView)
        resizeHandle.refreshCursorState()
    }

    private func maximumContentHeight(for visibleFrame: NSRect) -> CGFloat {
        guard let lockedResizeHandlePlacement,
              let anchorRectOnScreen = anchorRectOnScreen() else {
            return max(Self.minimumContentSize.height, min(visibleFrame.height * 0.7, 720))
        }

        let currentWindowHeight = view.window?.frame.height ?? currentContentSize.height
        let chromeHeight = max(0, currentWindowHeight - currentContentSize.height)
        let verticalPadding: CGFloat = 8

        let availableWindowHeight: CGFloat
        switch lockedResizeHandlePlacement {
        case .topTrailing:
            availableWindowHeight = visibleFrame.maxY - anchorRectOnScreen.maxY - verticalPadding
        case .bottomTrailing:
            availableWindowHeight = anchorRectOnScreen.minY - visibleFrame.minY - verticalPadding
        }

        return max(Self.minimumContentSize.height, availableWindowHeight - chromeHeight)
    }

    private func anchorRectOnScreen() -> NSRect? {
        guard let positioningView,
              let anchorWindow = positioningView.window else {
            return nil
        }

        let resolvedPositioningRect = positioningRect.isEmpty ? positioningView.bounds : positioningRect
        let anchorRectInWindow = positioningView.convert(resolvedPositioningRect, to: nil)
        return anchorWindow.convertToScreen(anchorRectInWindow)
    }

    // MARK: - JSON Helpers

    private static func looksLikeJSON(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
               (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }

    private static func shouldHighlightAsJSON(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    static func prettyJSON(_ string: String) -> String {
        guard looksLikeJSON(string),
              let data = string.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: prettyData, encoding: .utf8) else {
            return string
        }
        return result
    }

    static func compactJSON(_ string: String) -> String {
        guard looksLikeJSON(string),
              let data = string.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let compactData = try? JSONSerialization.data(withJSONObject: jsonObject),
              let result = String(data: compactData, encoding: .utf8) else {
            return string
        }
        return result
    }

    private static var restoredContentSize: NSSize? {
        guard let storedWidth = UserDefaults.standard.object(forKey: contentWidthDefaultsKey) as? Double,
              let storedHeight = UserDefaults.standard.object(forKey: contentHeightDefaultsKey) as? Double,
              storedWidth >= Double(minimumContentSize.width),
              storedHeight >= Double(minimumContentSize.height) else {
            return nil
        }

        return NSSize(width: CGFloat(storedWidth), height: CGFloat(storedHeight))
    }

    private static func persistContentSize(_ size: NSSize) {
        UserDefaults.standard.set(Double(size.width), forKey: contentWidthDefaultsKey)
        UserDefaults.standard.set(Double(size.height), forKey: contentHeightDefaultsKey)
    }

    /// Re-applies base attributes and JSON highlighting. Passing `editedRange`
    /// restricts the pass to the affected lines (plus the preceding line, whose
    /// key/value colouring can depend on the edited one); `nil` runs the full
    /// document, which is only needed for the initial load.
    private func applyEditorAttributesAndHighlighting(editedRange: NSRange? = nil) {
        guard let textStorage = textView.textStorage else {
            return
        }

        let font = textView.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = Self.editorLineHeight
        paragraphStyle.maximumLineHeight = Self.editorLineHeight

        let appearance = textView.effectiveAppearance
        let theme = editorTheme(for: appearance)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: theme.textColour,
        ]
        let targetRange: NSRange
        if let editedRange {
            targetRange = Self.lineScopedHighlightRange(for: editedRange, in: textStorage.string as NSString)
        } else {
            targetRange = NSRange(location: 0, length: textStorage.length)
        }

        textStorage.beginEditing()
        if targetRange.length > 0 {
            textStorage.setAttributes(baseAttributes, range: targetRange)
            if Self.shouldHighlightAsJSON(textView.string) {
                applyJSONSyntaxHighlighting(
                    in: textStorage,
                    range: targetRange,
                    theme: theme,
                    keyStringColour: jsonKeyStringColour(for: appearance),
                    valueStringColour: jsonValueStringColour(for: appearance)
                )
            }
        }
        textStorage.endEditing()

        textView.typingAttributes = baseAttributes
    }

    private static func lineScopedHighlightRange(for editedRange: NSRange, in string: NSString) -> NSRange {
        let length = string.length
        let location = min(max(editedRange.location, 0), length)
        let clamped = NSRange(location: location, length: min(max(editedRange.length, 0), length - location))
        var lineRange = string.lineRange(for: clamped)
        if lineRange.location > 0 {
            let previousLine = string.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
            lineRange = NSUnionRange(previousLine, lineRange)
        }
        return lineRange
    }

    private func editorTheme(for appearance: NSAppearance) -> Theme {
        isDarkAppearance(appearance) ? .defaultDark : .defaultLight
    }

    private func jsonKeyStringColour(for appearance: NSAppearance) -> NSColor {
        if isDarkAppearance(appearance) {
            return NSColor(red: 0.88, green: 0.64, blue: 0.34, alpha: 1)
        } else {
            return NSColor(red: 0.72, green: 0.41, blue: 0.12, alpha: 1)
        }
    }

    private func jsonValueStringColour(for appearance: NSAppearance) -> NSColor {
        if isDarkAppearance(appearance) {
            return NSColor(red: 0.37, green: 0.74, blue: 0.50, alpha: 1)
        } else {
            return NSColor(red: 0.17, green: 0.56, blue: 0.35, alpha: 1)
        }
    }

    private func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Tokenises over the UTF-16 view with integer offsets so each token's
    /// NSRange is built in O(1), instead of walking from the string's start
    /// per token as `NSRange(_:in:)` on String.Index ranges does.
    private func applyJSONSyntaxHighlighting(
        in textStorage: NSTextStorage,
        range: NSRange,
        theme: Theme,
        keyStringColour: NSColor,
        valueStringColour: NSColor
    ) {
        let string = textStorage.string as NSString
        let end = min(range.location + range.length, string.length)
        var index = range.location

        while index < end {
            let character = string.character(at: index)

            if character == JSONScalar.quote {
                let endIndex = Self.endOfJSONString(startingAt: index, in: string)
                let nextCharacter = Self.nextNonWhitespaceCharacter(after: endIndex, in: string)
                let stringColour = nextCharacter == JSONScalar.colon ? keyStringColour : valueStringColour
                textStorage.addAttribute(.foregroundColor, value: stringColour, range: NSRange(location: index, length: endIndex - index))
                index = endIndex
                continue
            }

            if let endIndex = Self.endOfJSONNumber(startingAt: index, in: string) {
                textStorage.addAttribute(.foregroundColor, value: theme.numberColour, range: NSRange(location: index, length: endIndex - index))
                index = endIndex
                continue
            }

            if let endIndex = Self.endOfJSONLiteral(startingAt: index, in: string) {
                textStorage.addAttribute(.foregroundColor, value: theme.keywordColour, range: NSRange(location: index, length: endIndex - index))
                index = endIndex
                continue
            }

            if Self.isJSONPunctuation(character) {
                let punctuationColour = character == JSONScalar.colon ? theme.operatorColour : theme.symbolColour
                textStorage.addAttribute(.foregroundColor, value: punctuationColour, range: NSRange(location: index, length: 1))
                index += 1
                continue
            }

            index += 1
        }
    }

    private enum JSONScalar {
        static let quote: unichar = 0x22       // "
        static let backslash: unichar = 0x5C   // \
        static let colon: unichar = 0x3A       // :
        static let minus: unichar = 0x2D       // -
        static let plus: unichar = 0x2B        // +
        static let dot: unichar = 0x2E         // .
        static let zero: unichar = 0x30        // 0
        static let one: unichar = 0x31         // 1
        static let nine: unichar = 0x39        // 9
        static let lowercaseE: unichar = 0x65  // e
        static let uppercaseE: unichar = 0x45  // E
    }

    private static let jsonLiterals: [[unichar]] = ["true", "false", "null"].map { Array($0.utf16) }
    private static let jsonPunctuation: Set<unichar> = Set("{}[]:,".utf16)

    private static func endOfJSONString(startingAt startIndex: Int, in string: NSString) -> Int {
        var index = startIndex + 1
        var isEscaped = false

        while index < string.length {
            let character = string.character(at: index)
            if isEscaped {
                isEscaped = false
            } else if character == JSONScalar.backslash {
                isEscaped = true
            } else if character == JSONScalar.quote {
                return index + 1
            }
            index += 1
        }

        return string.length
    }

    private static func endOfJSONLiteral(startingAt startIndex: Int, in string: NSString) -> Int? {
        for literal in jsonLiterals {
            let endIndex = startIndex + literal.count
            guard endIndex <= string.length,
                  literal.indices.allSatisfy({ string.character(at: startIndex + $0) == literal[$0] }) else {
                continue
            }

            if endIndex < string.length, !isJSONLiteralBoundary(string.character(at: endIndex)) {
                return nil
            }
            return endIndex
        }

        return nil
    }

    private static func endOfJSONNumber(startingAt startIndex: Int, in string: NSString) -> Int? {
        var index = startIndex

        if string.character(at: index) == JSONScalar.minus {
            index += 1
            guard index < string.length else {
                return nil
            }
        }

        if string.character(at: index) == JSONScalar.zero {
            index += 1
        } else {
            guard isNonZeroDigit(string.character(at: index)) else {
                return nil
            }

            repeat {
                index += 1
            } while index < string.length && isDigit(string.character(at: index))
        }

        if index < string.length, string.character(at: index) == JSONScalar.dot {
            index += 1
            guard index < string.length, isDigit(string.character(at: index)) else {
                return nil
            }

            repeat {
                index += 1
            } while index < string.length && isDigit(string.character(at: index))
        }

        if index < string.length, (string.character(at: index) == JSONScalar.lowercaseE || string.character(at: index) == JSONScalar.uppercaseE) {
            index += 1
            guard index < string.length else {
                return nil
            }

            if string.character(at: index) == JSONScalar.plus || string.character(at: index) == JSONScalar.minus {
                index += 1
                guard index < string.length else {
                    return nil
                }
            }

            guard isDigit(string.character(at: index)) else {
                return nil
            }

            repeat {
                index += 1
            } while index < string.length && isDigit(string.character(at: index))
        }

        guard index == string.length || isJSONLiteralBoundary(string.character(at: index)) else {
            return nil
        }

        return index
    }

    private static func nextNonWhitespaceCharacter(after startIndex: Int, in string: NSString) -> unichar? {
        var index = startIndex
        while index < string.length {
            let character = string.character(at: index)
            if !isWhitespace(character) {
                return character
            }
            index += 1
        }
        return nil
    }

    private static func isJSONPunctuation(_ character: unichar) -> Bool {
        jsonPunctuation.contains(character)
    }

    private static func isJSONLiteralBoundary(_ character: unichar) -> Bool {
        isWhitespace(character) || isJSONPunctuation(character)
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isDigit(_ character: unichar) -> Bool {
        character >= JSONScalar.zero && character <= JSONScalar.nine
    }

    private static func isNonZeroDigit(_ character: unichar) -> Bool {
        character >= JSONScalar.one && character <= JSONScalar.nine
    }
}

private final class QuickLookEditorContainerView: QuickLookHoverTrackingView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        guard let layer else {
            return
        }

        layer.cornerRadius = QuickLookViewController.editorCornerRadius
        layer.masksToBounds = false
        layer.backgroundColor = QuickLookViewController.editorBackgroundColor.cgColor
        layer.shadowColor = NSColor.black.withAlphaComponent(0.10).cgColor
        layer.shadowOpacity = 1.0
        layer.shadowRadius = 1
        layer.shadowOffset = .zero
    }
}

private final class QuickLookGripAwareClipView: NSClipView {
    var gripExclusionSize: NSSize = .zero
    weak var gripView: QuickLookResizeHandleView?
    private var isForwardingGripDrag = false
    private var trackingArea: NSTrackingArea?
    private var isGripCursorPushed = false

    isolated deinit {
        releaseGripCursorIfNeeded()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isPointInGripZone(point) {
            return self
        }

        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        guard let gripRect = gripRect(), !gripRect.isEmpty else {
            return
        }

        addCursorRect(gripRect, cursor: gripCursor())
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isPointInGripZone(point) else {
            releaseGripCursorIfNeeded()
            super.cursorUpdate(with: event)
            return
        }

        holdGripCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isPointInGripZone(point) else {
            releaseGripCursorIfNeeded()
            super.mouseMoved(with: event)
            return
        }

        holdGripCursor()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if isPointInGripZone(point) {
            holdGripCursor()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        releaseGripCursorIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isPointInGripZone(point),
              let gripView else {
            super.mouseDown(with: event)
            return
        }

        isForwardingGripDrag = true
        gripView.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isForwardingGripDrag,
              let gripView else {
            super.mouseDragged(with: event)
            return
        }

        gripView.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isForwardingGripDrag,
              let gripView else {
            super.mouseUp(with: event)
            return
        }

        isForwardingGripDrag = false
        gripView.mouseUp(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        releaseGripCursorIfNeeded()
        window?.invalidateCursorRects(for: self)
    }

    private func isPointInGripZone(_ point: NSPoint) -> Bool {
        guard let gripRect = gripRect() else {
            return false
        }

        return gripRect.contains(point)
    }

    private func gripRect() -> NSRect? {
        guard gripExclusionSize.width > 0,
              gripExclusionSize.height > 0 else {
            return nil
        }

        let rect = NSRect(
            x: bounds.maxX - gripExclusionSize.width,
            y: bounds.maxY - gripExclusionSize.height,
            width: gripExclusionSize.width,
            height: gripExclusionSize.height
        ).intersection(bounds)

        return rect.isEmpty ? nil : rect
    }

    private func gripCursor() -> NSCursor {
        .frameResize(position: .bottomTrailing(relativeTo: userInterfaceLayoutDirection), directions: .all)
    }

    private func holdGripCursor() {
        guard !isGripCursorPushed else {
            gripCursor().set()
            return
        }

        gripCursor().push()
        isGripCursorPushed = true
    }

    private func releaseGripCursorIfNeeded() {
        guard isGripCursorPushed else {
            return
        }

        NSCursor.pop()
        isGripCursorPushed = false
    }
}

private final class QuickLookGripAwareTextView: NSTextView {
    var gripExclusionSize: NSSize = .zero
    weak var gripView: QuickLookResizeHandleView?
    private var isForwardingGripDrag = false

    override func resetCursorRects() {
        guard let exclusionRect = gripExclusionRect(), !exclusionRect.isEmpty else {
            super.resetCursorRects()
            return
        }

        for rect in cursorRects(excluding: exclusionRect) where !rect.isEmpty {
            addCursorRect(rect, cursor: .iBeam)
        }
        addCursorRect(exclusionRect, cursor: gripCursor())
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard !isPointInGripExclusion(point) else {
            gripCursor().set()
            return
        }

        super.cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard !isPointInGripExclusion(point) else {
            gripCursor().set()
            return
        }

        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isPointInGripExclusion(point),
              let gripView else {
            super.mouseDown(with: event)
            return
        }

        isForwardingGripDrag = true
        gripView.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isForwardingGripDrag,
              let gripView else {
            super.mouseDragged(with: event)
            return
        }

        gripView.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isForwardingGripDrag,
              let gripView else {
            super.mouseUp(with: event)
            return
        }

        isForwardingGripDrag = false
        gripView.mouseUp(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    private func isPointInGripExclusion(_ point: NSPoint) -> Bool {
        guard let exclusionRect = gripExclusionRect() else {
            return false
        }

        return exclusionRect.contains(point)
    }

    private func gripExclusionRect() -> NSRect? {
        guard gripExclusionSize.width > 0,
              gripExclusionSize.height > 0 else {
            return nil
        }

        let visibleGripRect = NSRect(
            x: visibleRect.maxX - gripExclusionSize.width,
            y: visibleRect.maxY - gripExclusionSize.height,
            width: gripExclusionSize.width,
            height: gripExclusionSize.height
        )
        let exclusionRect = visibleGripRect.intersection(visibleRect)
        let boundedRect = exclusionRect.intersection(bounds)
        return boundedRect.isEmpty ? nil : boundedRect
    }

    private func cursorRects(excluding excludedRect: NSRect) -> [NSRect] {
        let boundedRect = excludedRect.intersection(bounds)
        guard !boundedRect.isEmpty else {
            return [bounds]
        }

        return [
            NSRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: boundedRect.minY - bounds.minY
            ),
            NSRect(
                x: bounds.minX,
                y: boundedRect.maxY,
                width: bounds.width,
                height: bounds.maxY - boundedRect.maxY
            ),
            NSRect(
                x: bounds.minX,
                y: boundedRect.minY,
                width: boundedRect.minX - bounds.minX,
                height: boundedRect.height
            ),
            NSRect(
                x: boundedRect.maxX,
                y: boundedRect.minY,
                width: bounds.maxX - boundedRect.maxX,
                height: boundedRect.height
            ),
        ].filter { !$0.isEmpty }
    }

    private func gripCursor() -> NSCursor {
        .frameResize(position: .bottomTrailing(relativeTo: userInterfaceLayoutDirection), directions: .all)
    }
}

private enum ResizeHandlePlacement {
    case topTrailing
    case bottomTrailing

    var verticalResizeDirection: CGFloat {
        switch self {
        case .topTrailing:
            return 1
        case .bottomTrailing:
            return -1
        }
    }
}

private final class QuickLookResizeHandleView: NSView {
    var currentSize: (() -> NSSize)?
    var onResizeStart: (() -> Void)?
    var onResize: ((NSSize) -> Void)?
    var onResizeEnd: (() -> Void)?
    var onDragStateChange: ((Bool) -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var verticalResizeDirection: CGFloat = -1
    var drawsFromTop = false {
        didSet {
            updateHandleLayer(animated: false)
        }
    }

    private let shapeLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private var dragStartLocation: NSPoint?
    private var dragStartSize: NSSize = .zero
    private var isGripVisible = false
    private var isResizeCursorPushed = false
    private var lastLayoutBounds: CGRect = .zero
    private(set) var isDragging = false
    var visualInsets = NSEdgeInsetsZero {
        didSet {
            updateHandleLayer(animated: false)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(shapeLayer)
        shapeLayer.strokeColor = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    isolated deinit {
        releaseResizeCursorIfNeeded()
    }

    override var isOpaque: Bool {
        false
    }

    override func layout() {
        super.layout()
        guard bounds != lastLayoutBounds else { return }
        lastLayoutBounds = bounds
        updateHandleLayer(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: resizeCursor())
    }

    override func cursorUpdate(with event: NSEvent) {
        holdResizeCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        holdResizeCursor()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        holdResizeCursor()
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        releaseResizeCursorIfNeeded()
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = screenLocation(for: event)
        dragStartSize = currentSize?() ?? .zero
        isDragging = true
        updateHandleLayer(animated: true)
        onDragStateChange?(true)
        onResizeStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartLocation,
              let currentLocation = screenLocation(for: event) else {
            return
        }

        let proposedSize = NSSize(
            width: dragStartSize.width + (currentLocation.x - dragStartLocation.x),
            height: dragStartSize.height + (verticalResizeDirection * (currentLocation.y - dragStartLocation.y))
        )

        onResize?(proposedSize)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        isDragging = false
        updateHandleLayer(animated: true)
        onDragStateChange?(false)
        onResizeEnd?()
        refreshHoverState()
    }

    private func refreshHoverState() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hovered = bounds.contains(point)
        if !hovered {
            onHoverChange?(false)
        }
    }

    func setGripVisible(_ visible: Bool) {
        guard isGripVisible != visible else {
            return
        }

        isGripVisible = visible
        updateHandleLayer(animated: true)
    }

    func refreshCursorState() {
        guard let window else {
            return
        }

        let mouseLocationInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(mouseLocationInView) {
            holdResizeCursor()
        } else {
            releaseResizeCursorIfNeeded()
        }
    }

    private func screenLocation(for event: NSEvent) -> NSPoint? {
        guard let window else {
            return nil
        }

        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func resizeCursor() -> NSCursor {
        let position: NSCursor.FrameResizePosition = drawsFromTop
            ? .topTrailing(relativeTo: userInterfaceLayoutDirection)
            : .bottomTrailing(relativeTo: userInterfaceLayoutDirection)
        return .frameResize(position: position, directions: .all)
    }

    private func holdResizeCursor() {
        guard !isResizeCursorPushed else {
            resizeCursor().set()
            return
        }

        resizeCursor().push()
        isResizeCursorPushed = true
    }

    private func releaseResizeCursorIfNeeded() {
        guard isResizeCursorPushed else {
            return
        }

        NSCursor.pop()
        isResizeCursorPushed = false
    }

    private func updateHandleLayer(animated: Bool) {
        let style = resizeHandleStyle
        let displayPath = handleBlobPath(for: style, middleScale: isDragging ? 0.45 : 1)

        CATransaction.begin()
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            CATransaction.setAnimationDuration(0.16)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }

        shapeLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        shapeLayer.frame = bounds
        shapeLayer.path = displayPath
        shapeLayer.fillColor = NSColor.systemGray.withAlphaComponent(style.alpha).cgColor
        shapeLayer.opacity = (isGripVisible || isDragging) ? 1 : 0
        shapeLayer.transform = CATransform3DIdentity

        CATransaction.commit()
    }

    private func handleBlobPath(for style: ResizeHandleStyle, middleScale: CGFloat) -> CGPath {
        let radius = max(3, style.cornerRadius - style.curveInset)
        let center = CGPoint(
            x: bounds.maxX - visualInsets.right - style.cornerRadius,
            y: drawsFromTop
                ? bounds.maxY - visualInsets.top - style.cornerRadius
                : bounds.minY + visualInsets.bottom + style.cornerRadius
        )
        let startAngle = (drawsFromTop ? style.startAngle : -style.startAngle) * .pi / 180
        let endAngle = (drawsFromTop ? style.endAngle : -style.endAngle) * .pi / 180
        let path = CGMutablePath()
        let sampleCount = 20

        for index in 0...sampleCount {
            let progress = CGFloat(index) / CGFloat(sampleCount)
            let angle = startAngle + ((endAngle - startAngle) * progress)
            let point = CGPoint(
                x: center.x + (radius * cos(angle)),
                y: center.y + (radius * sin(angle))
            )
            let topProgress = drawsFromTop ? progress : (1 - progress)
            let squeezeWeight = sin(.pi / 2 * topProgress)
            let thicknessScale = 1 - ((1 - middleScale) * squeezeWeight * squeezeWeight)
            let circleRadius = max(0.8, (style.strokeWidth * thicknessScale) / 2)
            let circleRect = CGRect(
                x: point.x - circleRadius,
                y: point.y - circleRadius,
                width: circleRadius * 2,
                height: circleRadius * 2
            )
            path.addEllipse(in: circleRect)
        }

        return path
    }

    private var resizeHandleStyle: ResizeHandleStyle {
        if #available(macOS 26, *) {
            return ResizeHandleStyle(
                strokeWidth: 3.7,
                alpha: 0.88,
                cornerRadius: QuickLookViewController.editorCornerRadius - QuickLookViewController.resizeHandleEdgeInset,
                curveInset: 2,
                startAngle: 6,
                endAngle: 84
            )
        } else {
            return ResizeHandleStyle(
                strokeWidth: 2.75,
                alpha: 0.76,
                cornerRadius: 10,
                curveInset: 2,
                startAngle: 12,
                endAngle: 72
            )
        }
    }
}

private struct ResizeHandleStyle {
    let strokeWidth: CGFloat
    let alpha: CGFloat
    let cornerRadius: CGFloat
    let curveInset: CGFloat
    let startAngle: CGFloat
    let endAngle: CGFloat
}

private class QuickLookHoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        refreshHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(false)
    }

    func refreshHoverState() {
        guard let window else {
            setHovered(false)
            return
        }

        let mouseLocationInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(mouseLocationInView))
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else {
            return
        }

        isHovered = hovered
        onHoverChange?(hovered)
    }
}

extension QuickLookViewController: NSTextViewDelegate {
    nonisolated func textDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            let editedRange = pendingEditedRange
            pendingEditedRange = nil
            applyEditorAttributesAndHighlighting(editedRange: editedRange)
            buttonState.isSaveEnabled = allowsSaveWithoutTextChanges || textView.string != displayedInitialContent
        }
    }
}

extension QuickLookViewController: NSTextStorageDelegate {
    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            pendingEditedRange = pendingEditedRange.map { NSUnionRange($0, editedRange) } ?? editedRange
        }
    }
}

// MARK: - Button Bar

@Observable
@MainActor
private class QuickLookButtonState {
    var isSaveEnabled = false
}

private struct QuickLookButtonBar: View {
    private static let buttonVerticalPadding: CGFloat = 6

    let state: QuickLookButtonState
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onCancel) {
                HStack(spacing: 4) {
                    Text("Cancel")
                    Text("ESC")
                        .opacity(0.6)
                }
            }
            .buttonStyle(QuickLookSecondaryButtonStyle(verticalPadding: Self.buttonVerticalPadding))

            Button(action: onSave) {
                HStack(spacing: 4) {
                    Text("Save")
                    Text("⌘⏎")
                        .opacity(0.6)
                }
            }
            .buttonStyle(QuickLookPrimaryButtonStyle(verticalPadding: Self.buttonVerticalPadding))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!state.isSaveEnabled)
        }
    }
}

private struct QuickLookPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let verticalPadding: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(isEnabled ? Color(.textBackgroundColor) : .secondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? Color.primaryButton : Color.gray.opacity(0.25))
                    .opacity(isHovering ? 0.8 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
    }
}

private struct QuickLookSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let verticalPadding: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, verticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        (colorScheme == .dark ? Color.white : Color.black)
                            .opacity(isHovering ? 0.15 : 0.08)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
    }
}
