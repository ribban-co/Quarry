//
//  PremiumCardView.swift
//  Quarry
//

import AppKit
import SceneKit
import SwiftUI

struct PremiumCardView: View {
    let displayName: String
    let sinceYear: String
    let memberSerial: String?

    @Environment(\.colorScheme) private var colorScheme

    private let cardWidth: CGFloat = 440
    private let cardHeight: CGFloat = 278

    var body: some View {
        AutoSpinCardSceneView(
            displayName: displayName,
            sinceYear: sinceYear,
            memberSerial: memberSerial,
            isDark: colorScheme == .dark
        )
        .frame(width: cardWidth, height: cardHeight)
        .fixedSize()
    }

    /// Warms the scene cache for the active theme AND the Metal shader cache
    /// by doing an offscreen render. Await this before rendering the card so
    /// callers can show a placeholder until the env is ready.
    @MainActor
    static func preload(displayName: String, sinceYear: String, memberSerial: String?) async {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let scene = AppleCardScene.make(
            displayName: displayName,
            sinceYear: sinceYear,
            memberSerial: memberSerial,
            isDark: isDark
        )
        AppleCardScene.warmRender(scene: scene)
    }

    /// Drops the cached USDZ scenes, environment image, and engraved text
    /// textures. Call when the Settings window closes so the Metal/SceneKit
    /// memory footprint (~100s of MB) doesn't linger for the rest of the
    /// session.
    @MainActor
    static func purge() {
        AppleCardScene.purge()
    }

}

// MARK: - SceneKit Card

private struct AutoSpinCardSceneView: NSViewRepresentable {
    let displayName: String
    let sinceYear: String
    let memberSerial: String?
    let isDark: Bool

    func makeNSView(context: Context) -> SCNView {
        let view = SafeCardSCNView(frame: CGRect(x: 0, y: 0, width: 440, height: 278))
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling16X
        view.autoenablesDefaultLighting = false
        view.isJitteringEnabled = false
        view.scene = AppleCardScene.make(
            displayName: displayName,
            sinceYear: sinceYear,
            memberSerial: memberSerial,
            isDark: isDark
        )
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        AppleCardScene.update(
            view: nsView,
            displayName: displayName,
            sinceYear: sinceYear,
            memberSerial: memberSerial,
            isDark: isDark
        )
    }
}

// MARK: - Safe SCNView

private final class SafeCardSCNView: SCNView {
    private var lastLocation: CGPoint?
    private var idleCenterY: CGFloat = 0
    private var didDrag = false
    private var dragSamples: [(dx: CGFloat, time: CFTimeInterval)] = []

    private static let dragSensitivity: CGFloat = 0.012
    private static let flingTau: CGFloat = 1.0
    private static let flingDuration: CGFloat = 3.0
    private static let maxFlingVelocity: CGFloat = 20.0

    override var acceptsFirstResponder: Bool { true }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            isPlaying = false
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, bounds.width > 0, bounds.height > 0 {
            isPlaying = true
            startIdleSway()
        }
    }

    override func layout() {
        super.layout()
        if let layer = layer as? CAMetalLayer {
            let size = bounds.size
            layer.isHidden = size.width <= 0 || size.height <= 0
        }
        if window != nil, bounds.width > 0, bounds.height > 0, !isPlaying {
            isPlaying = true
        }
    }

    private var cardNode: SCNNode? {
        scene?.rootNode.childNode(withName: "card", recursively: false)
    }

    fileprivate func startIdleSway() {
        guard let card = cardNode, card.action(forKey: "idleSway") == nil else { return }
        let center = idleCenterY
        let left = SCNAction.rotateTo(x: 0, y: center - 0.12, z: 0, duration: 2.8, usesShortestUnitArc: false)
        left.timingMode = .easeInEaseOut
        let right = SCNAction.rotateTo(x: 0, y: center + 0.12, z: 0, duration: 2.8, usesShortestUnitArc: false)
        right.timingMode = .easeInEaseOut
        card.runAction(.repeatForever(.sequence([left, right])), forKey: "idleSway")
    }

    private func stopIdleSway() {
        cardNode?.removeAction(forKey: "idleSway")
    }

    override func mouseDown(with event: NSEvent) {
        if let card = cardNode {
            card.removeAllActions()
            card.eulerAngles = card.presentation.eulerAngles
        }
        lastLocation = convert(event.locationInWindow, from: nil)
        didDrag = false
        dragSamples.removeAll()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastLocation, let card = cardNode else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let dx = loc.x - last.x
        let dy = loc.y - last.y
        lastLocation = loc
        didDrag = true

        let tiltLimit: CGFloat = .pi / 5
        var angles = card.eulerAngles
        angles.y += dx * Self.dragSensitivity
        let tiltX = angles.x - dy * Self.dragSensitivity
        angles.x = max(-tiltLimit, min(tiltLimit, tiltX))
        angles.z = 0
        card.eulerAngles = angles

        dragSamples.append((dx: dx, time: CACurrentMediaTime()))
        if dragSamples.count > 5 { dragSamples.removeFirst(dragSamples.count - 5) }
    }

    override func mouseUp(with event: NSEvent) {
        lastLocation = nil
        guard let card = cardNode else { return }

        guard didDrag else {
            startIdleSway()
            return
        }
        didDrag = false

        let startX = card.eulerAngles.x
        let startY = card.eulerAngles.y

        var velocity: CGFloat = 0
        if dragSamples.count >= 2,
           let first = dragSamples.first,
           let last = dragSamples.last {
            let span = last.time - first.time
            if span > 0.001 {
                let totalDx = dragSamples.dropFirst().reduce(0) { $0 + $1.dx }
                velocity = (totalDx / span) * Self.dragSensitivity
            }
        }
        velocity = max(-Self.maxFlingVelocity, min(Self.maxFlingVelocity, velocity))
        dragSamples.removeAll()

        let naturalEnd = startY + velocity * Self.flingTau
        let steps = (naturalEnd / .pi).rounded(.toNearestOrAwayFromZero)
        let targetY = steps * .pi
        idleCenterY = targetY

        let duration = Self.flingDuration
        let settle = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = min(max(elapsed / duration, 0), 1)
            let eased = 1 - pow(1 - t, 4)
            node.eulerAngles = SCNVector3(
                startX * (1 - eased),
                startY + (targetY - startY) * eased,
                0
            )
        }
        card.runAction(settle) { [weak self] in
            Task { @MainActor [weak self] in
                self?.startIdleSway()
            }
        }
    }

}

// MARK: - Scene Builder

private enum AppleCardScene {
    private static let targetCardWidth: CGFloat = 8.56

    // Cache the USDZ load for the currently-rendered theme only — the heaviest
    // single cost per render. Scenes clone nodes out of this cache instead of
    // re-parsing. A theme flip evicts and reloads, so only one copy is resident
    // at a time. Held as a reassignable var so `purge()` can release it.
    @MainActor private static var cachedUSDZ: (scene: SCNScene, isDark: Bool)?
    @MainActor private static var cachedEnvironment: NSImage?

    @MainActor private static var frontImageCache: [String: NSImage] = [:]
    @MainActor private static var backImageCache: [String: NSImage] = [:]
    @MainActor private static var shadersWarmed = false

    @MainActor
    static func purge() {
        cachedUSDZ = nil
        cachedEnvironment = nil
        frontImageCache.removeAll()
        backImageCache.removeAll()
        shadersWarmed = false
    }

    @MainActor
    private static func loadUSDZ(isDark: Bool) -> SCNScene? {
        if let cached = cachedUSDZ, cached.isDark == isDark {
            return cached.scene
        }
        let resource = isDark ? "apple_card_dark" : "apple_card"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: [.checkConsistency: false]) else {
            cachedUSDZ = nil
            return nil
        }
        cachedUSDZ = (scene, isDark)
        return scene
    }

    /// Synthetic equirectangular environment with a warm gold hot-band across
    /// the top. Metallic surfaces reflect this and pick up the gold tone.
    @MainActor
    private static func environmentImage() -> NSImage {
        if let cached = cachedEnvironment { return cached }
        let image = makeEnvironmentImage()
        cachedEnvironment = image
        return image
    }

    @MainActor
    private static func makeEnvironmentImage() -> NSImage {
        let size = CGSize(width: 1024, height: 512)
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

        ctx.setFillColor(NSColor(calibratedRed: 0.22, green: 0.22, blue: 0.24, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        let bandCenterY = size.height * 0.78
        let bandHalfHeight: CGFloat = size.height * 0.12
        let hotColor = NSColor(calibratedRed: 0.92, green: 0.86, blue: 0.72, alpha: 1)
        let midColor = NSColor(calibratedRed: 0.55, green: 0.50, blue: 0.42, alpha: 1)
        let edgeColor = NSColor(calibratedRed: 0.22, green: 0.22, blue: 0.24, alpha: 1)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let bandGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                edgeColor.cgColor,
                midColor.cgColor,
                hotColor.cgColor,
                hotColor.cgColor,
                midColor.cgColor,
                edgeColor.cgColor,
            ] as CFArray,
            locations: [0.0, 0.35, 0.48, 0.52, 0.65, 1.0]
        ) {
            ctx.drawLinearGradient(
                bandGradient,
                start: CGPoint(x: 0, y: bandCenterY - bandHalfHeight),
                end: CGPoint(x: 0, y: bandCenterY + bandHalfHeight),
                options: []
            )
        }
        return image
    }

    @MainActor
    static func make(displayName: String, sinceYear: String, memberSerial: String?, isDark: Bool) -> SCNScene {
        let scene = SCNScene()

        // Spinner root — rotations/animations happen here, no scale applied.
        let card = SCNNode()
        card.name = "card"
        card.setValue(isDark, forKey: "themeIsDark")
        scene.rootNode.addChildNode(card)

        // Scaled USDZ model lives in its own child so its scale doesn't
        // propagate to the text nodes we attach alongside it.
        let model = SCNNode()
        model.name = "model"
        card.addChildNode(model)

        var cardHalfWidth: CGFloat = targetCardWidth / 2
        var cardHalfHeight: CGFloat = (targetCardWidth / 1.586) / 2
        var cardFrontZ: CGFloat = 0.1

        if let loaded = loadUSDZ(isDark: isDark) {
            for child in loaded.rootNode.childNodes {
                // Deep-clone so we don't reparent out of the cache.
                model.addChildNode(child.clone())
            }
            stripLightsAndCameras(from: model)
            forcePhysicallyBasedMaterials(on: model)
            let bounds = normalizeAndMeasure(model)
            cardHalfWidth = bounds.halfWidth
            cardHalfHeight = bounds.halfHeight
            cardFrontZ = bounds.frontZ + 0.015
        }

        addTextOverlays(
            to: card,
            displayName: displayName,
            sinceYear: sinceYear,
            halfWidth: cardHalfWidth,
            halfHeight: cardHalfHeight,
            frontZ: cardFrontZ,
            isDark: isDark
        )

        addBackOverlay(
            to: card,
            sinceYear: sinceYear,
            memberSerial: memberSerial,
            halfWidth: cardHalfWidth,
            halfHeight: cardHalfHeight,
            frontZ: cardFrontZ,
            isDark: isDark
        )

        scene.lightingEnvironment.contents = environmentImage()
        scene.lightingEnvironment.intensity = 1.2

        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 300
        keyLight.castsShadow = false
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.eulerAngles = SCNVector3(-CGFloat.pi / 5, CGFloat.pi / 6, 0)
        scene.rootNode.addChildNode(keyNode)

        let fillLight = SCNLight()
        fillLight.type = .directional
        fillLight.intensity = 250
        fillLight.color = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        let fillNode = SCNNode()
        fillNode.light = fillLight
        fillNode.eulerAngles = SCNVector3(CGFloat.pi / 6, -CGFloat.pi / 4, 0)
        scene.rootNode.addChildNode(fillNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 180
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let camera = SCNCamera()
        camera.fieldOfView = 24
        camera.projectionDirection = .horizontal
        camera.zNear = 0.1
        camera.zFar = 100
        camera.bloomIntensity = 0.6
        camera.bloomBlurRadius = 5
        camera.bloomThreshold = 0.85
        camera.contrast = 0.5
        camera.saturation = 1.05
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 25)
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    @MainActor
    static func update(view: SCNView, displayName: String, sinceYear: String, memberSerial: String?, isDark: Bool) {
        // If the theme flipped, the USDZ model itself changes — cheapest path
        // is to rebuild the scene (both sides are cached so it's effectively
        // free). For same-theme text-only updates, just swap the textures.
        if view.scene?.rootNode.childNode(withName: "card", recursively: false)?
            .value(forKey: "themeIsDark") as? Bool != isDark {
            view.scene = make(
                displayName: displayName,
                sinceYear: sinceYear,
                memberSerial: memberSerial,
                isDark: isDark
            )
            return
        }

        guard let card = view.scene?.rootNode.childNode(withName: "card", recursively: false) else { return }

        if let overlay = card.childNode(withName: "textOverlay", recursively: false),
           let material = overlay.geometry?.firstMaterial {
            material.diffuse.contents = engravedOverlayImage(
                displayName: displayName,
                sinceYear: sinceYear,
                isDark: isDark
            )
        }

        if let backOverlay = card.childNode(withName: "backTextOverlay", recursively: false),
           let material = backOverlay.geometry?.firstMaterial {
            material.diffuse.contents = engravedBackImage(
                sinceYear: sinceYear,
                memberSerial: memberSerial,
                isDark: isDark
            )
        }
    }

    // MARK: - Engraved Text Overlay

    /// Forces Metal to compile the shader variants needed for this scene by
    /// rendering one offscreen frame. No-op once warmed until `purge()` resets
    /// the flag — shader compilation only matters once per cache lifetime.
    @MainActor
    static func warmRender(scene: SCNScene) {
        guard !shadersWarmed else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = false
        _ = renderer.snapshot(
            atTime: 0,
            with: CGSize(width: 440, height: 278),
            antialiasingMode: .multisampling4X
        )
        shadersWarmed = true
    }

    @MainActor
    private static func addTextOverlays(
        to card: SCNNode,
        displayName: String,
        sinceYear: String,
        halfWidth: CGFloat,
        halfHeight: CGFloat,
        frontZ: CGFloat,
        isDark: Bool
    ) {
        let plane = SCNPlane(width: halfWidth * 2, height: halfHeight * 2)
        plane.cornerRadius = min(halfWidth, halfHeight) * 0.08

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.isDoubleSided = false
        material.diffuse.contents = engravedOverlayImage(displayName: displayName, sinceYear: sinceYear, isDark: isDark)
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.metalness.contents = 0.85
        material.roughness.contents = 0.35
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        plane.firstMaterial = material

        let node = SCNNode(geometry: plane)
        node.name = "textOverlay"
        node.position = SCNVector3(0, 0, frontZ + 0.005)
        node.renderingOrder = 10
        card.addChildNode(node)
    }

    // MARK: - Back Overlay

    @MainActor
    private static func addBackOverlay(
        to card: SCNNode,
        sinceYear: String,
        memberSerial: String?,
        halfWidth: CGFloat,
        halfHeight: CGFloat,
        frontZ: CGFloat,
        isDark: Bool
    ) {
        let plane = SCNPlane(width: halfWidth * 2, height: halfHeight * 2)
        plane.cornerRadius = min(halfWidth, halfHeight) * 0.08

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.isDoubleSided = false
        material.diffuse.contents = engravedBackImage(
            sinceYear: sinceYear,
            memberSerial: memberSerial,
            isDark: isDark
        )
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.metalness.contents = 0.85
        material.roughness.contents = 0.35
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        plane.firstMaterial = material

        let node = SCNNode(geometry: plane)
        node.name = "backTextOverlay"
        node.position = SCNVector3(0, 0, -(frontZ + 0.005))
        // Rotate 180° around Y so the plane's normal faces the back of the
        // card. The double mirror (plane + card flip) leaves text readable.
        node.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
        node.renderingOrder = 10
        card.addChildNode(node)
    }

    @MainActor
    private static func engravedBackImage(sinceYear: String, memberSerial: String?, isDark: Bool) -> NSImage {
        let key = "\(memberSerial ?? "dedication-\(sinceYear)")|\(isDark ? "d" : "l")"
        if let cached = backImageCache[key] { return cached }
        let size = CGSize(width: 2048, height: 1291)
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        ctx.clear(CGRect(origin: .zero, size: size))

        let palette = engravePalette(isDark: isDark)
        let inkColor = palette.ink
        let highlightColor = palette.highlight

        if let memberSerial {
            let labelFont = NSFont.systemFont(ofSize: 54, weight: .bold)
            drawEngravedText(
                "FOUNDING MEMBER",
                at: CGPoint(x: 0, y: drawY(forCapCenter: size.height / 2 + 130, font: labelFont)),
                font: labelFont,
                kern: 8,
                ink: inkColor,
                highlight: highlightColor,
                alignment: .center,
                containerWidth: size.width
            )

            let serialFont = NSFont.systemFont(ofSize: 148, weight: .semibold)
            drawEngravedText(
                "No. \(memberSerial)",
                at: CGPoint(x: 0, y: drawY(forCapCenter: size.height / 2 - 20, font: serialFont)),
                font: serialFont,
                kern: 2,
                ink: inkColor,
                highlight: highlightColor,
                alignment: .center,
                containerWidth: size.width
            )
        } else {
            let messageFont = NSFont.systemFont(ofSize: 72, weight: .regular)
            drawEngravedText(
                "Thanks for being here.",
                at: CGPoint(x: 0, y: drawY(forCapCenter: size.height / 2 + 20, font: messageFont)),
                font: messageFont,
                kern: 0.5,
                ink: inkColor,
                highlight: highlightColor,
                alignment: .center,
                containerWidth: size.width
            )

            let labelFont = NSFont.systemFont(ofSize: 36, weight: .semibold)
            drawEngravedText(
                "MEMBER SINCE \(sinceYear)",
                at: CGPoint(x: 0, y: drawY(forCapCenter: size.height / 2 - 80, font: labelFont)),
                font: labelFont,
                kern: 7,
                ink: inkColor,
                highlight: highlightColor,
                alignment: .center,
                containerWidth: size.width
            )
        }

        backImageCache[key] = image
        return image
    }

    @MainActor
    private static func engravedOverlayImage(displayName: String, sinceYear: String, isDark: Bool) -> NSImage {
        let key = "\(displayName)|\(sinceYear)|\(isDark ? "d" : "l")"
        if let cached = frontImageCache[key] { return cached }
        let size = CGSize(width: 2048, height: 1291)
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        ctx.clear(CGRect(origin: .zero, size: size))

        let palette = engravePalette(isDark: isDark)
        let inkColor = palette.ink
        let highlightColor = palette.highlight
        let margin: CGFloat = 120

        // Top-left: "QUARRY PRO" tier label (small, matches SINCE styling)
        let tierFont = NSFont.systemFont(ofSize: 56, weight: .bold)
        let topCapCenter: CGFloat = size.height - margin - tierFont.capHeight / 2
        drawEngravedText(
            "QUARRY PRO",
            at: CGPoint(x: margin, y: drawY(forCapCenter: topCapCenter, font: tierFont)),
            font: tierFont,
            kern: 6,
            ink: inkColor,
            highlight: highlightColor,
            alignment: .left,
            containerWidth: size.width - margin * 2
        )

        // Top-right: SINCE year — cap center matches QUARRY PRO
        drawEngravedText(
            "SINCE \(sinceYear)",
            at: CGPoint(x: margin, y: drawY(forCapCenter: topCapCenter, font: tierFont)),
            font: tierFont,
            kern: 6,
            ink: inkColor,
            highlight: highlightColor,
            alignment: .right,
            containerWidth: size.width - margin * 2
        )

        // Directly below QUARRY PRO: display name (prominent)
        let nameFont = NSFont.systemFont(ofSize: 124, weight: .semibold)
        let nameCapCenter: CGFloat = topCapCenter - tierFont.capHeight / 2 - 120 - nameFont.capHeight / 2
        drawEngravedText(
            displayName,
            at: CGPoint(x: margin, y: drawY(forCapCenter: nameCapCenter, font: nameFont)),
            font: nameFont,
            kern: 0,
            ink: inkColor,
            highlight: highlightColor,
            alignment: .left,
            containerWidth: size.width - margin * 2
        )

        // Bottom-left: Quarry logo + wordmark
        let logoSize: CGFloat = 105
        let logoRect = CGRect(
            x: margin,
            y: margin - 6,
            width: logoSize,
            height: logoSize
        )
        drawEngravedLogo(in: logoRect, ink: inkColor, highlight: highlightColor)

        let wordmarkFont = NSFont.systemFont(ofSize: 90, weight: .semibold)
        drawEngravedText(
            "Quarry",
            at: CGPoint(x: logoRect.maxX + 26, y: drawY(forCapCenter: logoRect.midY, font: wordmarkFont)),
            font: wordmarkFont,
            kern: 0,
            ink: inkColor,
            highlight: highlightColor,
            alignment: .left,
            containerWidth: size.width - margin * 2
        )

        frontImageCache[key] = image
        return image
    }

    private struct EngravePalette {
        let ink: NSColor
        let highlight: NSColor
    }

    private static func engravePalette(isDark: Bool) -> EngravePalette {
        if isDark {
            return EngravePalette(
                ink: NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.88, alpha: 0.92),
                highlight: NSColor(calibratedWhite: 0.0, alpha: 0.42)
            )
        } else {
            return EngravePalette(
                ink: NSColor(calibratedRed: 0.38, green: 0.40, blue: 0.44, alpha: 0.92),
                highlight: NSColor(calibratedWhite: 1.0, alpha: 0.32)
            )
        }
    }

    /// Returns the y position to pass to `NSAttributedString.draw(at:)` so the
    /// rendered cap-height center sits at `center`. `.draw(at:)` in a
    /// non-flipped context treats the y as the bottom of the bounding box;
    /// baseline is above that by `|descender|`, and cap center is above
    /// baseline by `capHeight / 2`.
    private static func drawY(forCapCenter center: CGFloat, font: NSFont) -> CGFloat {
        center - font.capHeight / 2 - abs(font.descender)
    }

    private static func drawEngravedText(
        _ string: String,
        at origin: CGPoint,
        font: NSFont,
        kern: CGFloat,
        ink: NSColor,
        highlight: NSColor,
        alignment: NSTextAlignment,
        containerWidth: CGFloat
    ) {
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: kern,
        ]

        let probe = NSAttributedString(string: string, attributes: baseAttrs)
        let textSize = probe.size()
        let drawX: CGFloat = {
            switch alignment {
            case .right: return origin.x + containerWidth - textSize.width
            case .center: return origin.x + (containerWidth - textSize.width) / 2
            default: return origin.x
            }
        }()
        let drawPoint = CGPoint(x: drawX, y: origin.y)

        var highlightAttrs = baseAttrs
        highlightAttrs[.foregroundColor] = highlight
        NSAttributedString(string: string, attributes: highlightAttrs)
            .draw(at: CGPoint(x: drawPoint.x + 1, y: drawPoint.y - 1.5))

        var inkAttrs = baseAttrs
        inkAttrs[.foregroundColor] = ink
        NSAttributedString(string: string, attributes: inkAttrs)
            .draw(at: drawPoint)
    }

    private static func drawEngravedLogo(in rect: CGRect, ink: NSColor, highlight: NSColor) {
        guard let logo = NSImage(named: "quarry_logo_mark") else { return }

        let highlightRect = rect.offsetBy(dx: 1, dy: -1.5)
        let highlightTinted = NSImage(size: rect.size, flipped: false) { bounds in
            logo.draw(in: bounds)
            highlight.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        highlightTinted.draw(in: highlightRect)

        let inkTinted = NSImage(size: rect.size, flipped: false) { bounds in
            logo.draw(in: bounds)
            ink.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        inkTinted.draw(in: rect)
    }

    // MARK: - Loading

    private static func stripLightsAndCameras(from node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            child.light = nil
            child.camera = nil
        }
    }

    private static func forcePhysicallyBasedMaterials(on node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            child.geometry?.materials.forEach { material in
                material.lightingModel = .physicallyBased
            }
        }
    }

    private struct CardBounds {
        var halfWidth: CGFloat
        var halfHeight: CGFloat
        var frontZ: CGFloat
    }

    private static func normalizeAndMeasure(_ model: SCNNode) -> CardBounds {
        let (minVec, maxVec) = model.boundingBox
        let width = CGFloat(maxVec.x - minVec.x)
        let height = CGFloat(maxVec.y - minVec.y)
        let depth = CGFloat(maxVec.z - minVec.z)
        let largest = max(width, height, depth)
        guard largest > 0 else {
            return CardBounds(halfWidth: targetCardWidth / 2, halfHeight: (targetCardWidth / 1.586) / 2, frontZ: 0.1)
        }

        let scale = targetCardWidth / largest
        model.scale = SCNVector3(scale, scale, scale)

        let centerX = CGFloat(minVec.x + maxVec.x) / 2
        let centerY = CGFloat(minVec.y + maxVec.y) / 2
        let centerZ = CGFloat(minVec.z + maxVec.z) / 2
        for child in model.childNodes {
            child.position = SCNVector3(
                child.position.x - centerX,
                child.position.y - centerY,
                child.position.z - centerZ
            )
        }

        // After scaling + centering, the model in world space spans
        // (width * scale) on each axis, centered on origin.
        return CardBounds(
            halfWidth: (width * scale) / 2,
            halfHeight: (height * scale) / 2,
            frontZ: (depth * scale) / 2
        )
    }
}
