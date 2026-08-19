//
//  ViewModeToggle.swift
//  Quarry
//
//  Created by Fauzaan on 10/15/25.
//

import SwiftUI
import Foundation

struct ViewModeToggle: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var tabViewMode: DatabaseTab.ViewMode
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 4) {
            ToggleButton(
                icon: "tablecells",
                isSelected: tabViewMode == .content,
                action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        tabViewMode = .content
                    }
                },
                namespace: animation,
                id: DatabaseTab.ViewMode.content
            )
            .customHelp("Content", position: .top, shortcut: KeyboardShortcut(modifiers: [.command], key: "E"))
            ToggleButton(
                icon: "square.stack.3d.up",
                isSelected: tabViewMode == .schema,
                action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        tabViewMode = .schema
                    }
                },
                namespace: animation,
                id: DatabaseTab.ViewMode.schema
            )
            .customHelp("Schema", position: .top, shortcut: KeyboardShortcut(modifiers: [.command], key: "E"))
//            ToggleButton(
//                icon: "ellipsis.curlybraces",
//                isSelected: tabViewMode == .definition,
//                action: {
//                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//                        tabViewMode = .definition
//                    }
//                },
//                namespace: animation,
//                id: DatabaseTab.ViewMode.definition
//            )
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    colorScheme == .dark ? Color(.controlColor).opacity(0.24) :
                    Color(.separatorColor).opacity(0.70)
                )
        )
    }

    struct ToggleButton: View {
        @Environment(\.colorScheme) var colorScheme
        let icon: String
        let isSelected: Bool
        let action: () -> Void
        let namespace: Namespace.ID
        let id: DatabaseTab.ViewMode

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? id.color : Color.gray)
                    .offset(y: icon == "square.stack.3d.up" ? -1 : 0)
                    .frame(width: 28, height: 27)
                    .contentShape(Rectangle())
            }
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            colorScheme == .dark ?
                            Color(.controlColor).opacity(0.50) :
                            Color(.white)
                        )
                        .matchedGeometryEffect(id: "selector", in: namespace)
                }
            }
            .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.10), radius: 1)
            .buttonStyle(.plain)
        }
    }
}
