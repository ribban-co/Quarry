import AppKit

final class CanvasZoomOverlayView: NSView {
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onResetZoom: (() -> Void)?

    private let zoomPill: NSView
    private let zoomOutButton = NSButton()
    private let zoomPercentButton = NSButton()
    private let zoomInButton = NSButton()

    var zoomPercentage: Int = 100 {
        didSet { zoomPercentButton.title = "\(zoomPercentage)%" }
    }

    override init(frame frameRect: NSRect) {
        zoomPill = Self.makePill(cornerRadius: 8)
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        zoomPill = Self.makePill(cornerRadius: 8)
        super.init(coder: coder)
        setupViews()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }

    private func setupViews() {
        addSubview(zoomPill)

        configureIconButton(zoomOutButton, symbol: "minus", tooltip: "Zoom Out", action: #selector(zoomOutTapped))
        configureIconButton(zoomInButton, symbol: "plus", tooltip: "Zoom In", action: #selector(zoomInTapped))

        zoomPercentButton.bezelStyle = .toolbar
        zoomPercentButton.showsBorderOnlyWhileMouseInside = true
        zoomPercentButton.title = "50%"
        zoomPercentButton.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        zoomPercentButton.contentTintColor = .secondaryLabelColor
        zoomPercentButton.target = self
        zoomPercentButton.action = #selector(resetZoomTapped)
        zoomPercentButton.toolTip = "Reset Zoom (100%)"
        zoomPercentButton.translatesAutoresizingMaskIntoConstraints = false

        for button in [zoomOutButton, zoomPercentButton, zoomInButton] {
            zoomPill.addSubview(button)
        }

        NSLayoutConstraint.activate([
            zoomPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            zoomPill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            zoomOutButton.leadingAnchor.constraint(equalTo: zoomPill.leadingAnchor, constant: 4),
            zoomOutButton.topAnchor.constraint(equalTo: zoomPill.topAnchor, constant: 4),
            zoomOutButton.bottomAnchor.constraint(equalTo: zoomPill.bottomAnchor, constant: -4),

            zoomPercentButton.leadingAnchor.constraint(equalTo: zoomOutButton.trailingAnchor),
            zoomPercentButton.centerYAnchor.constraint(equalTo: zoomPill.centerYAnchor),

            zoomInButton.leadingAnchor.constraint(equalTo: zoomPercentButton.trailingAnchor),
            zoomInButton.topAnchor.constraint(equalTo: zoomPill.topAnchor, constant: 4),
            zoomInButton.bottomAnchor.constraint(equalTo: zoomPill.bottomAnchor, constant: -4),
            zoomInButton.trailingAnchor.constraint(equalTo: zoomPill.trailingAnchor, constant: -4),
        ])
    }

    // MARK: - Helpers

    private static func makePill(cornerRadius: CGFloat) -> NSView {
        ThemedPillView.makePill(cornerRadius: cornerRadius)
    }

    private func configureIconButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.bezelStyle = .toolbar
        button.showsBorderOnlyWhileMouseInside = true
        let config = NSImage.SymbolConfiguration(paletteColors: [.labelColor])
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Actions

    @objc private func zoomOutTapped() { onZoomOut?() }
    @objc private func zoomInTapped() { onZoomIn?() }
    @objc private func resetZoomTapped() { onResetZoom?() }
}
