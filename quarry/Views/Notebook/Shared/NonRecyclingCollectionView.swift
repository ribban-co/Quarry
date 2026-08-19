import AppKit

final class NonRecyclingCollectionView: NSCollectionView {
    override var visibleRect: NSRect { bounds }
}
