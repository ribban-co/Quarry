//
//  TwoPhaseLoader.swift
//  Quarry
//
//  Created by Fauzaan on 6/18/25.
//
import SwiftUI

struct TwoPhaseLoader: View {
    @State private var progress: CGFloat = 0
    @State private var opacity: Double = 1.0
    var containerWidth: CGFloat = 286
    let isLoading: Bool
    let cornerRadius: CGFloat
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main progress bar with gradient and heat trail effect
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 1.0, green: 0.3, blue: 0.0), // Bright red-orange
                            Color(red: 1.0, green: 0.5, blue: 0.0), // Orange
                            Color(red: 1.0, green: 0.6, blue: 0.2)  // Lighter orange
                        ]),
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                )
                .frame(width: containerWidth * progress, height: 1.5)
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.7),
                            .init(color: .black.opacity(0.8), location: 0.85),
                            .init(color: .black.opacity(0.4), location: 0.95),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                )
                .shadow(color: Color(red: 1.0, green: 0.4, blue: 0.0).opacity(0.6), radius: 8, x: 0, y: 0)
                .shadow(color: Color(red: 1.0, green: 0.4, blue: 0.0).opacity(0.3), radius: 16, x: 0, y: 0)
            
            // Heat trail glow effect
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 1.0, green: 0.4, blue: 0.0).opacity(0.3), location: 0),
                            .init(color: Color(red: 1.0, green: 0.5, blue: 0.0).opacity(0.15), location: 0.95),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: containerWidth * progress, height: 4)
                .blur(radius: 3)

            if progress != 0 {
                Rectangle()
                    .fill(.brand)
                    .opacity(0.05)
                    .frame(width: containerWidth)
            }
        }
        .opacity(opacity)
        .onAppear {
            if isLoading == true {
                // Phase 1: Initial load to 15% (no animation to avoid center-out effect)
                progress = 0.15
                opacity = 1.0
            }
        }
        .cornerRadius(cornerRadius)
        .onChange(of: isLoading) { oldValue, newValue in
            if newValue {
                // Only reset to 15% if we were previously hidden or completed
                if opacity == 0.0 || progress >= 1.0 || progress == 0.0 {
                    // Fresh start - show immediately at 15% (no animation to prevent slide-in effect)
                    opacity = 1.0
                    progress = 0.15  // Set directly without animation
                } else {
                    // Already visible and in progress - just ensure we're visible
                    // Keep current progress to avoid jarring jump back
                    opacity = 1.0
                    // Small animation to show we're refreshing
                    withAnimation(.easeOut(duration: 0.02)) {
                        progress = 0.15
                    }
                }
            } else {
                // Loading finished - complete to 100% and schedule hide
                withAnimation(.easeInOut(duration: 0.05)) {
                    progress = 1.0
                }
                
                withAnimation(.linear(duration: 0.1).delay(0.7)) {
                    if !isLoading {
                        opacity = 0.0
                    }
                }
            }
        }
    }
}

// MARK: - Usage Example
struct ContentView: View {
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Loader at the top
            TwoPhaseLoader(containerWidth: 200, isLoading: isLoading, cornerRadius: 12)
            
            // Your main content
            VStack {
                Text("Your Content Here")
                    .font(.title)
                    .padding()
                
                Button(isLoading ? "Complete Loading" : "Start Loading") {
                    isLoading.toggle()
                }
                .padding()
                .cornerRadius(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ContentView()
}
