import SwiftUI

/// Colours from the class-recordings site.
enum Theme {
    static let bg = Color(hex: 0x0C0D10)
    static let panel = Color(hex: 0x15171C)
    static let text = Color(hex: 0xF2F3F5)
    static let muted = Color(hex: 0x9AA0AA)
    static let accent = Color(hex: 0x00D179)
    static let border = Color(hex: 0x262A31)
    static let track = Color(hex: 0x2A2E36)
    static let danger = Color(hex: 0xFF6B6B)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The rounded dark card used for every row.
struct CardStyle: ViewModifier {
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(highlighted ? Theme.accent.opacity(0.08) : Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(highlighted ? Theme.accent : Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View { modifier(CardStyle(highlighted: highlighted)) }
}

/// Pill button with a thin border (like "Jump to latest").
struct PillButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 20).frame(minHeight: 44)
            .overlay(Capsule().stroke(configuration.isPressed ? Theme.accent : Theme.border, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Little animated equaliser shown on the recording that's playing.
struct EqBars: View {
    var animating: Bool
    @State private var phase = false
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1).fill(Theme.accent)
                    .frame(width: 3, height: animating ? (phase ? [12, 5, 9][i] : [4, 11, 6][i]) : 4)
            }
        }
        .frame(height: 12, alignment: .bottom)
        .animation(animating ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: phase)
        .onAppear { phase = true }
    }
}
