//
//  Button.swift
//  Collection
//
//  Created by Fauzaan on 1/18/25.
//

import SwiftUI

enum ToolbarIslandMetrics {
    static let controlHorizontalPadding: CGFloat = 7
    static let controlVerticalPadding: CGFloat = 5
    static let islandHorizontalPadding: CGFloat = 3
    static let islandVerticalPadding: CGFloat = 3
    static let cornerRadius: CGFloat = 10
    static let innerCornerRadius: CGFloat = 7
}

struct SidebarButtonStyle: ButtonStyle {
    @State private var isHovering = false
    let isActive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    (isActive || isHovering)
                    ? Color(.separatorColor)
                        .opacity(0.5)
                    : Color.clear
                )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.05)) {
                isHovering = hovering
            }
        }
    }
}

struct ActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    var padding: EdgeInsets = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
    var cornerRadius: CGFloat = 8
    var disableScaleEffect: Bool = false
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    (isHovering || isActive)
                    ? (colorScheme == .dark
                       ? Color(.controlColor).opacity(0.3)
                       : Color(.separatorColor).opacity(0.4))
                    : Color.clear
                )
        )
        .if(!disableScaleEffect) { view in
            view.scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct WorkspaceCreateButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    var cornerRadius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, ToolbarIslandMetrics.controlHorizontalPadding)
            .padding(.vertical, ToolbarIslandMetrics.controlVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isHovering
                            ? (colorScheme == .dark
                               ? Color.black.opacity(0.3)
                               : Color(.separatorColor).opacity(0.4))
                            : Color.clear
                    )
            )
            .opacity(configuration.isPressed ? 1.0 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// MARK: - Toolbar Island

/// Shared container that groups toolbar buttons into an "island" with a subtle border.
struct ToolbarIslandModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ToolbarIslandMetrics.islandHorizontalPadding)
            .padding(.vertical, ToolbarIslandMetrics.islandVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: ToolbarIslandMetrics.cornerRadius, style: .continuous)
                    .fill(toolbarIslandFillColor)
                    .shadow(color: .black.opacity(0.10), radius: 1, y: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarIslandMetrics.cornerRadius, style: .continuous)
                    .stroke(toolbarIslandBorderColor, lineWidth: 0.5)
            )
    }

    private var toolbarIslandFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : .white
    }

    private var toolbarIslandBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.08)
    }
}

extension View {
    func toolbarIsland() -> some View {
        modifier(ToolbarIslandModifier())
    }
}

struct AIBackButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @State private var isHovering = false
    var isActive: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(6)
        .background(
            RoundedCorners(tl: 8, tr: 8, bl: 8, br: 8)
                .fill(
                    isHovering
                    ? colorScheme == .dark ? Color(.controlColor).opacity(0.3) : Color(.separatorColor).opacity(0.4)
                    : Color.clear
                )
        )
        .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct XMarkButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    var padding: EdgeInsets = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
    var disableScaleEffect: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(padding)
        .background(
            Circle()
                .fill(
                    isHovering
                    ? (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(0.3)
                    : Color.clear
                )
        )
        .if(!disableScaleEffect) { view in
            view.scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct TabBarButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    (colorScheme == .dark
                     ? Color(.controlColor)
                     : Color(.secondarySystemFill))
                )
        )
    }
}

struct TabCloseButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    var padding: EdgeInsets = EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
    var disableScaleEffect: Bool = false
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    (isHovering || isActive)
                    ? (colorScheme == .dark
                       ? Color.white.opacity(0.3)
                       : Color(.secondarySystemFill))
                    : Color.clear
                )
        )
        .if(!disableScaleEffect) { view in
            view.scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct NewTabButtonStyle: ButtonStyle {
    @State private var isHovering = false
    var padding: EdgeInsets = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    var disableScaleEffect: Bool = false
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .foregroundStyle(.secondary)
        }
        .padding(padding)
        .contentShape(Rectangle())
        .modifier(NewTabGlassBackground(isHovering: isHovering, isActive: isActive))
        .if(!disableScaleEffect) { view in
            view.scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// Glass effect background for new tab button on macOS 26+
struct NewTabGlassBackground: ViewModifier {
    let isHovering: Bool
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if isHovering || isActive {
                content.glassEffect(.regular, in: .rect(cornerRadius: 8))
            } else {
                content
            }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            (isHovering || isActive)
                            ? Color(.controlColor).opacity(0.8)
                            : Color.clear
                        )
                )
        }
    }
}

struct IconButton: View {
    let systemName: String
    let isSelected: Bool
    let action: () -> Void
    let withBorder: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                    .frame(width: 50, height: 40)
                    .contentShape(Rectangle())
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(.controlColor).opacity(0.4) : .clear)
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.separator)
                            .opacity(isSelected ? 1 : 0)
                    )
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: systemName)
                            .font(.system(size: 12, weight: .semibold))
                    )
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}

struct IconButtonWithoutBorder: View {
    let systemName: String
    let isSelected: Bool
    let action: () -> Void
    let withBorder: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isHovering
                        ? (colorScheme == .dark ? Color.black : Color.white)
                            .opacity(0.3)
                        : Color.clear
                    )
                
                Image(systemName: systemName)
                    .font(.system(size: 12))
                    .opacity(0.7)
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 10).fill(
                isHovering
                ? (colorScheme == .dark ? Color.black : Color.white)
                    .opacity(0.3)
                : Color.clear
            )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}

struct DatabaseIcon: View {
    let color: Color
    let letter: String
    let isSelected: Bool
    @State private var isHovering = false
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color, lineWidth: isSelected ? 1.5 : 0)
                    .frame(width: 32, height: 32)
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Text(letter)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    static let buttonColor = Color.primaryButton
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)      // Vertical padding for height
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color(.textBackgroundColor) : .secondary)
            .background(
                // Use system accent color for native feel, or specify custom blue
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEnabled ? Self.buttonColor : Color.white.opacity(0.1))
                    .opacity(isHovering ? 0.8 : 1.0)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered in
                isHovering = isHovered
                
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct FilterSubmitButtonStyle: ButtonStyle {
    static let buttonColor = Color.primaryButton
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .foregroundStyle(isEnabled ? Color(.textBackgroundColor) : .secondary)
            .background(
                // Use system accent color for native feel, or specify custom blue
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? Self.buttonColor : Color(Self.buttonColor).opacity(0.5))
                    .opacity(isHovering ? 0.8 : 1.0)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered in
                isHovering = isHovered
                
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct ChatSendButtonStyle: ButtonStyle {
    static let buttonColor = Color.primaryButton
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)      // Vertical padding for height
            .foregroundColor(isEnabled ? Color(.textBackgroundColor) : .secondary)     // White text color
            .background(
                Circle()
                    .fill(isEnabled ? Self.buttonColor : colorScheme == .dark ? Color.white.opacity(0.1) : Color(.separatorColor).opacity(0.4))
                    .opacity(isHovering ? 0.8 : 1.0)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered in
                isHovering = isHovered
                
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    static let buttonColor = Color(.black).opacity(0.1)
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)      // Vertical padding for height
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)     // White text color
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Self.buttonColor : .clear)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered in
                isHovering = isHovered
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct CustomMenuButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isHovering
                    ? (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(0.2)
                    : Color.clear
                )
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct CustomCancelButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 32)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.primary)
        .background(Color(.controlColor).opacity(colorScheme == .dark ? 0.1 : 0.4))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isHovering
                    ? (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(0.2)
                    : Color.clear
                )
        )
        .cornerRadius(10)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct FilterDropdownStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator)
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isHovering
                    ? (colorScheme == .dark ? Color(.controlBackgroundColor) : Color.white)
                        .opacity(0.2)
                    : Color(.controlBackgroundColor).opacity(0.2)
                )
        )
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct SchemaDropdownStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator)
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(isHovering ? 0.1 : 0.2)
                )
        )
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isHovering
                    ? (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(0.2)
                    : Color.clear
                )
        )
        .cornerRadius(8)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct OutlineSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .cornerRadius(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    (colorScheme == .dark ? Color.black : Color.white).opacity(isHovering ? 0.4 : 0.2)
                )
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct DistructiveButtonStyleText: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 11)
        .cornerRadius(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isHovering
                    ? (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(0.3)
                    : Color.clear
                )
        )
        .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct HoverActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .frame(width: 12, height: 12)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isHovering
                    ? (colorScheme == .dark ? Color.black : Color.gray)
                        .opacity(0.3)
                    : Color.clear
                )
        )
        .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct HoverActionButtonStyleText: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .frame(height: 12)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isHovering
                    ? (colorScheme == .dark ? Color.black : Color.gray)
                        .opacity(0.3)
                    : Color.clear
                )
        )
        .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct RenameCancelButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .frame(height: 14)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    (colorScheme == .dark ? Color.white : Color.black)
                        .opacity(isHovering ? 0.2 : 0.1)
                )
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct RenameSaveButtonStyle: ButtonStyle {
    let backgroundColor: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    init(backgroundColor: Color = .primary) {
        self.backgroundColor = backgroundColor
    }
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .foregroundStyle(isEnabled ? Color(.textBackgroundColor) : .secondary)
        .frame(height: 14)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    backgroundColor
                        .opacity(isHovering ? 0.9 : 0.8)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct FilterClearButtonStyle: ButtonStyle {
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .offset(y: 8)
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
    }
}

// MARK: - Compact Button Styles
private struct CompactMenuButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isHovering
                    ? (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(0.2)
                    : Color.clear
                )
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct CompactPrimaryButtonStyle: ButtonStyle {
    static let buttonColor = Color.primaryButton
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isEnabled ? Color(.textBackgroundColor) : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled ? Self.buttonColor : colorScheme == .dark ? Color.white.opacity(0.1) : Color(.separatorColor).opacity(0.4))
                    .opacity(isHovering ? 0.8 : 1.0)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered in
                isHovering = isHovered
            }
    }
}

struct FileSelectionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isHovering
                        ? (colorScheme == .dark ? Color(.black) : Color(.white))
                            .opacity(0.2)
                        : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(isHovering ? 0.8 : 0.5), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
    }
}

struct FileChangeButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isHovering
                        ? (colorScheme == .dark ? Color(.black) : Color(.white))
                            .opacity(0.2)
                        : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(isHovering ? 1.0 : 0.5), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
    }
}

struct ToolbarIconButton: View {
    let systemName: String
    let action: () -> Void
    let disabled: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            isHovering && !disabled
                            ? Color(NSColor.controlBackgroundColor)
                            : Color.clear
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.separator, lineWidth: isHovering && !disabled ? 0.5 : 0)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct AICommandPromptPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isEnabled ? Color(.textBackgroundColor) : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled ? Color.primaryButton : Color.primaryButton.opacity(0.5))
                    .opacity(isHovering ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
    }
}

struct AICommandPromptSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        (colorScheme == .dark ? Color.white : Color.black)
                            .opacity(isHovering ? 0.15 : 0.08)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
    }
}

struct DeleteActionButton: View {
    let deleteCount: Int
    let isProcessingBatch: Bool
    let onDelete: () -> Void

    var body: some View {
        Button(action: onDelete) {
            HStack(alignment: .center, spacing: 4) {
                if isProcessingBatch {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 12))

                    Text("\(deleteCount)")
                        .font(.system(size: 12, weight: .light))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isProcessingBatch)
        .background(Color.red.opacity(isProcessingBatch ? 0.7 : 1))
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
        .transition(.scale.combined(with: .opacity))
        .customHelp("Delete Documents", position: .top, shortcut: KeyboardShortcut(
            modifiers: [.command],
            key: "S"
        ), spacing: 10)
    }
}

struct UpdateActionButton: View {
    let updateCount: Int
    let isProcessingBatch: Bool
    let onUpdate: () -> Void

    var body: some View {
        Button(action: onUpdate) {
            HStack(alignment: .center, spacing: 4) {
                if isProcessingBatch {
                    // Display a loading indicator when processing
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                } else {
                    Text("Save")
                        .font(.system(size: 12, weight: .light))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundColor(.onBrand)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isProcessingBatch)
        .background(Color.brand)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        .transition(.scale.combined(with: .opacity))
        .customHelp("Save Changes", position: .top, shortcut: KeyboardShortcut(
            modifiers: [.command],
            key: "S"
        ), spacing: 10)
    }
}

struct SidebarCollapseButton: ButtonStyle {
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
//        .padding(.vertical, 6)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isHovering
                    ? Color(.controlColor).opacity(0.8)
                    : Color.clear
                )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.05)) {
                isHovering = hovering
            }
        }
    }
}



extension Button {
    func primaryStyle() -> some View {
        self.buttonStyle(PrimaryButtonStyle())
    }
    
    func secondaryStyle() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }
    
    func customMenuButtonStyle() -> some View {
        self.buttonStyle(CustomMenuButtonStyle())
    }
    
    func customCancelButtonStyle() -> some View {
        self.buttonStyle(CustomCancelButtonStyle())
    }
    
    func compactMenuButtonStyle() -> some View {
        self.buttonStyle(CompactMenuButtonStyle())
    }
    
    func compactPrimaryStyle() -> some View {
        self.buttonStyle(CompactPrimaryButtonStyle())
    }
    
    func fileSelectionStyle() -> some View {
        self.buttonStyle(FileSelectionButtonStyle())
    }
    
    func fileChangeStyle() -> some View {
        self.buttonStyle(FileChangeButtonStyle())
    }
}

// MARK: - Sheet Chrome Button
// 34×34 circular button used as back / close chrome on modal sheets
// (Create Connection form, Convex OAuth view, DB selection view).
struct SheetChromeButton: View {
    let systemImage: String
    let action: () -> Void
    var keyboardShortcut: SwiftUI.KeyboardShortcut? = nil

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(Color(.tertiaryLabelColor).opacity(0.28))
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keyboardShortcut ?? .init(.escape, modifiers: []))
    }
}
