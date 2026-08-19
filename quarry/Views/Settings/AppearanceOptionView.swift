//
//  AppearanceOptionView.swift
//  Quarry
//

import SwiftUI

enum AppearanceMode {
    case system
    case light
    case dark
}

struct AppearanceOptionView: View {
    let title: String
    let mode: AppearanceMode
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                switch mode {
                case .system:
                    HStack(spacing: 0) {
                        appearanceThumbnail(isDark: false)
                            .frame(width: 40)
                            .clipped()
                        appearanceThumbnail(isDark: true)
                            .frame(width: 40)
                            .clipped()
                    }
                case .light:
                    appearanceThumbnail(isDark: false)
                case .dark:
                    appearanceThumbnail(isDark: true)
                }
            }
            .frame(width: 80, height: 52)
            .clipShape(.rect(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )

            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func appearanceThumbnail(isDark: Bool) -> some View {
        let windowBg = isDark ? Color(white: 0.15) : Color(white: 0.92)
        let containerBg = isDark ? Color(white: 0.1) : Color.white
        let rowColor = isDark ? Color(white: 0.28) : Color(white: 0.75)

        ZStack(alignment: .topLeading) {
            // Window background
            Rectangle().fill(windowBg)

            HStack(spacing: 0) {
                // Sidebar with list rows
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(rowColor)
                            .frame(width: 14, height: 3)
                    }
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.leading, 4)
                .frame(width: 22)

                // Main container area
                RoundedRectangle(cornerRadius: 4)
                    .fill(containerBg)
                    .padding(.top, 10)
                    .padding(.trailing, 3)
                    .padding(.bottom, 3)
            }

            // Traffic lights
            HStack(spacing: 1.5) {
                Circle().fill(Color.red).frame(width: 4, height: 4)
                Circle().fill(Color.yellow).frame(width: 4, height: 4)
                Circle().fill(Color.green).frame(width: 4, height: 4)
            }
            .padding(.leading, 4)
            .padding(.top, 4)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        AppearanceOptionView(title: "System", mode: .system, isSelected: true)
        AppearanceOptionView(title: "Light", mode: .light, isSelected: false)
        AppearanceOptionView(title: "Dark", mode: .dark, isSelected: false)
    }
    .padding(30)
    .background(Color(nsColor: .windowBackgroundColor))
}
