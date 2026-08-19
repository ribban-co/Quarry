import AppKit

@MainActor
final class IntelligencePlatterOverlay {

    private var containerView: NSView?
    private var platterView: NSView?
    private var shimmerTask: Task<Void, Never>?
    private var isShowing = false

    func setup(on targetView: NSView, behind siblingView: NSView? = nil) {
        guard let platterViewClass = NSClassFromString("_NSIntelligenceUIPlatterView") as? NSView.Type else { return }

        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.alphaValue = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        if let siblingView {
            targetView.addSubview(container, positioned: .below, relativeTo: siblingView)
        } else {
            targetView.addSubview(container)
        }

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: targetView.topAnchor),
            container.leadingAnchor.constraint(equalTo: targetView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: targetView.trailingAnchor),
            container.heightAnchor.constraint(equalToConstant: 8),
        ])

        let platter = platterViewClass.init(frame: .zero)
        platter.setValue(true, forKey: "hasInteriorLight")
        platter.setValue(false, forKey: "hasExteriorLight")
        platter.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(platter)

        NSLayoutConstraint.activate([
            platter.topAnchor.constraint(equalTo: container.topAnchor),
            platter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            platter.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            platter.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let mask = CAGradientLayer()
        mask.type = .radial
        mask.colors = [
            NSColor.white.cgColor,
            NSColor.white.cgColor,
            NSColor.clear.cgColor,
        ]
        mask.locations = [0.0, 0.4, 1.0]
        mask.startPoint = CGPoint(x: 0.5, y: 1.0)
        mask.endPoint = CGPoint(x: 1.0, y: 0.0)
        container.layer?.mask = mask

        containerView = container
        platterView = platter
    }

    func layoutMask() {
        containerView?.layer?.mask?.frame = containerView?.bounds ?? .zero
    }

    func show() {
        guard !isShowing, let container = containerView else { return }
        isShowing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            container.animator().alphaValue = 1
        }
        startShimmerLoop()
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        shimmerTask?.cancel()
        shimmerTask = nil
        guard let container = containerView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            container.animator().alphaValue = 0
        }
    }

    nonisolated func teardown() {
        MainActor.assumeIsolated {
            shimmerTask?.cancel()
            shimmerTask = nil
            containerView?.removeFromSuperview()
            containerView = nil
            platterView = nil
        }
    }

    private func startShimmerLoop() {
        shimmerTask?.cancel()
        shimmerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let platter = self.platterView else { return }
                platter.perform(NSSelectorFromString("shimmer"))
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
