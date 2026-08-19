//
//  Color.swift
//  Collection
//
//  Created by Fauzaan on 1/3/25.
//  Abstract:
//  Extended Color values used to define custom color values and assets.
//

import SwiftUI
import AppKit

extension Color {
    static var separator: Color {
        Color("separator")
    }

    static var arcInactiveStroke: Color {
        Color("arcInactiveStroke")
    }

    static var primaryButton: Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    return NSColor(red: 0xE5 / 255.0, green: 0x7E / 255.0, blue: 0x52 / 255.0, alpha: 1.0)
                }
                return NSColor(red: 0xB9 / 255.0, green: 0x55 / 255.0, blue: 0x31 / 255.0, alpha: 1.0)
            }
        )
    }
}

extension NSColor {
    static var primaryButton: NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0xE5 / 255.0, green: 0x7E / 255.0, blue: 0x52 / 255.0, alpha: 1.0)
            }
            return NSColor(red: 0xB9 / 255.0, green: 0x55 / 255.0, blue: 0x31 / 255.0, alpha: 1.0)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}


enum AccentColor {
    case coral      // MongoDB coral
    case ocean      // Blue
    case purple     // Purple
    case ruby       // Red
    case emerald    // Green
    
    case amber      // Warm yellow
    case teal       // Blue-green
    case indigo     // Deep blue-purple
    case magenta    // Pink-purple
    case lime       // Yellow-green
    case azure      // Light blue
    case crimson    // Deep red
    case violet     // Light purple
    case mint       // Light green
    case gold       // Golden yellow
    
    var color: Color {
        switch self {
        case .coral:
            return Color(red: 247/255, green: 127/255, blue: 60/255)
        case .ocean:
            return Color(red: 68/255, green: 151/255, blue: 238/255)
        case .purple:
            return Color(red: 155/255, green: 107/255, blue: 239/255)
        case .ruby:
            return Color(red: 234/255, green: 76/255, blue: 87/255)
        case .emerald:
            return Color(red: 71/255, green: 186/255, blue: 127/255)
        case .amber:
            return Color(red: 251/255, green: 191/255, blue: 36/255)
        case .teal:
            return Color(red: 45/255, green: 212/255, blue: 191/255)
        case .indigo:
            return Color(red: 99/255, green: 102/255, blue: 241/255)
        case .magenta:
            return Color(red: 236/255, green: 72/255, blue: 153/255)
        case .lime:
            return Color(red: 132/255, green: 204/255, blue: 22/255)
        case .azure:
            return Color(red: 56/255, green: 189/255, blue: 248/255)
        case .crimson:
            return Color(red: 220/255, green: 38/255, blue: 38/255)
        case .violet:
            return Color(red: 167/255, green: 139/255, blue: 250/255)
        case .mint:
            return Color(red: 34/255, green: 197/255, blue: 94/255)
        case .gold:
            return Color(red: 234/255, green: 179/255, blue: 8/255)
        }
    }
    
    static func random() -> Color {
        let colors: [AccentColor] = [
            .coral, .ocean, .purple, .ruby, .emerald,
            .amber, .teal, .indigo, .magenta, .lime,
            .azure, .crimson, .violet, .mint, .gold
        ]
        return colors.randomElement()!.color
    }
}
