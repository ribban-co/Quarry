//
//  StatusToast.swift
//  Collection
//
//  Created by Fauzaan on 2/26/25.
//

import SwiftUI


struct StatusToast: View {
    var isLoading: Bool
    @State private var isHovering = false
    @State private var shouldShow = false
    @State private var showTask: Task<Void, Error>? = nil
    @State private var hideTask: Task<Void, Error>? = nil
    var message: String = "Fetching Documents"
    
    // Customizable timing parameters
    var showDelay: Double = 0.3
    var minimumDisplayTime: Double = 1.0
    
    var body: some View {
        HStack(spacing: 4) {
            // Advanced pulsing circle
            PulsingCircleAdvanced(color: .green)
                .frame(width: 20, height: 20)
            
            // Status message
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.trailing, 10)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            ZStack {
                // Translucent backdrop with increased transparency
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.7))
                
                // Subtle gradient overlay with reduced opacity
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.15)
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                
                // Inner subtle highlight at top edge
                Capsule()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .padding(0.5)
                
                // Subtle inner shadow
                Capsule()
                    .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                    .blur(radius: 0.5)
                    .offset(y: 0.5)
                    .mask(
                        Capsule()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.clear, .black]),
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .padding(0.5)
                    )
            }
        )
        .overlay(
            // Outer border with reduced opacity
            Capsule()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.15),
                            Color.gray.opacity(0.2),
                            Color.gray.opacity(0.25)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 0.5, x: 0, y: 0.5)
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        .offset(y: shouldShow ? 0 : -15)
        .opacity(shouldShow ? 1.0 : 0)
        .animation(
            .spring(
                response: 0.5,
                dampingFraction: 0.65,
                blendDuration: 0.1
            ),
            value: shouldShow
        )
        .onChange(of: isLoading) { oldValue, newValue in
            // Cancel any existing tasks to avoid conflicts
            showTask?.cancel()
            
            if newValue == true {
                // Start loading - delay showing the toast
                showTask = Task {
                    do {
                        try await Task.sleep(for: .seconds(showDelay))
                        // Check if we're still loading after the delay
                        if !Task.isCancelled && isLoading {
                            shouldShow = true
                        }
                    } catch {
                        // Task was cancelled, do nothing
                    }
                }
            } else if oldValue == true && newValue == false {
                // Cancel the show task if it's still pending
                showTask?.cancel()
                
                // Finished loading - ensure minimum display time only if toast is visible
                if shouldShow {
                    hideTask = Task {
                        do {
                            try await Task.sleep(for: .seconds(minimumDisplayTime))
                            if !Task.isCancelled {
                                shouldShow = false
                            }
                        } catch {
                            // Task was cancelled, do nothing
                        }
                    }
                }
            }
        }
        // Handle cleanup when view disappears
        .onDisappear {
            showTask?.cancel()
            hideTask?.cancel()
        }
    }
}
struct PulsingCircleAdvanced: View {
    @State private var isPulsing = false
    var color: Color = .green
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: color.opacity(0.3), location: 0),
                            .init(color: color.opacity(0.2), location: 0.5),
                            .init(color: .clear, location: 1)
                        ]),
                        center: .leading,
                        startRadius: 1,
                        endRadius: 180
                    )
                )
                .frame(width: 20, height: 20)
                .blur(radius: 6)
            
            // Core static circle
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            // Continuous ripple effect
            ForEach(0..<3) { index in
                Circle()
                    .stroke(color.opacity(0.7 - (Double(index) * 0.2)), lineWidth: 1.5 - (Double(index) * 0.25))
                    .scaleEffect(isPulsing ? 1 + (Double(index) * 0.5) : 0.3)
                    .opacity(isPulsing ? 0.0 : 0.8 - (Double(index) * 0.2))
                    .animation(
                        Animation.easeOut(duration: 1.2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.1),
                        value: isPulsing
                    )
            }
            
        }
        .frame(width: 20, height: 20) // Fixed containment frame
        .onAppear {
            // Start the pulsing animation
            withAnimation(
                Animation.easeOut(duration: 1.2)
                    .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
    }
}

struct StatusCircle: View {
    var color: Color = .green
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: color.opacity(0.3), location: 0),
                            .init(color: color.opacity(0.2), location: 0.5),
                            .init(color: .clear, location: 1)
                        ]),
                        center: .leading,
                        startRadius: 1,
                        endRadius: 180
                    )
                )
                .frame(width: 20, height: 20)
                .blur(radius: 6)
            
            // Core static circle
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .frame(width: 20, height: 20) // Fixed containment frame
    }
}

