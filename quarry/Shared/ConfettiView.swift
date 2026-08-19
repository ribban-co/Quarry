//
//  ConfettiView.swift
//  Quarry
//
//  Created by Fauzaan on 1/31/25.
//

import SwiftUI
import AppKit
import QuartzCore

public enum ConfettiViewStyle {
    case large
    case small
}

public struct ConfettiView: NSViewRepresentable {
    public var colors: [NSColor] = [
        NSColor(red: 248/255, green: 148/255, blue: 99/255, alpha: 1.0), // Primary orange
        NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0), // Blue
        NSColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1.0), // Green
        NSColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 1.0), // Pink
        NSColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 1.0)  // Yellow
    ]
    public var intensity: Float = 0.8
    public var style: ConfettiViewStyle = .large
    @Binding var isActive: Bool
    
    public func makeNSView(context: Context) -> ConfettiNSView {
        let view = ConfettiNSView()
        view.colors = colors
        view.intensity = intensity
        view.style = style
        return view
    }
    
    public func updateNSView(_ nsView: ConfettiNSView, context: Context) {
        if isActive && !nsView.isActive() {
            nsView.startConfetti()
        } else if !isActive && nsView.isActive() {
            nsView.stopConfetti()
        }
    }
}

public final class ConfettiNSView: NSView {
    public var colors: [NSColor] = []
    public var intensity: Float = 0.8
    public var style: ConfettiViewStyle = .large

    private(set) var emitter: CAEmitterLayer?
    private var active = false
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = false
    }
    private var image: CGImage? {
        // Create a simple confetti shape programmatically
        let size = CGSize(width: 10, height: 10)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), 
                               bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, 
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        context?.setFillColor(NSColor.white.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        
        return context?.makeImage()
    }

    public func startConfetti(beginAtTimeZero: Bool = true) {
        emitter?.removeFromSuperlayer()
        emitter = CAEmitterLayer()

        if beginAtTimeZero {
            emitter?.beginTime = CACurrentMediaTime()
        }

//        emitter?.emitterPosition = CGPoint(x: frame.size.width / 2.0, y: -10)
        emitter?.emitterPosition = CGPoint(x: frame.size.width / 2.0, y: frame.size.height + 10)
        emitter?.emitterShape = .line
        emitter?.emitterSize = CGSize(width: frame.size.width, height: 1)

        var cells = [CAEmitterCell]()
        for color in colors {
            cells.append(confettiWithColor(color: color))
        }

        emitter?.emitterCells = cells

        switch style {
        case .large:
            emitter?.birthRate = 4
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.emitter?.birthRate = 0.6
            }
        case .small:
            emitter?.birthRate = 0.35
        }

        if let layer = self.layer {
            layer.addSublayer(emitter!)
        }
        active = true

        // Auto-stop after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.stopConfetti()
        }
    }

    public func stopConfetti() {
        active = false
        guard let emitter else { return }
        emitter.birthRate = 0

        // Let already-emitted particles finish, then drop the layer so it
        // stops animating and can be released.
        let maxLifetime = TimeInterval((emitter.emitterCells ?? [])
            .map { $0.lifetime + $0.lifetimeRange }
            .max() ?? 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + maxLifetime) { [weak self, weak emitter] in
            guard let emitter else { return }
            emitter.removeFromSuperlayer()
            // A restart swaps in a fresh emitter; only clear our reference
            // if it still points at the one we just removed.
            if self?.emitter === emitter {
                self?.emitter = nil
            }
        }
    }

    public override func layout() {
        super.layout()
        emitter?.emitterPosition = CGPoint(x: frame.size.width / 2.0, y: frame.size.height + 10)
//        emitter?.emitterPosition = CGPoint(x: frame.size.width / 2.0, y: -10)
        emitter?.emitterSize = CGSize(width: frame.size.width, height: 1)
    }

    func confettiWithColor(color: NSColor) -> CAEmitterCell {
        let confetti = CAEmitterCell()
        confetti.birthRate = 12.0 * intensity
        confetti.lifetime = 14.0 * intensity
        confetti.lifetimeRange = 0
        confetti.color = color.cgColor
        confetti.velocity = CGFloat(350.0 * intensity)
        confetti.velocityRange = CGFloat(80.0 * intensity)
        confetti.emissionLongitude = CGFloat(Double.pi)
        confetti.emissionRange = CGFloat(Double.pi)
        confetti.spin = CGFloat(3.5 * intensity)
        confetti.spinRange = CGFloat(4.0 * intensity)
        confetti.scaleRange = CGFloat(intensity)
        confetti.scaleSpeed = CGFloat(-0.1 * intensity)
        confetti.contents = image
        confetti.contentsScale = 1.5
        confetti.setValue("plane", forKey: "particleType")
        confetti.setValue(Double.pi, forKey: "orientationRange")
        confetti.setValue(Double.pi / 2, forKey: "orientationLongitude")
        confetti.setValue(Double.pi / 2, forKey: "orientationLatitude")

        if style == .small {
            confetti.contentsScale = 3.0
            confetti.velocity = CGFloat(70.0 * intensity)
            confetti.velocityRange = CGFloat(20.0 * intensity)
        }

        return confetti
    }

    public func isActive() -> Bool {
        return self.active
    }
}
