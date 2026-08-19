import AppKit

@MainActor
final class ShimmerLayer {

    private var maskLayer: CAGradientLayer?

    var isActive: Bool { maskLayer != nil }

    func start(on view: NSView, insetDx: CGFloat = -24) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        guard maskLayer == nil else { return }

        view.wantsLayer = true

        let mask = CAGradientLayer()
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [
            NSColor.white.withAlphaComponent(0.55).cgColor,
            NSColor.white.cgColor,
            NSColor.white.withAlphaComponent(0.55).cgColor,
        ]
        mask.locations = [0.0, 0.18, 0.36]

        let bounds = view.bounds
        if bounds.width > 0 {
            mask.frame = bounds.insetBy(dx: insetDx, dy: 0)
        } else {
            mask.frame = CGRect(x: insetDx, y: 0, width: 250, height: 20)
        }

        let shimmer = CABasicAnimation(keyPath: "locations")
        shimmer.fromValue = [-0.25, -0.1, 0.05]
        shimmer.toValue = [0.95, 1.1, 1.25]
        shimmer.duration = 1.4
        shimmer.repeatCount = .infinity
        shimmer.timingFunction = CAMediaTimingFunction(name: .easeOut)

        mask.add(shimmer, forKey: "shimmer")
        view.layer?.mask = mask
        maskLayer = mask
    }

    func stop(from view: NSView) {
        guard let mask = maskLayer else { return }
        mask.removeAllAnimations()
        view.layer?.mask = nil
        maskLayer = nil
    }

    func updateFrame(for view: NSView, insetDx: CGFloat = -24) {
        maskLayer?.frame = view.bounds.insetBy(dx: insetDx, dy: 0)
    }
}
