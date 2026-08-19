//
//  ConnectionColorPicker.swift
//  Collection
//
//  Created by Fauzaan on 2/1/25.
//
import SwiftUI

struct ConnectionColorPicker: View {
    @Binding var selectedColor: Optional<ConnectionColor>
    @Environment(\.colorScheme) var colorScheme
    @State private var isPickerPresented = false
    @State private var isHovering = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            
            Button(action: {
                isPickerPresented.toggle()
            }) {
                HStack {
                    if let color = selectedColor {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.color)
                            .frame(width: 16, height: 16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        
                        Text(color.displayName)
                    } else {
                        Text("Select a color")
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.compact.down")
                        .scaleEffect(CGSize(width: 0.7, height: 1.5))
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
                            isFocused || isHovering || isPickerPresented
                            ? (colorScheme == .dark ? Color.black : Color.white)
                                .opacity(0.2)
                            : Color.clear
                        )
                )
                .onHover { hovering in
                    isHovering = hovering
                }
            }
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .focused($isFocused)
            .buttonStyle(.plain)
            .onKeyPress(.space, phases: .down) { _ in
                isPickerPresented.toggle()
                return .handled
            }
            .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
                ColorPickerPopover(selectedColor: $selectedColor) {
                    isPickerPresented = false
                }
            }
        }
    }
}

struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer selection border
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color, lineWidth: isSelected ? 1 : 0)
                    .frame(width: 36, height: 36)  // Fixed outer frame
                
                // Main color button
                RoundedRectangle(cornerRadius: 10)
                    .fill(color)
                    .frame(width: 30, height: 30)  // Fixed inner frame
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 36, height: 36)  // Fixed container frame
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("Select color")
    }
}

struct ColorPickerPopover: View {
    @Binding var selectedColor: Optional<ConnectionColor>
    let onSelect: () -> Void
    
    private let columns = Array(repeating: GridItem(.fixed(40), spacing: 8), count: 6)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose a Color")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ConnectionColor.allCases, id: \.self) { colorOption in
                        ColorButton(
                            color: colorOption.color,
                            isSelected: selectedColor == colorOption
                        ) {
                            selectedColor = colorOption
                            onSelect()
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}


// Helper extension for hex color support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum ConnectionColor: String, CaseIterable, Codable {
    case magenta
    case turquoise
    case darkGray
    case blue
    case mint
    case lightBlue
    case lime
    case emerald
    case indigo
    case mauve
    case purple
    case pink
    case red
    case coral
    case salmon
    case orange
    case yellow
    case teal
    
    var color: Color {
        switch self {
        case .magenta: return Color(red: 236/255, green: 72/255, blue: 153/255)
        case .turquoise: return Color(red: 45/255, green: 212/255, blue: 191/255)
        case .darkGray: return Color(red: 80/255, green: 80/255, blue: 80/255)
        case .blue: return Color(red: 0/255, green: 122/255, blue: 255/255)
        case .mint: return Color(red: 34/255, green: 197/255, blue: 94/255)
        case .lightBlue: return Color(red: 56/255, green: 189/255, blue: 248/255)
        case .lime: return Color(red: 50/255, green: 205/255, blue: 50/255)
        case .emerald: return Color(red: 71/255, green: 186/255, blue: 127/255)
        case .indigo: return Color(red: 75/255, green: 0/255, blue: 130/255)
        case .mauve: return Color(red: 224/255, green: 176/255, blue: 255/255)
        case .purple: return Color(red: 153/255, green: 50/255, blue: 204/255)
        case .pink: return Color(red: 255/255, green: 105/255, blue: 180/255)
        case .red: return Color(red: 255/255, green: 59/255, blue: 48/255)
        case .coral: return Color(red: 255/255, green: 69/255, blue: 0/255)
        case .salmon: return Color(red: 255/255, green: 160/255, blue: 122/255)
        case .orange: return Color(red: 255/255, green: 149/255, blue: 0/255)
        case .yellow: return Color(red: 255/255, green: 204/255, blue: 0/255)
        case .teal: return Color(red: 0/255, green: 128/255, blue: 128/255)
        }
    }
    
    var displayName: String {
        switch self {
        case .magenta: return "Magenta"
        case .turquoise: return "Turquoise"
        case .darkGray: return "Dark Gray"
        case .blue: return "Blue"
        case .mint: return "Mint"
        case .lightBlue: return "Light Blue"
        case .lime: return "Lime"
        case .emerald: return "Emerald"
        case .indigo: return "Indigo"
        case .mauve: return "Mauve"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .coral: return "Coral"
        case .salmon: return "Salmon"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .teal: return "Teal"
        }
    }
}

