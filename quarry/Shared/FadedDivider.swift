//
//  FadedDivider.swift
//  Collection
//
//  Created by Fauzaan on 3/8/25.
//

import SwiftUI

struct SoftSeparator: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(NSColor.separatorColor).opacity(0), location: 0),
                .init(color: Color(NSColor.separatorColor), location: 0.2),
                .init(color: Color(NSColor.separatorColor), location: 0.5),
                .init(color: Color(NSColor.separatorColor).opacity(0), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.horizontal, 8)
    }
}
