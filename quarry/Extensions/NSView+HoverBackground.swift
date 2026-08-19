import AppKit

extension NSView {
    func applyHoverBackground(_ isHovering: Bool) {
        guard let layer else { return }
        if isHovering {
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.06).cgColor
                : NSColor.black.withAlphaComponent(0.04).cgColor
        } else {
            layer.backgroundColor = nil
        }
    }
}
