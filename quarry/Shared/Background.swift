//
//  Background.swift
//  Collection
//
//  Created by Fauzaan on 2/23/25.
//

import SwiftUI

struct GlassBackgroundStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 6
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background {
                    ZStack {
                        if colorScheme == .dark {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(.thinMaterial)
                            RoundedRectangle(cornerRadius: cornerRadius + 2)
                                .fill(
                                    .linearGradient(
                                        colors: [
                                            Color(.controlBackgroundColor).opacity(0.05),
                                            .clear,
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .blendMode(.plusLighter)
                        } else {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(.white)
                        }
                    }
                }
        }
    }
}

struct GlassBackgroundStyleRoundedTop: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color(.controlColor).opacity(0.15)), in: .rect(topLeadingRadius: 10, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 10))
        } else {
            content
                .background {
                    ZStack {
                        if colorScheme == .dark {
                            RoundedCorners(tl: 10, tr: 10, bl: 0, br: 0)
                                .fill(.thinMaterial)
                            RoundedCorners(tl: 10 + 2, tr: 10 + 2, bl: 0, br: 0)
                                .fill(
                                    .linearGradient(
                                        colors: [
                                            Color(.controlBackgroundColor).opacity(0.05),
                                            .clear,
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .blendMode(.plusLighter)
                        } else {
                            RoundedCorners(tl: 10, tr: 10, bl: 0, br: 0)
                                .fill(.white)
                        }
                    }
                }
        }
    }
}

struct GlassFallbackBorder<BorderShape: Shape>: ViewModifier {
    let shape: BorderShape
    let color: Color
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
        } else {
            content.overlay(
                shape.stroke(color, lineWidth: lineWidth)
            )
        }
    }
}

// MARK: - View Extension
extension View {
    func glassBackground(cornerRadius: CGFloat = 6) -> some View {
        modifier(GlassBackgroundStyle(cornerRadius: cornerRadius))
    }
    
    func glassBackgroundRoundedTop() -> some View {
        modifier(GlassBackgroundStyleRoundedTop())
    }

    func glassFallbackBorder<BorderShape: Shape>(
        _ shape: BorderShape,
        color: Color = .separator,
        lineWidth: CGFloat = 1
    ) -> some View {
        modifier(GlassFallbackBorder(shape: shape, color: color, lineWidth: lineWidth))
    }
}
