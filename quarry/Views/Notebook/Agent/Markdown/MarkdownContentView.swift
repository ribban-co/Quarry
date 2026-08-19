import AppKit

final class MarkdownContentView: NSView {

    private let stackView: NSStackView
    private var currentBlocks: [MarkdownBlock] = []
    private var blockViews: [NSView] = []
    private var parserState = MarkdownBlockParser.StreamingState()

    override init(frame: NSRect) {
        stackView = NSStackView()
        super.init(frame: frame)
        setupStack()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(content: String) {
        let newBlocks = MarkdownBlockParser.parseIncremental(content, state: &parserState)

        guard !newBlocks.isEmpty else {
            removeAllBlockViews()
            currentBlocks = []
            return
        }

        let divergenceIndex = zip(currentBlocks, newBlocks)
            .prefix(while: { $0 == $1 })
            .count

        if divergenceIndex == newBlocks.count - 1
            && newBlocks.count == currentBlocks.count
            && divergenceIndex < blockViews.count
            && sameBlockType(currentBlocks[divergenceIndex], newBlocks[divergenceIndex])
        {
            updateBlockView(blockViews[divergenceIndex], with: newBlocks[divergenceIndex])
            currentBlocks = newBlocks
            invalidateIntrinsicContentSize()
            return
        }

        if divergenceIndex == currentBlocks.count && newBlocks.count > currentBlocks.count {
            for i in divergenceIndex..<newBlocks.count {
                let view = makeBlockView(for: newBlocks[i])
                addBlockView(view)
            }
            currentBlocks = newBlocks
            invalidateIntrinsicContentSize()
            return
        }

        while blockViews.count > divergenceIndex {
            let view = blockViews.removeLast()
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for i in divergenceIndex..<newBlocks.count {
            let view = makeBlockView(for: newBlocks[i])
            addBlockView(view)
        }

        currentBlocks = newBlocks
        invalidateIntrinsicContentSize()
    }

    var plainText: String {
        currentBlocks.map { block -> String in
            switch block {
            case .paragraph(let text), .heading(_, let text), .blockquote(let text), .thinkingBlock(let text, _, _):
                return text
            case .codeBlock(let code, _):
                return code
            case .unorderedList(let items), .orderedList(let items):
                return items.map(\.text).joined(separator: "\n")
            case .table(let headers, let rows):
                let headerRow = headers.joined(separator: "\t")
                let dataRows = rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
                return headerRow + "\n" + dataRows
            case .horizontalRule:
                return "---"
            case .toolCallGroup(let calls):
                return calls.map(\.displayText).joined(separator: "\n")
            }
        }.joined(separator: "\n\n")
    }

    // MARK: - Setup

    private func setupStack() {
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // MARK: - Block View Factory

    private func makeBlockView(for block: MarkdownBlock) -> NSView {
        switch block {
        case .paragraph(let text):
            return MarkdownTextBlockView(text: text, style: .paragraph)

        case .heading(let level, let text):
            return MarkdownTextBlockView(text: text, style: .heading(level: level))

        case .codeBlock(let code, let language):
            return CodeBlockView(code: code, language: language)

        case .unorderedList(let items):
            return MarkdownListView(items: items, ordered: false)

        case .orderedList(let items):
            return MarkdownListView(items: items, ordered: true)

        case .blockquote(let text):
            return BlockquoteView(text: text)

        case .table(let headers, let rows):
            return MarkdownTableView(headers: headers, rows: rows)

        case .horizontalRule:
            return HorizontalRuleView()

        case .thinkingBlock(let text, let duration, let toolCalls):
            let view = ThinkingBlockView(text: text, finishedDuration: duration ?? 0)
            for (i, call) in toolCalls.enumerated() {
                view.addToolCall(id: "persisted-\(i)", name: call.name, displayText: call.displayText, isComplete: true)
            }
            return view

        case .toolCallGroup(let calls):
            let view = ThinkingBlockView(text: "", finishedDuration: 0)
            for (i, call) in calls.enumerated() {
                view.addToolCall(id: "persisted-\(i)", name: call.name, displayText: call.displayText, isComplete: true)
            }
            return view
        }
    }

    private func updateBlockView(_ view: NSView, with block: MarkdownBlock) {
        switch block {
        case .paragraph(let text):
            (view as? MarkdownTextBlockView)?.update(text: text, style: .paragraph)

        case .heading(let level, let text):
            (view as? MarkdownTextBlockView)?.update(text: text, style: .heading(level: level))

        case .codeBlock(let code, let language):
            (view as? CodeBlockView)?.update(code: code, language: language)

        case .unorderedList(let items):
            (view as? MarkdownListView)?.update(items: items, ordered: false)

        case .orderedList(let items):
            (view as? MarkdownListView)?.update(items: items, ordered: true)

        case .blockquote(let text):
            (view as? BlockquoteView)?.update(text: text)

        case .table(let headers, let rows):
            (view as? MarkdownTableView)?.update(headers: headers, rows: rows)

        case .thinkingBlock(let text, _, _):
            (view as? ThinkingBlockView)?.update(text: text)

        case .horizontalRule:
            break

        case .toolCallGroup:
            break
        }
    }

    // MARK: - Helpers

    private func addBlockView(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(view)
        view.leadingAnchor.constraint(equalTo: stackView.leadingAnchor).isActive = true
        view.trailingAnchor.constraint(equalTo: stackView.trailingAnchor).isActive = true
        blockViews.append(view)
    }

    private func sameBlockType(_ a: MarkdownBlock, _ b: MarkdownBlock) -> Bool {
        switch (a, b) {
        case (.paragraph, .paragraph),
             (.heading, .heading),
             (.codeBlock, .codeBlock),
             (.unorderedList, .unorderedList),
             (.orderedList, .orderedList),
             (.blockquote, .blockquote),
             (.table, .table),
             (.horizontalRule, .horizontalRule),
             (.thinkingBlock, .thinkingBlock),
             (.toolCallGroup, .toolCallGroup):
            return true
        default:
            return false
        }
    }

    private func removeAllBlockViews() {
        for view in blockViews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        blockViews.removeAll()
    }
}
