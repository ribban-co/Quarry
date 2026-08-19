import AppKit

@MainActor
protocol TableCellEditorOwner: AnyObject {
    func tableCellEditorDidCommit(_ editor: TableCellEditor, context: TableCellEditor.Context, value: String)
    func tableCellEditorDidCancel(_ editor: TableCellEditor, context: TableCellEditor.Context)
    func tableCellEditorDidRequestNavigation(_ editor: TableCellEditor, context: TableCellEditor.Context, direction: TableCellEditor.NavigationDirection)
}

@MainActor
final class TableCellEditorTextField: NSTextField {
    weak var editor: TableCellEditor?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func cancelOperation(_ sender: Any?) {
        editor?.cancelEditing()
    }
}

final class TableCellEditorFieldCell: NSTextFieldCell {
    private let horizontalInset: CGFloat = 8
    private let topInset: CGFloat = 6
    private let bottomInset: CGFloat = 5

    override init(textCell string: String) {
        super.init(textCell: string)
        setupCell()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }

    private func setupCell() {
        lineBreakMode = .byClipping
        wraps = false
        isScrollable = true
        usesSingleLineMode = true
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = rect
        titleRect.origin.x += horizontalInset
        titleRect.origin.y += topInset
        titleRect.size.width = max(0, rect.width - horizontalInset * 2)
        titleRect.size.height = max(0, rect.height - topInset - bottomInset)
        return titleRect
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

@MainActor
final class TableCellEditor: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
    struct Context {
        let row: Int
        let column: Int
        let columnName: String
        let dataType: String
        let originalValue: String
        let isReadOnly: Bool
    }

    enum NavigationDirection {
        case next
        case previous
        case down
        case up
    }

    weak var owner: TableCellEditorOwner?

    private let textField = TableCellEditorTextField(frame: .zero)
    private weak var tableView: CustomTableView?
    private var context: Context?
    private var isClosing = false

    override init() {
        super.init()

        textField.editor = self
        textField.configureForTableCell()
        textField.isSelectable = true
        textField.isEditable = true
        textField.delegate = self
        textField.cell = TableCellEditorFieldCell()
        textField.font = NSFont.preferredFont(forTextStyle: .body)
        textField.translatesAutoresizingMaskIntoConstraints = true
    }

    func beginEditing(
        in tableView: CustomTableView,
        frame: NSRect,
        context: Context,
        value: String
    ) {
        cancelEditing()

        self.tableView = tableView
        self.context = context

        textField.frame = frame
        textField.stringValue = value
        textField.isEditable = !context.isReadOnly
        textField.isSelectable = true
        textField.backgroundColor = .clear
        textField.drawsBackground = false

        tableView.addSubview(textField)
        tableView.window?.makeFirstResponder(textField)
        normalizeFieldEditorSelection()
    }

    func cancelEditing() {
        guard let context else {
            textField.removeFromSuperview()
            return
        }

        isClosing = true
        textField.abortEditing()
        textField.window?.makeFirstResponder(tableView)
        textField.removeFromSuperview()
        isClosing = false

        self.context = nil
        owner?.tableCellEditorDidCancel(self, context: context)
    }

    func commitEditing() {
        guard let context else { return }

        isClosing = true
        textField.window?.makeFirstResponder(tableView)
        textField.removeFromSuperview()
        isClosing = false

        self.context = nil
        owner?.tableCellEditorDidCommit(self, context: context, value: textField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertTab(_:)):
            commitAndNavigate(.next)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            commitAndNavigate(.previous)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            commitAndNavigate(.down)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelEditing()
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isClosing, context != nil else { return }
        commitEditing()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let context, context.isReadOnly,
              let editor = textField.window?.fieldEditor(true, for: textField) as? NSTextView else {
            return
        }
        editor.delegate = self
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        !(context?.isReadOnly ?? true)
    }

    private func commitAndNavigate(_ direction: NavigationDirection) {
        guard let context else { return }
        commitEditing()
        owner?.tableCellEditorDidRequestNavigation(self, context: context, direction: direction)
    }

    private func normalizeFieldEditorSelection() {
        guard let editor = textField.window?.fieldEditor(true, for: textField) as? NSTextView else {
            return
        }

        if context?.isReadOnly == true {
            editor.delegate = self
        }

        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = false
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: textField.bounds.height)
        editor.textContainerInset = .zero

        if let scrollView = editor.enclosingScrollView {
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.borderType = .noBorder
        }

        if let textContainer = editor.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = true
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: textField.bounds.height)
            textContainer.lineFragmentPadding = 0
        }

        let insertionLocation = textField.stringValue.utf16.count
        editor.setSelectedRange(NSRange(location: insertionLocation, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
    }
}
