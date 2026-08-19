import Combine
import Foundation
import SwiftUI
import CodeEditorView
@preconcurrency import LanguageSupport

final class SQLAutocompleteLanguageService: LanguageService {
    @MainActor
    private final class MetadataProvider {
        private let connection: ConnectionInstance

        init(connection: ConnectionInstance) {
            self.connection = connection
        }

        func currentContext() -> EditorContext {
            EditorContext(
                databaseName: connection.databaseService.currentDatabase?.name ?? "__default_db__",
                schemaName: connection.selectedTab?.databaseSchema ?? connection.databaseService.currentSchema
            )
        }

        func fetchTables(forSchemaName schemaName: String?) async -> [TableSummary] {
            let fetchedTables = (try? await connection.databaseService.listCollections(schema: schemaName)) ?? []
            return fetchedTables.map { table in
                TableSummary(name: table.name, schema: table.schema ?? schemaName, type: table.type)
            }
        }

        func fetchSchemaNames() async -> [String] {
            guard let schemas = try? await connection.databaseService.getInformationSchema() else {
                return []
            }
            return schemas.map { $0.name }
        }

        func fetchSchema(for tableName: String, schemaName: String?) async -> DatabaseSchemaResult? {
            try? await connection.databaseService.getSchema(for: tableName, databaseSchema: schemaName)
        }
    }

    private struct TableReference {
        let tableName: String
        let schemaName: String?
        let alias: String?

        var lookupKeys: [String] {
            var keys = [SQLAutocompleteLanguageService.normalizedLookupValue(tableName)]
            if let alias, !alias.isEmpty {
                keys.append(SQLAutocompleteLanguageService.normalizedLookupValue(alias))
            }
            return keys
        }
    }

    private struct TableSummary: Sendable {
        let name: String
        let schema: String?
        let type: String
    }

    private struct SchemaCacheKey: Hashable {
        let databaseName: String
        let tableName: String
        let schemaName: String?
    }

    /// `mask` is a cheap O(1) subsequence prefilter: scoring returns nil without
    /// running the DP when the pattern contains a char the text doesn't have.
    fileprivate struct ScoringBuffers: Sendable {
        let scalars: [UInt32]
        let scalarsLower: [UInt32]
        let mask: UInt64

        init(text: String) {
            var scalars: [UInt32] = []
            var scalarsLower: [UInt32] = []
            var mask: UInt64 = 0
            scalars.reserveCapacity(text.unicodeScalars.underestimatedCount)
            scalarsLower.reserveCapacity(text.unicodeScalars.underestimatedCount)

            for scalar in text.unicodeScalars {
                let value = scalar.value
                scalars.append(value)
                var lower = value
                if value >= 65, value <= 90 { lower = value + 32 }
                scalarsLower.append(lower)

                if lower >= 97, lower <= 122 {
                    mask |= UInt64(1) << (lower - 97)
                } else if lower >= 48, lower <= 57 {
                    mask |= UInt64(1) << (26 + (lower - 48))
                } else if lower == 95 {
                    mask |= UInt64(1) << 36
                }
            }
            self.scalars = scalars
            self.scalarsLower = scalarsLower
            self.mask = mask
        }
    }

    fileprivate struct CompletionCandidate: @unchecked Sendable {
        typealias Kind = CompletionDisplayInfo.Kind

        let id: Int
        let key: String
        let label: String
        let filterText: String
        let insertText: String
        let insertRange: NSRange?
        let kind: Kind
        let detail: String?
        let scoring: ScoringBuffers

        init(
            key: String,
            label: String,
            filterText: String,
            insertText: String,
            insertRange: NSRange?,
            kind: Kind,
            detail: String?
        ) {
            self.id = Self.stableIdentifier(for: key)
            self.key = key
            self.label = label
            self.filterText = filterText
            self.insertText = insertText
            self.insertRange = insertRange
            self.kind = kind
            self.detail = detail
            self.scoring = ScoringBuffers(text: filterText)
        }

        private static func stableIdentifier(for value: String) -> Int {
            value.unicodeScalars.reduce(5381) { partial, scalar in
                ((partial << 5) &+ partial) &+ Int(scalar.value)
            }
        }
    }

    private struct EditorContext: Sendable {
        let databaseName: String
        let schemaName: String?
    }

    private struct State {
        var documentText = ""
        var didOpenDocument = false
        var tableCache: [String: [TableSummary]] = [:]
        var schemaCache: [SchemaCacheKey: DatabaseSchemaResult] = [:]
        var schemaNameCache: [String: [String]] = [:]
        var displayInfoById: [Int: CompletionDisplayInfo] = [:]
        var tableReferencesCache: (prefix: String, defaultSchema: String?, result: [TableReference])?
    }

    private let metadataProvider: MetadataProvider
    private let stateLock = NSLock()
    private var state = State()

    let events = PassthroughSubject<LanguageServiceEvent, Never>()
    let diagnostics = CurrentValueSubject<Set<TextLocated<Message>>, Never>([])
    let completionTriggerCharacters = CurrentValueSubject<[Character], Never>([".", " "])
    let extraActions = CurrentValueSubject<[ExtraAction], Never>([])

    var isOpen: Bool {
        withState { $0.didOpenDocument }
    }

    @MainActor
    init(connection: ConnectionInstance) {
        self.metadataProvider = MetadataProvider(connection: connection)
    }

    func openDocument(with text: String, locationService: any LocationService) async throws {
        withState { state in
            state.documentText = text
            state.didOpenDocument = true
        }
    }

    func updateDocumentTextImmediately(_ text: String) {
        withState { state in
            state.documentText = text
        }
    }

    func documentDidChange(
        position changeLocation: Int,
        changeInLength delta: Int,
        lineChange deltaLine: Int,
        columnChange deltaColumn: Int,
        newText text: String
    ) async throws {
        withState { state in
            let currentNSString = state.documentText as NSString
            let safeLocation = max(0, min(changeLocation, currentNSString.length))
            let replacementLength = max(0, (text as NSString).length - delta)
            let safeLength = max(0, min(replacementLength, currentNSString.length - safeLocation))
            let safeRange = NSRange(location: safeLocation, length: safeLength)
            state.documentText = currentNSString.replacingCharacters(in: safeRange, with: text)
        }
    }

    func closeDocument() async throws {
        withState { state in
            state.documentText = ""
            state.didOpenDocument = false
        }
    }

    func completions(at location: Int, reason: CompletionTriggerReason) async throws -> Completions {
        let context = await metadataProvider.currentContext()
        let documentText = withState { $0.documentText }
        let insertionRange = completionRange(at: location, in: documentText)
        let prefix = substring(in: insertionRange, from: documentText)
        let statementPrefix = currentStatementPrefix(at: insertionRange.location, in: documentText)
        let tableReferences = tableReferences(in: statementPrefix, defaultSchema: context.schemaName)

        if let qualifier = memberQualifier(before: insertionRange.location, in: documentText) {
            let schemaNames = await schemaNames(context: context)
            if schemaNames.contains(where: { Self.normalizedLookupValue($0) == Self.normalizedLookupValue(qualifier) }) {
                let tables = await tables(forSchemaName: qualifier, context: context)
                let candidates = makeTableCandidates(
                    tables: tables,
                    insertionRange: insertionRange,
                    defaultSchema: qualifier,
                    includeSchemaPrefix: false
                )
                return makeCompletions(from: candidates, prefix: prefix, preferredKind: .table)
            }

            if let tableReference = resolveTableReference(for: qualifier, in: tableReferences) {
                let columns = await columns(for: tableReference, context: context)
                let candidates = makeColumnCandidates(columns: columns, insertionRange: insertionRange)
                return makeCompletions(from: candidates, prefix: prefix, preferredKind: .column)
            }

            if let directTableReference = await directTableReference(
                named: qualifier,
                schemaName: context.schemaName,
                context: context
            ) {
                let columns = await columns(for: directTableReference, context: context)
                let candidates = makeColumnCandidates(columns: columns, insertionRange: insertionRange)
                return makeCompletions(from: candidates, prefix: prefix, preferredKind: .column)
            }

            return .none
        }

        let lastKeyword = lastCompletionKeyword(in: statementPrefix)
        if let lastKeyword,
           tableContextKeywords.contains(lastKeyword),
           tableReferences.isEmpty
        {
            let tables = await tables(forSchemaName: context.schemaName, context: context)
            let candidates = makeTableCandidates(
                tables: tables,
                insertionRange: insertionRange,
                defaultSchema: context.schemaName
            )
            return makeCompletions(from: candidates, prefix: prefix, preferredKind: .table)
        }

        var candidates = makeKeywordCandidates(insertionRange: insertionRange)
        candidates.append(contentsOf: makeFunctionCandidates(insertionRange: insertionRange))

        let tables = await tables(forSchemaName: context.schemaName, context: context)
        candidates.append(contentsOf: makeTableCandidates(
            tables: tables,
            insertionRange: insertionRange,
            defaultSchema: context.schemaName
        ))

        if tableReferences.count == 1, let tableReference = tableReferences.first {
            let columns = await columns(for: tableReference, context: context)
            candidates.append(contentsOf: makeColumnCandidates(columns: columns, insertionRange: insertionRange))
        }

        let preferredKind = preferredKindForGeneralContext(lastKeyword: lastKeyword, hasTableReferences: !tableReferences.isEmpty)
        return makeCompletions(from: candidates, prefix: prefix, preferredKind: preferredKind)
    }

    private func preferredKindForGeneralContext(lastKeyword: String?, hasTableReferences: Bool) -> CompletionCandidate.Kind? {
        guard let lastKeyword else { return nil }
        switch lastKeyword {
        case "select", "where", "having", "on", "set", "order", "group", "by", "and", "or":
            return hasTableReferences ? .column : .keyword
        default:
            return nil
        }
    }

    func tokens(for lineRange: Range<Int>) async throws -> [[(token: LanguageConfiguration.Token, range: NSRange)]] {
        Array(repeating: [], count: lineRange.count)
    }

    func info(at location: Int) async throws -> (view: any View, anchor: NSRange?)? {
        nil
    }

    func capabilities() async throws -> (any View)? {
        Text("Phase 1 SQL autocomplete")
    }

    private func tables(forSchemaName schemaName: String?, context: EditorContext) async -> [TableSummary] {
        let cacheKey = "\(context.databaseName)::\(schemaName ?? "__default__")"
        if let cached = withState({ $0.tableCache[cacheKey] }) {
            return cached
        }

        let fetchedTables = await metadataProvider.fetchTables(forSchemaName: schemaName)
        withState { state in
            state.tableCache[cacheKey] = fetchedTables
        }
        return fetchedTables
    }

    private func schemaNames(context: EditorContext) async -> [String] {
        if let cached = withState({ $0.schemaNameCache[context.databaseName] }) {
            return cached
        }
        let fetched = await metadataProvider.fetchSchemaNames()
        withState { state in
            state.schemaNameCache[context.databaseName] = fetched
        }
        return fetched
    }

    private func columns(for tableReference: TableReference, context: EditorContext) async -> [DatabaseSchemaInfo] {
        let cacheKey = SchemaCacheKey(
            databaseName: context.databaseName,
            tableName: tableReference.tableName,
            schemaName: tableReference.schemaName
        )
        if let cached = withState({ $0.schemaCache[cacheKey] }) {
            return cached.columns
        }

        guard let schema = await metadataProvider.fetchSchema(
            for: tableReference.tableName,
            schemaName: tableReference.schemaName
        ) else {
            return []
        }

        withState { state in
            state.schemaCache[cacheKey] = schema
        }
        return schema.columns
    }

    private func withState<T>(_ operation: (inout State) -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return operation(&state)
    }

    private func completionRange(at location: Int, in documentText: String) -> NSRange {
        let nsText = documentText as NSString
        let safeLocation = max(0, min(location, nsText.length))
        var start = safeLocation

        while start > 0 {
            let scalar = nsText.character(at: start - 1)
            guard isIdentifierScalar(scalar) else { break }
            start -= 1
        }

        return NSRange(location: start, length: safeLocation - start)
    }

    private func currentStatementPrefix(at location: Int, in documentText: String) -> String {
        let nsText = documentText as NSString
        let safeLocation = max(0, min(location, nsText.length))
        let prefix = nsText.substring(to: safeLocation)
        let components = prefix.split(separator: ";", omittingEmptySubsequences: false)
        return components.last.map(String.init) ?? ""
    }

    private func memberQualifier(before location: Int, in documentText: String) -> String? {
        let nsText = documentText as NSString
        guard location > 0, location <= nsText.length else { return nil }

        let dotIndex = location - 1
        guard nsText.character(at: dotIndex) == 46 else { return nil }

        var qualifierEnd = dotIndex
        while qualifierEnd > 0, isWhitespaceScalar(nsText.character(at: qualifierEnd - 1)) {
            qualifierEnd -= 1
        }

        var qualifierStart = qualifierEnd
        while qualifierStart > 0, isIdentifierScalar(nsText.character(at: qualifierStart - 1)) {
            qualifierStart -= 1
        }

        guard qualifierStart < qualifierEnd else { return nil }
        return normalizedIdentifier(nsText.substring(with: NSRange(location: qualifierStart, length: qualifierEnd - qualifierStart)))
    }

    private func substring(in range: NSRange, from documentText: String) -> String {
        let nsText = documentText as NSString
        let safeLocation = max(0, min(range.location, nsText.length))
        let safeLength = max(0, min(range.length, nsText.length - safeLocation))
        return nsText.substring(with: NSRange(location: safeLocation, length: safeLength))
    }

    private func tokenize(_ text: String) -> [SQLToken] {
        var tokens: [SQLToken] = []
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                index += 1
                continue
            }

            if character == "." {
                tokens.append(SQLToken(rawText: ".", normalizedText: ".", isWord: false))
                index += 1
                continue
            }

            if character == "\"" || character == "`" || character == "[" {
                let closingCharacter: Character = character == "[" ? "]" : character
                let start = index
                index += 1

                while index < characters.count, characters[index] != closingCharacter {
                    index += 1
                }

                if index < characters.count {
                    index += 1
                }

                let raw = String(characters[start..<index])
                tokens.append(
                    SQLToken(
                        rawText: raw,
                        normalizedText: Self.normalizedLookupValue(normalizedIdentifier(raw)),
                        isWord: true
                    )
                )
                continue
            }

            if isIdentifierCharacter(character) {
                let start = index
                index += 1

                while index < characters.count, isIdentifierCharacter(characters[index]) {
                    index += 1
                }

                let raw = String(characters[start..<index])
                tokens.append(
                    SQLToken(
                        rawText: raw,
                        normalizedText: Self.normalizedLookupValue(raw),
                        isWord: true
                    )
                )
                continue
            }

            tokens.append(SQLToken(rawText: String(character), normalizedText: String(character), isWord: false))
            index += 1
        }

        return tokens
    }

    private func tableReferences(in statementPrefix: String, defaultSchema: String?) -> [TableReference] {
        if let cached = withState({ $0.tableReferencesCache }),
           cached.prefix == statementPrefix,
           cached.defaultSchema == defaultSchema
        {
            return cached.result
        }

        let result = computeTableReferences(in: statementPrefix, defaultSchema: defaultSchema)
        withState { state in
            state.tableReferencesCache = (statementPrefix, defaultSchema, result)
        }
        return result
    }

    private func computeTableReferences(in statementPrefix: String, defaultSchema: String?) -> [TableReference] {
        let tokens = tokenize(statementPrefix)
        var references: [TableReference] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            guard token.isWord else {
                index += 1
                continue
            }

            if !tableContextKeywords.contains(token.normalizedText) {
                index += 1
                continue
            }

            guard let reference = parseTableReference(
                tokens: tokens,
                startIndex: index + 1,
                defaultSchema: defaultSchema
            ) else {
                index += 1
                continue
            }

            references.append(reference.reference)
            index = reference.nextIndex
        }

        return references
    }

    private func parseTableReference(
        tokens: [SQLToken],
        startIndex: Int,
        defaultSchema: String?
    ) -> (reference: TableReference, nextIndex: Int)? {
        guard startIndex < tokens.count, tokens[startIndex].isWord else { return nil }

        let firstPart = normalizedIdentifier(tokens[startIndex].rawText)
        var schemaName: String?
        var tableName = firstPart
        var nextIndex = startIndex + 1

        if nextIndex + 1 < tokens.count, tokens[nextIndex].rawText == ".", tokens[nextIndex + 1].isWord {
            schemaName = firstPart
            tableName = normalizedIdentifier(tokens[nextIndex + 1].rawText)
            nextIndex += 2
        }

        if nextIndex < tokens.count, tokens[nextIndex].normalizedText == "as" {
            nextIndex += 1
        }

        var alias: String?
        if nextIndex < tokens.count,
           tokens[nextIndex].isWord,
           !sqlClauseKeywords.contains(tokens[nextIndex].normalizedText) {
            alias = normalizedIdentifier(tokens[nextIndex].rawText)
            nextIndex += 1
        }

        return (
            TableReference(tableName: tableName, schemaName: schemaName ?? defaultSchema, alias: alias),
            nextIndex
        )
    }

    private func resolveTableReference(for qualifier: String, in tableReferences: [TableReference]) -> TableReference? {
        let normalizedQualifier = Self.normalizedLookupValue(qualifier)
        return tableReferences.first { reference in
            reference.lookupKeys.contains(normalizedQualifier)
        }
    }

    private func directTableReference(
        named qualifier: String,
        schemaName: String?,
        context: EditorContext
    ) async -> TableReference? {
        let normalizedQualifier = Self.normalizedLookupValue(qualifier)
        let tables = await tables(forSchemaName: schemaName, context: context)
        guard let table = tables.first(where: { Self.normalizedLookupValue($0.name) == normalizedQualifier }) else {
            return nil
        }

        return TableReference(tableName: table.name, schemaName: table.schema ?? schemaName, alias: nil)
    }

    private func lastCompletionKeyword(in statementPrefix: String) -> String? {
        tokenize(statementPrefix)
            .reversed()
            .first(where: { $0.isWord && tableContextKeywords.contains($0.normalizedText) })?
            .normalizedText
    }

    private func makeKeywordCandidates(insertionRange: NSRange) -> [CompletionCandidate] {
        sqlKeywords.map { keyword in
            CompletionCandidate(
                key: "keyword:\(keyword)",
                label: keyword,
                filterText: keyword,
                insertText: keyword,
                insertRange: insertionRange,
                kind: .keyword,
                detail: "SQL keyword"
            )
        }
    }

    private func makeFunctionCandidates(insertionRange: NSRange) -> [CompletionCandidate] {
        sqlFunctions.map { function in
            CompletionCandidate(
                key: "function:\(function)",
                label: function,
                filterText: function,
                insertText: function,
                insertRange: insertionRange,
                kind: .function,
                detail: "SQL function"
            )
        }
    }

    private func makeTableCandidates(
        tables: [TableSummary],
        insertionRange: NSRange,
        defaultSchema: String?,
        includeSchemaPrefix: Bool = true
    ) -> [CompletionCandidate] {
        tables.map { table in
            let displayName: String
            if includeSchemaPrefix,
               let schema = table.schema,
               !schema.isEmpty,
               schema != defaultSchema
            {
                displayName = "\(schema).\(table.name)"
            } else {
                displayName = table.name
            }

            return CompletionCandidate(
                key: "table:\(table.schema ?? "_default"):\(table.name)",
                label: displayName,
                filterText: table.name,
                insertText: displayName,
                insertRange: insertionRange,
                kind: .table,
                detail: table.type.capitalized
            )
        }
    }

    private func makeColumnCandidates(
        columns: [DatabaseSchemaInfo],
        insertionRange: NSRange
    ) -> [CompletionCandidate] {
        columns.map { column in
            CompletionCandidate(
                key: "column:\(column.columnName)",
                label: column.columnName,
                filterText: column.columnName,
                insertText: column.columnName,
                insertRange: insertionRange,
                kind: .column,
                detail: column.formatType.isEmpty ? column.dataType : column.formatType
            )
        }
    }

    private func makeCompletions(
        from candidates: [CompletionCandidate],
        prefix: String,
        preferredKind: CompletionCandidate.Kind? = nil
    ) -> Completions {
        let filteredCandidates = filterCandidates(
            candidates,
            prefix: prefix,
            preferredKind: preferredKind
        )

        var displayInfoMap: [Int: CompletionDisplayInfo] = [:]
        displayInfoMap.reserveCapacity(filteredCandidates.count)

        let completions = filteredCandidates.enumerated().map { index, candidate -> Completions.Completion in
            displayInfoMap[candidate.id] = CompletionDisplayInfo(
                label: candidate.label,
                detail: candidate.detail,
                kind: candidate.kind
            )
            return Completions.Completion(
                id: candidate.id,
                rowView: { _ in EmptyView() },
                documentationView: EmptyView(),
                selected: index == 0,
                sortText: "\(paddedSortOrder(index))-\(candidate.label.lowercased())",
                filterText: candidate.filterText,
                insertText: candidate.insertText,
                insertRange: candidate.insertRange,
                commitCharacters: [],
                refine: { nil }
            )
        }

        // Atomic swap so UI never sees a half-populated map between calls.
        withState { state in
            state.displayInfoById = displayInfoMap
        }

        return Completions(isIncomplete: false, items: completions)
    }

    private static let maxCompletionResults = 50

    private func filterCandidates(
        _ candidates: [CompletionCandidate],
        prefix: String,
        preferredKind: CompletionCandidate.Kind?
    ) -> [CompletionCandidate] {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)

        let patternData: ScoringBuffers? = trimmedPrefix.isEmpty ? nil : ScoringBuffers(text: trimmedPrefix)

        let candidateCount = candidates.count
        var scores = [Int](repeating: 0, count: candidateCount)

        for i in 0..<candidateCount {
            scores[i] = Self.relevanceScore(
                candidate: candidates[i],
                pattern: patternData,
                preferredKind: preferredKind
            )
        }

        let indices = (0..<candidateCount).sorted { lhs, rhs in
            if scores[lhs] != scores[rhs] { return scores[lhs] > scores[rhs] }
            let lhsPriority = completionPriority(candidates[lhs].kind)
            let rhsPriority = completionPriority(candidates[rhs].kind)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return candidates[lhs].label.localizedCaseInsensitiveCompare(candidates[rhs].label) == .orderedAscending
        }

        let limit = min(Self.maxCompletionResults, indices.count)
        return indices.prefix(limit).map { candidates[$0] }
    }

    private static func relevanceScore(
        candidate: CompletionCandidate,
        pattern: ScoringBuffers?,
        preferredKind: CompletionCandidate.Kind?
    ) -> Int {
        let preferenceBonus = candidate.kind == preferredKind ? 60 : 0

        guard let pattern else { return preferenceBonus }

        guard (candidate.scoring.mask & pattern.mask) == pattern.mask else {
            return -1000 + preferenceBonus
        }

        guard let match = fuzzyScore(candidate: candidate, pattern: pattern) else {
            return -1000 + preferenceBonus
        }
        return match + preferenceBonus
    }

    /// fzf-v2 DP scoring. Returns nil when `pattern` is not a subsequence of the
    /// candidate's text. Reference: https://github.com/junegunn/fzf/blob/master/src/algo/algo.go
    private static func fuzzyScore(candidate: CompletionCandidate, pattern: ScoringBuffers) -> Int? {
        let textScalars = candidate.scoring.scalars
        let textScalarsLower = candidate.scoring.scalarsLower
        let patternScalars = pattern.scalars
        let patternScalarsLower = pattern.scalarsLower
        let textCount = textScalars.count
        let patternCount = patternScalars.count

        guard patternCount > 0 else { return 0 }
        guard patternCount <= textCount else { return nil }

        let matchBase = 16
        let caseBonus = 3
        let boundaryBonus = 30
        let separatorBonus = 30
        let camelBonus = 24
        let gapStart = -3
        let gapExtend = -1
        let firstCharMultiplier = 2
        let minScore = Int.min / 2

        var positionBonus = [Int](repeating: 0, count: textCount)
        for j in 0..<textCount {
            if j == 0 {
                positionBonus[j] = boundaryBonus
            } else {
                let previous = textScalarsLower[j - 1]
                // 95=_, 46=., 32=space, 45=-, 47=/
                if previous == 95 || previous == 46 || previous == 32 || previous == 45 || previous == 47 {
                    positionBonus[j] = separatorBonus
                } else {
                    let prevOriginal = textScalars[j - 1]
                    let currentOriginal = textScalars[j]
                    let prevIsLower = prevOriginal >= 97 && prevOriginal <= 122
                    let currIsUpper = currentOriginal >= 65 && currentOriginal <= 90
                    if prevIsLower && currIsUpper {
                        positionBonus[j] = camelBonus
                    }
                }
            }
        }

        var scoreMatrix = [Int](repeating: minScore, count: patternCount * textCount)
        var consecMatrix = [Int](repeating: 0, count: patternCount * textCount)

        var rowMax = minScore

        for j in 0..<textCount {
            let idx = j  // row 0 offset = 0
            if textScalarsLower[j] == patternScalarsLower[0] {
                let matchedCase = textScalars[j] == patternScalars[0] ? caseBonus : 0
                scoreMatrix[idx] = matchBase + (positionBonus[j] * firstCharMultiplier) + matchedCase
                consecMatrix[idx] = 1
            }
            if j > 0 {
                let prevConsec = consecMatrix[idx - 1]
                let gapPenalty = prevConsec > 0 ? gapStart : gapExtend
                let gapScore = scoreMatrix[idx - 1] + gapPenalty
                if gapScore > scoreMatrix[idx] {
                    scoreMatrix[idx] = gapScore
                    consecMatrix[idx] = 0
                }
            }
            rowMax = max(rowMax, scoreMatrix[idx])
        }

        if rowMax == minScore { return nil }

        for i in 1..<patternCount {
            rowMax = minScore
            let rowOffset = i * textCount
            let prevRowOffset = (i - 1) * textCount
            for j in i..<textCount {
                let idx = rowOffset + j
                let prevDiag = scoreMatrix[prevRowOffset + j - 1]
                if textScalarsLower[j] == patternScalarsLower[i], prevDiag > minScore {
                    let matchedCase = textScalars[j] == patternScalars[i] ? caseBonus : 0
                    let prevConsec = consecMatrix[prevRowOffset + j - 1]
                    let consecutiveBonus = prevConsec > 0 ? matchBase : 0
                    let matchScore =
                        prevDiag
                        + matchBase
                        + positionBonus[j]
                        + matchedCase
                        + consecutiveBonus
                    scoreMatrix[idx] = matchScore
                    consecMatrix[idx] = prevConsec + 1
                }
                if j > i {
                    let prevConsec = consecMatrix[idx - 1]
                    let gapPenalty = prevConsec > 0 ? gapStart : gapExtend
                    let gapScore = scoreMatrix[idx - 1] + gapPenalty
                    if gapScore > scoreMatrix[idx] {
                        scoreMatrix[idx] = gapScore
                        consecMatrix[idx] = 0
                    }
                }
                rowMax = max(rowMax, scoreMatrix[idx])
            }
            if rowMax == minScore { return nil }
        }

        let lastRowOffset = (patternCount - 1) * textCount
        var best = minScore
        for j in 0..<textCount {
            if scoreMatrix[lastRowOffset + j] > best {
                best = scoreMatrix[lastRowOffset + j]
            }
        }
        guard best > minScore else { return nil }

        return best - (textCount - patternCount) / 5
    }

    func displayInfo(forId id: Int) -> CompletionDisplayInfo? {
        withState { $0.displayInfoById[id] }
    }

    private func completionPriority(_ kind: CompletionCandidate.Kind) -> Int {
        switch kind {
        case .column: return 0
        case .keyword: return 1
        case .function: return 2
        case .table: return 3
        case .info: return 4
        }
    }

    private func paddedSortOrder(_ value: Int) -> String {
        let rawValue = String(value)
        return String(repeating: "0", count: max(0, 4 - rawValue.count)) + rawValue
    }

    private func isIdentifierScalar(_ scalar: unichar) -> Bool {
        guard let unicodeScalar = UnicodeScalar(UInt32(scalar)) else { return false }
        return scalar == 95 || scalar == 36 || CharacterSet.alphanumerics.contains(unicodeScalar)
    }

    private func isWhitespaceScalar(_ scalar: unichar) -> Bool {
        guard let unicodeScalar = UnicodeScalar(UInt32(scalar)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(unicodeScalar)
    }

    private func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    private func normalizedIdentifier(_ rawValue: String) -> String {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue.hasPrefix("\""), trimmedValue.hasSuffix("\""), trimmedValue.count >= 2 {
            return String(trimmedValue.dropFirst().dropLast())
        }

        if trimmedValue.hasPrefix("`"), trimmedValue.hasSuffix("`"), trimmedValue.count >= 2 {
            return String(trimmedValue.dropFirst().dropLast())
        }

        if trimmedValue.hasPrefix("["), trimmedValue.hasSuffix("]"), trimmedValue.count >= 2 {
            return String(trimmedValue.dropFirst().dropLast())
        }

        return trimmedValue
    }

    private static func normalizedLookupValue(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private struct SQLToken {
        let rawText: String
        let normalizedText: String
        let isWord: Bool
    }

    private let tableContextKeywords: Set<String> = ["from", "join", "update", "into"]

    private let sqlClauseKeywords: Set<String> = [
        "select", "from", "join", "update", "into", "where", "group", "order", "having", "limit",
        "offset", "on", "union", "left", "right", "inner", "outer", "cross", "with", "values", "set"
    ]

    private let sqlKeywords: [String] = [
        "*", "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "ON", "GROUP BY",
        "ORDER BY", "HAVING", "LIMIT", "OFFSET", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "ALTER", "DROP", "TABLE", "VIEW", "INDEX", "DISTINCT", "UNION", "ALL", "AS", "AND",
        "OR", "NOT", "NULL", "IS", "IN", "EXISTS", "BETWEEN", "LIKE", "CASE", "WHEN", "THEN", "ELSE",
        "END", "WITH", "RETURNING"
    ]

    private let sqlFunctions: [String] = [
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF", "LOWER", "UPPER", "LENGTH",
        "ROUND", "TRIM", "SUBSTRING"
    ]
}
