import SwiftUI

struct NotebookBetaInviteModal: View {
    let onDismiss: () -> Void
    let onTryNotebook: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didAnimateIn = false
    @State private var showGreeting = false
    @State private var showPrompt = false
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            NotebookBetaInviteHero(
                showGreeting: showGreeting,
                showPrompt: showPrompt
            )

            NotebookBetaInviteDetails(
                isVisible: showDetails,
                onDismiss: onDismiss,
                onTryNotebook: onTryNotebook
            )
        }
        .frame(width: 560)
        .task {
            await animateInIfNeeded()
        }
    }

    @MainActor
    private func animateInIfNeeded() async {
        guard !didAnimateIn else { return }
        didAnimateIn = true

        if reduceMotion {
            showGreeting = true
            showPrompt = true
            showDetails = true
            return
        }

        withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
            showGreeting = true
        }

        try? await Task.sleep(for: .milliseconds(140))

        withAnimation(.spring(duration: 0.5, bounce: 0.16)) {
            showPrompt = true
        }

        try? await Task.sleep(for: .milliseconds(180))

        withAnimation(.spring(duration: 0.4, bounce: 0.08)) {
            showDetails = true
        }
    }
}

private struct NotebookBetaInviteHero: View {
    let showGreeting: Bool
    let showPrompt: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HeroBackground()

            VStack(spacing: 20) {
                Spacer()

                HStack(spacing: 8) {
                    Text("What would you like to build?")
                        .font(.title.weight(.bold))
                        .foregroundStyle(Color.black)

                    Text("BETA")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.primaryButton)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Color.primaryButton.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.primaryButton.opacity(0.2), lineWidth: 1)
                        }
                }
                .opacity(showGreeting ? 1 : 0)
                .scaleEffect(showGreeting ? 1 : (reduceMotion ? 1 : 0.98))
                .offset(y: showGreeting ? 0 : (reduceMotion ? 0 : 16))

                NotebookBetaPromptCard(isVisible: showPrompt)

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .frame(height: 290)
    }
}

private struct HeroBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.97, blue: 0.95),
                    Color(red: 0.95, green: 0.92, blue: 0.88),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Color(red: 0.94, green: 0.69, blue: 0.54).opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 32)
                .offset(x: -170, y: -90)

            Circle()
                .fill(Color.primaryButton.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 24)
                .offset(x: 180, y: -110)
        }
    }
}

private struct NotebookBetaPromptCard: View {
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Text("Ask a data question...")
                .font(.body)
                .foregroundStyle(.secondary.opacity(0.6))

            Spacer()

            HStack(spacing: 8) {
                Image("convex")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)

                Text("Convex")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.7))

                ZStack {
                    Circle()
                        .fill(.primary.opacity(0.08))

                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.3))
                }
                .frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 440)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : (reduceMotion ? 1 : 0.96))
        .offset(y: isVisible ? 0 : (reduceMotion ? 0 : 22))
    }
}

private struct NotebookBetaInviteDetails: View {
    let isVisible: Bool
    let onDismiss: () -> Void
    let onTryNotebook: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 46) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your new data teammate")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Ask Notebook Agent anything about your data and let it do the heavy lifting. It can write the SQL, surface the insight, and turn raw tables into charts in minutes")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 18) {
                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button("Cancel", action: onDismiss)
                        .secondaryStyle()
                        .frame(width: 110)

                    Button("Try Notebook", action: onTryNotebook)
                        .primaryStyle()
                        .frame(width: 170)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : (reduceMotion ? 0 : 14))
    }
}
