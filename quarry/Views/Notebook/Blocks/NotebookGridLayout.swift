import AppKit

struct NotebookRowInfo {
    let startIndex: Int
    let endIndex: Int
    let frame: NSRect
}

final class NotebookGridLayout: NSCollectionViewLayout {

    private static let standardRowTopInset: CGFloat = 29
    private static let singleValueRowTopInset: CGFloat = 16
    private static let firstInsertBarGapHeight: CGFloat = 60

    weak var dataController: NotebookDataController?

    var sectionInsets = NSEdgeInsets(top: 32, left: 20, bottom: 32, right: 20)
    var lineSpacing: CGFloat = 48

    var insertRowGapBeforeIndex: Int?
    var insertRowGapHeight: CGFloat = 60

    var insertBarBeforeRowIndex: Int?
    var insertBarHeight: CGFloat = 46

    private var cachedAttributes: [NSCollectionViewLayoutAttributes] = []
    private var cachedContentSize: NSSize = .zero
    private(set) var cachedRows: [NotebookRowInfo] = []
    private(set) var insertGapFrame: NSRect?
    private(set) var insertBarFrame: NSRect?

    private func rowBottomInset(for row: [NotebookBlock]) -> CGFloat {
        row.allSatisfy { $0.blockType == .singleValue } ? 0 : 12
    }

    private func rowTopInset(for row: [NotebookBlock]) -> CGFloat {
        guard !row.isEmpty else { return 0 }
        return row.allSatisfy { $0.blockType == .singleValue }
            ? Self.singleValueRowTopInset
            : Self.standardRowTopInset
    }

    override func prepare() {
        super.prepare()
        cachedAttributes.removeAll()
        cachedRows.removeAll()
        insertGapFrame = nil
        insertBarFrame = nil

        guard let collectionView, let dataController else {
            cachedContentSize = .zero
            return
        }

        let blocks = dataController.blocks
        guard !blocks.isEmpty else {
            cachedContentSize = NSSize(width: collectionView.bounds.width, height: sectionInsets.top + sectionInsets.bottom)
            return
        }

        let totalWidth = collectionView.bounds.width
        let availableWidth = totalWidth - sectionInsets.left - sectionInsets.right

        let rows = buildRows(from: blocks)

        var yOffset = sectionInsets.top
        var globalIndex = 0

        for (rowIndex, row) in rows.enumerated() {
            if rowIndex == insertRowGapBeforeIndex {
                insertGapFrame = NSRect(x: sectionInsets.left, y: yOffset, width: availableWidth, height: insertRowGapHeight)
                yOffset += insertRowGapHeight + lineSpacing
            }

            if rowIndex == insertBarBeforeRowIndex {
                let existingGapHeight: CGFloat
                let gapTop: CGFloat

                if rowIndex == 0 {
                    existingGapHeight = sectionInsets.top
                    gapTop = 0
                } else {
                    let previousRow = rows[rowIndex - 1]
                    let previousBottomInset = rowBottomInset(for: previousRow)
                    let currentTopInset = rowTopInset(for: row)
                    existingGapHeight = lineSpacing + previousBottomInset + currentTopInset
                    gapTop = yOffset - lineSpacing - previousBottomInset
                }

                let desiredGapHeight: CGFloat
                if rowIndex == 0 {
                    desiredGapHeight = max(Self.firstInsertBarGapHeight, insertBarHeight)
                } else {
                    desiredGapHeight = max(existingGapHeight, insertBarHeight)
                }
                let additionalGapHeight = desiredGapHeight - existingGapHeight
                insertBarFrame = NSRect(x: sectionInsets.left, y: gapTop, width: availableWidth, height: desiredGapHeight)
                yOffset += additionalGapHeight
            }

            let rowStartIndex = globalIndex
            var xOffset = sectionInsets.left
            var maxHeight: CGFloat = 0

            for block in row {
                let isSingleValue = block.blockType == .singleValue
                let titleHeight: CGFloat = 29
                let resizeHandleHeight: CGFloat = isSingleValue ? 0 : 12
                let contentHeight: CGFloat
                if isSingleValue {
                    contentHeight = 140
                } else {
                    let minContentHeight: CGFloat
                    switch block.blockType {
                    case .chart: minContentHeight = 280
                    case .singleValue: minContentHeight = 120
                    case .text: minContentHeight = 80
                    case .query: minContentHeight = 200
                    }
                    contentHeight = max(minContentHeight, block.blockHeight)
                }
                let itemHeight = titleHeight + contentHeight + resizeHandleHeight

                let itemWidth: CGFloat
                if isSingleValue {
                    itemWidth = 240
                } else {
                    itemWidth = availableWidth
                }

                let attrs = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: globalIndex, section: 0))
                attrs.frame = NSRect(x: xOffset, y: yOffset, width: itemWidth, height: itemHeight)
                cachedAttributes.append(attrs)

                xOffset += itemWidth + (isSingleValue ? 12 : 0)
                maxHeight = max(maxHeight, itemHeight)
                globalIndex += 1
            }

            let rowFrame = NSRect(x: sectionInsets.left, y: yOffset, width: availableWidth, height: maxHeight)
            cachedRows.append(NotebookRowInfo(
                startIndex: rowStartIndex,
                endIndex: globalIndex - 1,
                frame: rowFrame
            ))

            yOffset += maxHeight + lineSpacing
        }

        if insertRowGapBeforeIndex == rows.count {
            insertGapFrame = NSRect(x: sectionInsets.left, y: yOffset, width: availableWidth, height: insertRowGapHeight)
            yOffset += insertRowGapHeight + lineSpacing
        }

        yOffset = yOffset - lineSpacing + sectionInsets.bottom
        cachedContentSize = NSSize(width: totalWidth, height: yOffset)
    }

    override var collectionViewContentSize: NSSize {
        cachedContentSize
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cachedAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < cachedAttributes.count else { return nil }
        return cachedAttributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        guard let collectionView else { return true }
        return collectionView.bounds.width != newBounds.width
    }

    private func buildRows(from blocks: [NotebookBlock]) -> [[NotebookBlock]] {
        var rows: [[NotebookBlock]] = []
        for block in blocks {
            if block.notebookInline, !rows.isEmpty {
                rows[rows.count - 1].append(block)
            } else {
                rows.append([block])
            }
        }
        return rows
    }
}
