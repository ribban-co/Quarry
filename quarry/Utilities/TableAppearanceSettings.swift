//
//  TableAppearanceSettings.swift
//  Quarry
//

import AppKit

private enum TableAppearanceDefaults {
    static let alternatingRowColorsKey = "alternatingRowColors"
    static let alternatingRowColorsDefault = true
}

@MainActor
enum TableAppearanceSettings {
    nonisolated(unsafe) private(set) static var alternatingRowColors = readAlternatingRowColors()

    nonisolated(unsafe) private static let observer: NSObjectProtocol = {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let newValue = readAlternatingRowColors()
            if newValue != alternatingRowColors {
                alternatingRowColors = newValue
                NotificationCenter.default.post(name: .tableReloadData, object: nil)
            }
        }
    }()

    nonisolated(unsafe) private static let appearanceObserver: NSObjectProtocol = {
        NotificationCenter.default.addObserver(
            forName: .appAppearanceDidChange,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .tableReloadData, object: nil)
        }
    }()

    static func initialize() {
        alternatingRowColors = readAlternatingRowColors()
        _ = observer
        _ = appearanceObserver
    }

    nonisolated private static func readAlternatingRowColors() -> Bool {
        UserDefaults.standard.object(forKey: TableAppearanceDefaults.alternatingRowColorsKey) as? Bool
            ?? TableAppearanceDefaults.alternatingRowColorsDefault
    }
}

extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension NSColor {
    static var cellModificationColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDarkMode
                ? NSColor(red: 0x7C/255.0, green: 0x59/255.0, blue: 0x2C/255.0, alpha: 1.0)
                : NSColor(red: 0xFF/255.0, green: 0xE5/255.0, blue: 0x99/255.0, alpha: 1.0)
        }
    }

    static var alternatingRowStripeColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDarkMode
                ? NSColor.white.withAlphaComponent(0.02)
                : NSColor.black.withAlphaComponent(0.02)
        }
    }
}
