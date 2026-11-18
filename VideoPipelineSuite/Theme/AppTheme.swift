import SwiftUI

enum AppTheme {
    static let bgDark = Color(hex: 0x09090B)
    static let surfaceCard = Color(hex: 0x18181B)
    static let surfaceCardElevated = Color(hex: 0x222226)
    static let surfaceCardBorder = Color(hex: 0x2E2E33)

    static let primary = Color(hex: 0x6366F1)
    static let primaryVariant = Color(hex: 0x4F46E5)
    static let primaryLight = Color(hex: 0x818CF8)

    static let emerald = Color(hex: 0x10B981)
    static let emeraldDark = Color(hex: 0x059669)

    static let danger = Color(hex: 0xEF4444)
    static let amber = Color(hex: 0xF59E0B)
    static let cyan = Color(hex: 0x06B6D4)

    static let textPrimary = Color(hex: 0xF8FAFC)
    static let textSecondary = Color(hex: 0x94A3B8)
    static let textMuted = Color(hex: 0x64748B)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

struct PipelineCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppTheme.surfaceCardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func pipelineCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        modifier(PipelineCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = AppTheme.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? color.opacity(0.8) : color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
