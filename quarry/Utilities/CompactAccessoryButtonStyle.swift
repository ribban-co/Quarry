//
//  CompactAccessoryButtonStyle.swift
//  Collection
//
//  Created by Fauzaan on 1/5/25.
//

import SwiftUI

struct CompactAccessoryButtonStyle: ButtonStyle {
    @State private var isHovered = false
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    
    // Initialize with default padding values
    init(horizontal: CGFloat = 2, vertical: CGFloat = 2) {
        self.horizontalPadding = horizontal
        self.verticalPadding = vertical
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(configuration.isPressed ? Color.gray.opacity(0.3) :
                        isHovered ? Color.gray.opacity(0.2) :
                        Color.clear)
            .cornerRadius(4)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension ButtonStyle where Self == CompactAccessoryButtonStyle {
    /// A compact button style for accessory views like close buttons
    /// - Parameters:
    ///   - horizontal: The horizontal padding (default: 2)
    ///   - vertical: The vertical padding (default: 2)
    /// Usage: .buttonStyle(.compactAccessory())
    /// or: .buttonStyle(.compactAccessory(horizontal: 8, vertical: 4))
    static func compactAccessory(
        horizontal: CGFloat = 2,
        vertical: CGFloat = 2
    ) -> CompactAccessoryButtonStyle {
        CompactAccessoryButtonStyle(horizontal: horizontal, vertical: vertical)
    }
}

// Preview with different padding configurations
#Preview {
    VStack(spacing: 20) {
        // Default padding
        Button("Default Padding") {}
            .buttonStyle(.compactAccessory())
        
        // Custom horizontal padding
        Button("Wide Horizontal") {}
            .buttonStyle(.compactAccessory(horizontal: 16, vertical: 2))
        
        // Custom vertical padding
        Button("Tall Vertical") {}
            .buttonStyle(.compactAccessory(horizontal: 2, vertical: 8))
        
        // Custom both
        Button("Custom Both") {}
            .buttonStyle(.compactAccessory(horizontal: 12, vertical: 6))
    }
}
