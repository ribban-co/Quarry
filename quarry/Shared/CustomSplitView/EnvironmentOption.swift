//
//  EnvironmentOptions.swift
//  Collection
//
//  Created by Fauzaan on 1/16/25.
//
import SwiftUI

private enum EnvironmentMenuLabelMetrics {
    static let minHeight: CGFloat = 32
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 10
    static let hoverAnimation = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.2)
}

// MARK: - Environment value to reserve leading space for overlay controls
struct LeadingOverlayWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var leadingOverlayWidth: CGFloat {
        get { self[LeadingOverlayWidthKey.self] }
        set { self[LeadingOverlayWidthKey.self] = newValue }
    }
}

// MARK: - Environment value for current database type
struct CurrentDatabaseTypeKey: EnvironmentKey {
    static let defaultValue: DatabaseType? = nil
}

extension EnvironmentValues {
    var currentDatabaseType: DatabaseType? {
        get { self[CurrentDatabaseTypeKey.self] }
        set { self[CurrentDatabaseTypeKey.self] = newValue }
    }
}

// MARK: - Hoverable Menu Label
struct EnvironmentMenuLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var isLoading: Bool = false
    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .font(.callout)
        .padding(.horizontal, EnvironmentMenuLabelMetrics.horizontalPadding)
        .frame(minHeight: EnvironmentMenuLabelMetrics.minHeight)
        .background(
            RoundedRectangle(cornerRadius: EnvironmentMenuLabelMetrics.cornerRadius, style: .continuous)
                .fill(hoverFillColor)
                .opacity(isHovering ? 1 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EnvironmentMenuLabelMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: EnvironmentMenuLabelMetrics.cornerRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(EnvironmentMenuLabelMetrics.hoverAnimation) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
    }

    private var hoverFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color(nsColor: .controlColor).opacity(0.8)
    }
}
