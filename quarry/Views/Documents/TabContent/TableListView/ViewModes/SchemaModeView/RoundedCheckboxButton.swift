//
//  RoundedCheckboxButton.swift
//  Quarry
//
//  Rounded-corner checkbox used by the schema editor (Nullable / Unique columns).
//

import AppKit

/// A custom-drawn checkbox with rounded corners that matches Quarry's design language.
/// Checked state uses the system accent color; unchecked state is a soft outlined box.
final class RoundedCheckboxButton: NSButton {
    var isOn: Bool = false {
        didSet {
            guard oldValue != isOn else { return }
            needsDisplay = true
        }
    }

    private let boxSize: CGFloat = 16
    private let cornerRadius: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        title = ""
        isBordered = false
        imagePosition = .noImage
        setButtonType(.momentaryChange)
        focusRingType = .none
    }

    override var allowsVibrancy: Bool { false }

    // Pin the coordinate system so the checkmark orientation is deterministic.
    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let boxRect = NSRect(
            x: ((bounds.width - boxSize) / 2).rounded(),
            y: ((bounds.height - boxSize) / 2).rounded(),
            width: boxSize,
            height: boxSize
        )

        if isOn {
            let fill = NSBezierPath(roundedRect: boxRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.controlAccentColor.setFill()
            fill.fill()
            drawCheckmark(in: boxRect)
        } else {
            let inset = boxRect.insetBy(dx: 0.5, dy: 0.5)
            let track = NSBezierPath(roundedRect: inset, xRadius: cornerRadius - 0.5, yRadius: cornerRadius - 0.5)
            track.lineWidth = 1
            NSColor.quaternaryLabelColor.setStroke()
            track.stroke()
        }
    }

    private func drawCheckmark(in box: NSRect) {
        let w = box.width
        let check = NSBezierPath()
        check.move(to: NSPoint(x: box.minX + w * 0.27, y: box.minY + w * 0.48))
        check.line(to: NSPoint(x: box.minX + w * 0.43, y: box.minY + w * 0.67))
        check.line(to: NSPoint(x: box.minX + w * 0.74, y: box.minY + w * 0.33))
        check.lineWidth = 2
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor.white.setStroke()
        check.stroke()
    }
}
