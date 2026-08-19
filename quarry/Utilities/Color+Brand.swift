//
//  Color+Brand.swift
//  Quarry
//

import SwiftUI

// Declared on ShapeStyle rather than Color so `.brand` resolves both as
// `Color.brand` and in shape-style position (.foregroundStyle, .fill, .tint) —
// the same way SwiftUI declares its own `.orange`.
extension ShapeStyle where Self == Color {
    /// Quarry's accent. Near-black in light mode, near-white in dark, so a
    /// brand-filled surface stays legible against either background.
    static var brand: Color { Color("AccentColor", bundle: .main) }

    /// Foreground to pair with a `brand` fill. Always the inverse of `brand`.
    static var onBrand: Color { Color("OnAccentColor", bundle: .main) }
}
