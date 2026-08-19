import Foundation

struct ListItem: Equatable {
    let text: String
    let isTask: Bool
    let isChecked: Bool
}

struct ToolCallInfo: Equatable {
    let name: String
    let displayText: String
}

enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case codeBlock(code: String, language: String)
    case unorderedList(items: [ListItem])
    case orderedList(items: [ListItem])
    case blockquote(String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
    case thinkingBlock(String, duration: Int?, toolCalls: [ToolCallInfo])
    case toolCallGroup(calls: [ToolCallInfo])
}

@MainActor
enum MarkdownBlockParser {

    private enum State {
        case idle
        case inCodeBlock(language: String, lines: [String])
        case inThinkingBlock(lines: [String], duration: Int?)
    }

    /// Incremental parse cache for streaming content. Everything before
    /// `stablePrefix.count` characters has been parsed into `stableBlocks` and is
    /// guaranteed not to change as long as new content only appends.
    struct StreamingState {
        fileprivate var stablePrefix: String = ""
        fileprivate var stableBlocks: [MarkdownBlock] = []

        init() {}
    }

    static func parse(_ text: String) -> [MarkdownBlock] {
        mergeToolCallsIntoThinking(parseBlocks(text).blocks)
    }

    /// Parses streaming content incrementally: blocks in the cached stable prefix
    /// are reused and only the trailing, still-mutating portion is re-parsed.
    /// Produces exactly the same result as `parse(_:)`; falls back to a full
    /// parse whenever `text` is not an append to the previously seen content.
    static func parseIncremental(_ text: String, state: inout StreamingState) -> [MarkdownBlock] {
        if !text.hasPrefix(state.stablePrefix) {
            state = StreamingState()
        }
        let tail = String(text.dropFirst(state.stablePrefix.count))
        let (tailBlocks, boundary) = parseBlocks(tail)
        let result = mergeToolCallsIntoThinking(state.stableBlocks + tailBlocks)
        // Carriage returns make character offsets ambiguous ("\r\n" is one
        // Character but splits as two lines), so don't advance the cache then.
        if let boundary, !tail.unicodeScalars.contains("\r") {
            state.stablePrefix += tail.prefix(boundary.offset)
            state.stableBlocks += tailBlocks[0..<boundary.blockCount]
        }
        #if DEBUG
        assert(result == parse(text), "Incremental markdown parse diverged from full parse")
        #endif
        return result
    }

    /// Parses `text` into blocks without the tool-call merge pass. Also returns
    /// the last safe boundary: a character offset just past a newline-terminated
    /// blank line where the parser was in the idle state with all buffers
    /// flushed, and where the blocks emitted so far can no longer change (the
    /// last block is not a tool-call group, which later lines could extend).
    private static func parseBlocks(_ text: String) -> (blocks: [MarkdownBlock], stableBoundary: (offset: Int, blockCount: Int)?) {
        var blocks: [MarkdownBlock] = []
        var stableBoundary: (offset: Int, blockCount: Int)?
        var lineStart = 0
        var state = State.idle
        var paragraphBuffer: [String] = []
        var listBuffer: [ListItem] = []
        var listIsOrdered = false
        var tableHeaders: [String] = []
        var tableRows: [[String]] = []
        var inTable = false

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            blocks.append(.paragraph(paragraphBuffer.joined(separator: "\n")))
            paragraphBuffer.removeAll()
        }

        func flushList() {
            guard !listBuffer.isEmpty else { return }
            blocks.append(listIsOrdered ? .orderedList(items: listBuffer) : .unorderedList(items: listBuffer))
            listBuffer.removeAll()
        }

        func flushTable() {
            guard inTable else { return }
            blocks.append(.table(headers: tableHeaders, rows: tableRows))
            tableHeaders = []
            tableRows = []
            inTable = false
        }

        func flushAll() {
            flushParagraph()
            flushList()
            flushTable()
        }

        let lines = text.components(separatedBy: "\n")

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            defer { lineStart += line.count + 1 }

            switch state {
            case .idle:
                if trimmed.hasPrefix("```") {
                    flushAll()
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    state = .inCodeBlock(language: lang, lines: [])
                    continue
                }

                if trimmed.hasPrefix("<thinking") && trimmed.hasSuffix(">") {
                    flushAll()
                    var duration: Int?
                    if let dStart = trimmed.range(of: "duration=\""),
                       let dEnd = trimmed[dStart.upperBound...].firstIndex(of: "\"") {
                        duration = Int(trimmed[dStart.upperBound..<dEnd])
                    }
                    state = .inThinkingBlock(lines: [], duration: duration)
                    continue
                }

                if let toolCallInfo = parseToolCallTag(trimmed) {
                    flushAll()
                    if case .toolCallGroup(let existing) = blocks.last {
                        blocks[blocks.count - 1] = .toolCallGroup(calls: existing + [toolCallInfo])
                    } else {
                        blocks.append(.toolCallGroup(calls: [toolCallInfo]))
                    }
                    continue
                }

                if trimmed.isEmpty {
                    flushAll()
                    // Safe boundary: newline-terminated blank line, idle state,
                    // buffers flushed, and no trailing block that later lines
                    // could still extend.
                    if lineIndex < lines.count - 1 {
                        if case .toolCallGroup = blocks.last {} else {
                            stableBoundary = (offset: lineStart + line.count + 1, blockCount: blocks.count)
                        }
                    }
                    continue
                }

                if let heading = parseHeading(trimmed) {
                    flushAll()
                    blocks.append(heading)
                    continue
                }

                if isHorizontalRule(trimmed) {
                    flushAll()
                    blocks.append(.horizontalRule)
                    continue
                }

                if trimmed.hasPrefix(">") {
                    flushAll()
                    let content = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : String(trimmed.dropFirst(1))
                    blocks.append(.blockquote(content))
                    continue
                }

                if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                    flushParagraph()
                    flushList()
                    let cells = parseTableRow(trimmed)
                    if !inTable {
                        tableHeaders = cells
                        inTable = true
                    } else if isSeparatorRow(trimmed) {
                        // skip
                    } else {
                        tableRows.append(cells)
                    }
                    continue
                } else if inTable {
                    flushTable()
                }

                if let taskItem = parseTaskListItem(trimmed) {
                    flushParagraph()
                    flushTable()
                    if !listBuffer.isEmpty && listIsOrdered {
                        let last = listBuffer.removeLast()
                        let checkbox = taskItem.isChecked ? "\u{2611} " : "\u{2610} "
                        let newText = last.text.isEmpty ? checkbox + taskItem.text : last.text + "\n" + checkbox + taskItem.text
                        listBuffer.append(ListItem(text: newText, isTask: last.isTask, isChecked: last.isChecked))
                        continue
                    }
                    listIsOrdered = false
                    listBuffer.append(taskItem)
                    continue
                }

                if let ulText = parseUnorderedListItem(trimmed) {
                    flushParagraph()
                    flushTable()
                    if !listBuffer.isEmpty && listIsOrdered {
                        let last = listBuffer.removeLast()
                        let newText = last.text.isEmpty ? "\u{2022} " + ulText : last.text + "\n\u{2022} " + ulText
                        listBuffer.append(ListItem(text: newText, isTask: last.isTask, isChecked: last.isChecked))
                        continue
                    }
                    listIsOrdered = false
                    listBuffer.append(ListItem(text: ulText, isTask: false, isChecked: false))
                    continue
                }

                if let olText = parseOrderedListItem(trimmed) {
                    flushParagraph()
                    flushTable()
                    if !listBuffer.isEmpty && !listIsOrdered { flushList() }
                    listIsOrdered = true
                    listBuffer.append(ListItem(text: olText, isTask: false, isChecked: false))
                    continue
                }

                if !listBuffer.isEmpty {
                    let last = listBuffer.removeLast()
                    let newText = last.text.isEmpty ? trimmed : last.text + "\n" + trimmed
                    listBuffer.append(ListItem(text: newText, isTask: last.isTask, isChecked: last.isChecked))
                    continue
                }

                flushList()
                flushTable()
                paragraphBuffer.append(trimmed)

            case .inCodeBlock(let language, var codeLines):
                if trimmed.hasPrefix("```") {
                    blocks.append(.codeBlock(code: codeLines.joined(separator: "\n"), language: language))
                    state = .idle
                } else {
                    codeLines.append(line)
                    state = .inCodeBlock(language: language, lines: codeLines)
                }

            case .inThinkingBlock(var thinkingLines, let duration):
                if trimmed == "</thinking>" {
                    blocks.append(.thinkingBlock(thinkingLines.joined(separator: "\n"), duration: duration, toolCalls: []))
                    state = .idle
                } else {
                    thinkingLines.append(line)
                    state = .inThinkingBlock(lines: thinkingLines, duration: duration)
                }
            }
        }

        switch state {
        case .idle:
            flushAll()
        case .inCodeBlock(let language, let codeLines):
            blocks.append(.codeBlock(code: codeLines.joined(separator: "\n"), language: language))
        case .inThinkingBlock(let thinkingLines, let duration):
            blocks.append(.thinkingBlock(thinkingLines.joined(separator: "\n"), duration: duration, toolCalls: []))
        }

        return (blocks, stableBoundary)
    }

    private static func mergeToolCallsIntoThinking(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        var merged: [MarkdownBlock] = []
        var i = 0
        while i < blocks.count {
            if case .thinkingBlock(let text, let duration, var toolCalls) = blocks[i] {
                while i + 1 < blocks.count, case .toolCallGroup(let calls) = blocks[i + 1] {
                    toolCalls += calls
                    i += 1
                }
                merged.append(.thinkingBlock(text, duration: duration, toolCalls: toolCalls))
            } else {
                merged.append(blocks[i])
            }
            i += 1
        }
        return merged
    }

    // MARK: - Line Parsers

    private static func parseHeading(_ trimmed: String) -> MarkdownBlock? {
        guard trimmed.hasPrefix("#") else { return nil }
        if trimmed.hasPrefix("### ") { return .heading(level: 3, text: String(trimmed.dropFirst(4))) }
        if trimmed.hasPrefix("## ") { return .heading(level: 2, text: String(trimmed.dropFirst(3))) }
        if trimmed.hasPrefix("# ") { return .heading(level: 1, text: String(trimmed.dropFirst(2))) }
        return nil
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let cleaned = trimmed.replacing(" ", with: "")
        guard cleaned.count >= 3 else { return false }
        return cleaned.allSatisfy({ $0 == "-" }) ||
               cleaned.allSatisfy({ $0 == "*" }) ||
               cleaned.allSatisfy({ $0 == "_" })
    }

    private static func parseTaskListItem(_ trimmed: String) -> ListItem? {
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            return ListItem(text: String(trimmed.dropFirst(6)), isTask: true, isChecked: true)
        }
        if trimmed.hasPrefix("- [ ] ") {
            return ListItem(text: String(trimmed.dropFirst(6)), isTask: true, isChecked: false)
        }
        return nil
    }

    private static func parseUnorderedListItem(_ trimmed: String) -> String? {
        for prefix in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func parseOrderedListItem(_ trimmed: String) -> String? {
        guard let dotIndex = trimmed.firstIndex(of: ".") ?? trimmed.firstIndex(of: ")") else { return nil }
        let numberPart = trimmed[trimmed.startIndex..<dotIndex]
        guard !numberPart.isEmpty, numberPart.allSatisfy(\.isNumber) else { return nil }
        let afterDot = trimmed.index(after: dotIndex)
        guard afterDot < trimmed.endIndex else { return "" }
        guard trimmed[afterDot] == " " else { return nil }
        return String(trimmed[trimmed.index(after: afterDot)...])
    }

    private static func parseTableRow(_ trimmed: String) -> [String] {
        var row = trimmed
        if row.hasPrefix("|") { row = String(row.dropFirst()) }
        if row.hasSuffix("|") { row = String(row.dropLast()) }
        return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparatorRow(_ trimmed: String) -> Bool {
        var row = trimmed
        if row.hasPrefix("|") { row = String(row.dropFirst()) }
        if row.hasSuffix("|") { row = String(row.dropLast()) }
        return row.components(separatedBy: "|").allSatisfy { cell in
            cell.trimmingCharacters(in: .whitespaces).replacing("-", with: "").replacing(":", with: "").isEmpty
        }
    }

    private static func parseToolCallTag(_ trimmed: String) -> ToolCallInfo? {
        guard trimmed.hasPrefix("<tool_call"),
              let closingRange = trimmed.range(of: "</tool_call>"),
              trimmed.endIndex == closingRange.upperBound,
              let nameStart = trimmed.range(of: "name=\""),
              let nameEnd = trimmed[nameStart.upperBound...].firstIndex(of: "\""),
              let openTagEnd = trimmed.firstIndex(of: ">") else { return nil }
        let name = String(trimmed[nameStart.upperBound..<nameEnd])
        let displayText = String(trimmed[trimmed.index(after: openTagEnd)..<closingRange.lowerBound])
        return ToolCallInfo(name: name, displayText: displayText)
    }
}
