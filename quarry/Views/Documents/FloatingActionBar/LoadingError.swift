//
//  LoadingAnimation.swift
//  Quarry
//
//  Created by Fauzaan on 4/12/25.
//
//
//  LoadingErrorIndicator.swift
//  Quarry
//
//  Created by Fauzaan on 4/12/25.
//
import SwiftUI

struct LoadingErrorIndicator: View {
    let cornerRadius: CGFloat
    var statusColor: Color = .red
    var height: CGFloat = 6
    var animationDuration: Double = 1.5
    
    @State private var bubbleOffset = CGSize.zero
    
    var body: some View {
        Color.clear
            .background(
                ZStack {
                    // Base background
                    statusColor.opacity(0.15)
                    
                    // Moving bubble with dynamic color
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(stops: [
                                    .init(color: statusColor.opacity(0.8), location: 0),
                                    .init(color: statusColor.opacity(0.4), location: 0.5),
                                    .init(color: .clear, location: 1)
                                ]),
                                center: .leading,
                                startRadius: 1,
                                endRadius: 120
                            )
                        )
                        .blendMode(.multiply)
                        .frame(width: 240, height: 240)
                        .blur(radius: 30)
                        .offset(bubbleOffset)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 8)
                                .repeatForever(autoreverses: true)
                            ) {
                                bubbleOffset = CGSize(width: 50, height: 20)
                            }
                            
                            withAnimation(
                                .easeInOut(duration: 6)
                                .repeatForever(autoreverses: true)
                                .delay(1)
                            ) {
                                bubbleOffset.height = -20
                            }
                        }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

