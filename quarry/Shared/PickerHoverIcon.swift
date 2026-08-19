//
//  PickerHoverIcon.swift
//  Quarry
//
//  Created by Fauzaan on 8/25/25.
//

import SwiftUI

struct PickerHoverIcon: ViewModifier {
    @State private var isHovered = false
    let normalIcon: String
    let hoverIcon: String
    let showNormalIcon: Bool
    
    init(normalIcon: String = "chevron.compact.right",
         hoverIcon: String = "chevron.compact.up.chevron.compact.down",
         weight: Font.Weight = .bold,
         showNormalIcon: Bool = true) {
        self.normalIcon = normalIcon
        self.hoverIcon = hoverIcon
        self.showNormalIcon = showNormalIcon
    }
    
    
    func body(content: Content) -> some View {
         content
             .menuIndicator(.hidden)
             .overlay(alignment: .trailing) {
                 Image(systemName: isHovered ? hoverIcon : normalIcon)
                     .foregroundColor(.secondary)
                     .font(.caption)
                     .opacity(showNormalIcon ? 1.0 : (isHovered ? 1.0 : 0.0))
                     .font(.caption.weight(.bold))
                     .allowsHitTesting(false)
                     .padding(.trailing, 4)
             }
             .onHover { hovering in
                 withAnimation(.easeInOut(duration: 0.2)) {
                     isHovered = hovering
                 }
             }
     }
}

extension View {
    func hoverMenuIndicator(normalIcon: String = "chevron.right",
                           hoverIcon: String = "chevron.up.chevron.down", showNormalIcon: Bool = false) -> some View {
        modifier(PickerHoverIcon(normalIcon: normalIcon, hoverIcon: hoverIcon, showNormalIcon: showNormalIcon))
    }
}
