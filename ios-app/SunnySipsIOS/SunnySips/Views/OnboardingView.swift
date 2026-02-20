import SwiftUI

private struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let accentLabel: String
}

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var currentPage = 0
    @State private var animateIcon = false

    private let pages: [OnboardingPage] = [
        .init(
            id: 0,
            title: "Find Sunny Cafes Fast",
            subtitle: "Green means best sun right now. Yellow means partial sun. Red means shaded.",
            icon: "sun.max.fill",
            tint: ThemeColor.sunnyGreen,
            accentLabel: "Live map scoring"
        ),
        .init(
            id: 1,
            title: "Forecast Later Today",
            subtitle: "Tap Forecast in the header, jump forward with +30m/+1h chips, and compare spots instantly.",
            icon: "clock.badge.checkmark",
            tint: ThemeColor.focusBlue,
            accentLabel: "Future prediction"
        ),
        .init(
            id: 2,
            title: "Pick And Navigate",
            subtitle: "Open any cafe card for details, then hit Navigate to launch Apple Maps, Google Maps, or Street View.",
            icon: "location.fill",
            tint: ThemeColor.sun,
            accentLabel: "One-tap directions"
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ThemeColor.bg, ThemeColor.surfaceSoft],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    Button("Skip") {
                        onFinish()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ThemeColor.muted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                TabView(selection: $currentPage) {
                    ForEach(pages) { page in
                        pageCard(page)
                            .tag(page.id)
                            .padding(.horizontal, 20)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(pages) { page in
                        Capsule()
                            .fill(page.id == currentPage ? ThemeColor.focusBlue : ThemeColor.line.opacity(0.8))
                            .frame(width: page.id == currentPage ? 24 : 8, height: 8)
                            .animation(.spring(duration: 0.22), value: currentPage)
                    }
                }

                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation(.spring(duration: 0.28)) {
                            currentPage += 1
                        }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Next" : "Start Exploring")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(ThemeColor.focusBlue, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .onAppear {
            animateIcon = true
        }
    }

    private func pageCard(_ page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.15))
                    .frame(width: 124, height: 124)

                Image(systemName: page.icon)
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(page.tint)
                    .scaleEffect(animateIcon ? 1.0 : 0.9)
                    .animation(
                        .easeInOut(duration: 1.05).repeatForever(autoreverses: true),
                        value: animateIcon
                    )
            }
            .frame(maxWidth: .infinity)

            Text(page.accentLabel.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(page.tint)
                .tracking(0.8)

            Text(page.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(ThemeColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(page.subtitle)
                .font(.body)
                .foregroundStyle(ThemeColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            if page.id == 0 {
                legendRow
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ThemeColor.line.opacity(0.45), lineWidth: 1)
        )
    }

    private var legendRow: some View {
        HStack(spacing: 8) {
            legendPill("Sunny", color: ThemeColor.sunnyGreen)
            legendPill("Partial", color: ThemeColor.partialAmber)
            legendPill("Shaded", color: ThemeColor.shadedRed)
        }
    }

    private func legendPill(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "cup.and.saucer.fill")
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color, in: Capsule())
    }
}
