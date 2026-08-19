//
//  AboutView.swift
//  Quarry
//
//  Created by Fauzaan on 4/26/25.
//
import AppKit

class AboutWindowController: NSWindowController {

    convenience init() {
        let window = AboutWindowController.createAboutWindow()
        self.init(window: window)
    }

    static func createAboutWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 150),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false

        // Create visual effect view with thin material
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow

        // Create horizontal stack view for icon and text
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // App Icon
        let iconView = NSImageView()
        if let appIcon = NSApplication.shared.applicationIconImage {
            iconView.image = appIcon
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.wantsLayer = true
            iconView.layer?.cornerRadius = 16
            iconView.layer?.masksToBounds = true
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 84),
            iconView.heightAnchor.constraint(equalToConstant: 84)
        ])

        // Text stack (vertical)
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0

        // App Name
        let nameLabel = NSTextField(labelWithString: "Quarry")
        nameLabel.font = NSFont.systemFont(ofSize: 28, weight: .regular)
        nameLabel.isBordered = false
        nameLabel.isEditable = false
        nameLabel.backgroundColor = .clear

        // Version
        let version = Bundle.main.appVersion
        let build = Bundle.main.buildNumber
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.isSelectable = true
        versionLabel.isBordered = false
        versionLabel.isEditable = false
        versionLabel.backgroundColor = .clear

        // Copyright
        let currentYear = Date.now.formatted(.dateTime.year())
        let copyrightLabel = NSTextField(
            wrappingLabelWithString: "Copyright © \(currentYear) RIBBAN AB. Based on Pluk, © Pluk, Inc.\nLicensed under GNU AGPL v3.0."
        )
        copyrightLabel.font = NSFont.systemFont(ofSize: 11)
        copyrightLabel.textColor = .secondaryLabelColor
        copyrightLabel.isBordered = false
        copyrightLabel.isEditable = false
        copyrightLabel.backgroundColor = .clear
        copyrightLabel.preferredMaxLayoutWidth = 286

        // Add spacer for copyright
        let spacerView = NSView()
        spacerView.translatesAutoresizingMaskIntoConstraints = false
        spacerView.heightAnchor.constraint(equalToConstant: 10).isActive = true

        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(versionLabel)
        textStack.addArrangedSubview(spacerView)
        textStack.addArrangedSubview(copyrightLabel)

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(textStack)

        visualEffectView.addSubview(stackView)

        // Center the stack view
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: visualEffectView.leadingAnchor, constant: 30),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: visualEffectView.trailingAnchor, constant: -30)
        ])

        window.contentView = visualEffectView

        return window
    }
}
