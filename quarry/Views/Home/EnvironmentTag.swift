//
//  EnvironmentTag.swift
//  Collection
//
//  Created by Fauzaan on 2/9/25.
//

import SwiftUI

extension ConnectionEnvironment {
    var color: Color {
        switch self {
        case .local: AccentColor.emerald.color
        case .testing: AccentColor.ocean.color
        case .development: AccentColor.indigo.color
        case .staging: AccentColor.coral.color
        case .production: AccentColor.ruby.color
        }
    }

    var labelStrokeColor: Color {
        switch self {
        case .production:
            color.opacity(0.95)
        default:
            color.opacity(0.82)
        }
    }
}

struct EnvironmentTag: View {
    let environment: ConnectionEnvironment

    var body: some View {
        Text(environment.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(environment.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(environment.labelStrokeColor, lineWidth: 1)
            )
    }
}
