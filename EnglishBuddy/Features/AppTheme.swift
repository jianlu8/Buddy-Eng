import SwiftUI

enum AppBackgroundStyle {
    case home
    case history
    case settings
    case feedback
    case onboarding
    case transcript
}

enum CallChromeStyle {
    case cinematic
}

enum AppTheme {
    static let ink = Color(red: 0.15, green: 0.14, blue: 0.18)
    static let mutedInk = Color(red: 0.40, green: 0.37, blue: 0.38)
    static let warmAccent = Color(red: 0.92, green: 0.43, blue: 0.27)
    static let warmAccentSoft = Color(red: 0.99, green: 0.83, blue: 0.68)
    static let coolAccent = Color(red: 0.27, green: 0.51, blue: 0.72)
    static let canvas = Color(red: 0.97, green: 0.94, blue: 0.90)
    static let canvasLift = Color(red: 1.0, green: 0.98, blue: 0.95)
    static let surface = Color.white.opacity(0.88)
    static let secondarySurface = Color.white.opacity(0.74)
    static let hairline = Color.black.opacity(0.06)
    static let strongHairline = Color.black.opacity(0.12)
    static let heroShadow = Color(red: 0.35, green: 0.25, blue: 0.20).opacity(0.14)

    static func backgroundGradient(for style: AppBackgroundStyle) -> LinearGradient {
        switch style {
        case .home:
            return LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.95, blue: 0.91),
                    Color(red: 1.0, green: 0.98, blue: 0.95),
                    Color(red: 0.97, green: 0.94, blue: 0.89)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .history:
            return LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.94, blue: 0.90),
                    Color(red: 0.99, green: 0.97, blue: 0.94),
                    Color(red: 0.95, green: 0.92, blue: 0.88)
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        case .settings:
            return LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.93, blue: 0.89),
                    Color(red: 0.99, green: 0.97, blue: 0.95),
                    Color(red: 0.97, green: 0.95, blue: 0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottom
            )
        case .feedback:
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.92, blue: 0.88),
                    Color(red: 0.99, green: 0.97, blue: 0.95),
                    Color(red: 0.96, green: 0.93, blue: 0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .onboarding:
            return LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.95, blue: 0.92),
                    Color(red: 0.99, green: 0.97, blue: 0.95),
                    Color(red: 0.96, green: 0.92, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .transcript:
            return LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.95, blue: 0.92),
                    Color(red: 0.99, green: 0.98, blue: 0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct AppSectionHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?

    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow, eyebrow.isEmpty == false {
                Text(eyebrow.uppercased())
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.warmAccent)
            }

            Text(title)
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(AppTheme.ink)

            if let subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AppCapsuleBadge: View {
    let text: String
    var tint: Color = AppTheme.warmAccent
    var foreground: Color = .white
    var backgroundOpacity: Double = 0.14

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(tint.opacity(backgroundOpacity))
                    .overlay(
                        Capsule()
                            .stroke(foreground.opacity(0.16), lineWidth: 1)
                    )
            )
    }
}

struct AppIconChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct SurfaceCardStyle: ViewModifier {
    var padding: CGFloat = 18
    var fill: Color = AppTheme.surface
    var shadowOpacity: Double = 0.08

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AppTheme.hairline, lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 28, y: 14)
    }
}

struct HeroPanelStyle: ViewModifier {
    var cornerRadius: CGFloat = 34

    func body(content: Content) -> some View {
        content
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.26, blue: 0.40),
                                Color(red: 0.47, green: 0.28, blue: 0.24),
                                Color(red: 0.84, green: 0.43, blue: 0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .shadow(color: AppTheme.heroShadow, radius: 32, y: 18)
    }
}

struct GlassPanelStyle: ViewModifier {
    var padding: CGFloat = 16
    var tint: Color = Color.black.opacity(0.26)
    var strokeOpacity: Double = 0.12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(tint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.16), radius: 20, y: 14)
    }
}

struct FloatingDockStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.40))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.22), radius: 24, y: 18)
    }
}

extension View {
    func surfaceCard(padding: CGFloat = 18, fill: Color = AppTheme.surface, shadowOpacity: Double = 0.08) -> some View {
        modifier(SurfaceCardStyle(padding: padding, fill: fill, shadowOpacity: shadowOpacity))
    }

    func heroPanel(cornerRadius: CGFloat = 34) -> some View {
        modifier(HeroPanelStyle(cornerRadius: cornerRadius))
    }

    func glassPanel(padding: CGFloat = 16, tint: Color = Color.black.opacity(0.26), strokeOpacity: Double = 0.12) -> some View {
        modifier(GlassPanelStyle(padding: padding, tint: tint, strokeOpacity: strokeOpacity))
    }

    func floatingDock() -> some View {
        modifier(FloatingDockStyle())
    }
}
