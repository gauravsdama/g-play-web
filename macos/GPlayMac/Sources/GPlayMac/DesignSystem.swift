import SwiftUI

extension Color {
    static let gBackground = Color(red: 0.055, green: 0.06, blue: 0.07)
    static let gSurface = Color(red: 0.12, green: 0.125, blue: 0.135)
    static let gSurfaceRaised = Color(red: 0.16, green: 0.165, blue: 0.18)
    static let gAccent = Color(red: 0.03, green: 0.48, blue: 0.95)
    static let gMint = Color(red: 0.1, green: 0.72, blue: 0.52)
    static let gWarning = Color(red: 0.95, green: 0.62, blue: 0.18)
}

struct AppCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            )
    }
}

struct ArtworkView: View {
    let track: Track?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(8, size * 0.12), style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.gAccent.opacity(0.8), .gMint.opacity(0.7), .purple.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let thumbnail = track?.thumbnail, let url = URL(string: thumbnail) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.28, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.12), style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
        .accessibilityHidden(true)
    }
}

struct StatusBanner: View {
    let message: String?

    var body: some View {
        if let message, !message.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.gAccent)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(Color.gAccent)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .accessibilityElement(children: .combine)
    }
}
