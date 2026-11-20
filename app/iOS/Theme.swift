import SwiftUI

/// Colours from the class-recordings site.
enum Links {
    static let website = URL(string: "https://unknownuser5545.github.io/class-recordings/")!
    static let repo = URL(string: "https://github.com/Unknownuser5545/class-recordings")!
}

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

/// Liquid Glass card used for every row. Tinted green when it's the one playing.
struct CardStyle: ViewModifier {
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .glassEffect(highlighted ? .regular.tint(Theme.accent.opacity(0.22)).interactive() : .regular.interactive(),
                         in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View { modifier(CardStyle(highlighted: highlighted)) }
}

/// Dark background with soft green glows, so the glass has something to refract.
struct GlassBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.6, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                Color(hex: 0x0A2A1D), Theme.bg, Color(hex: 0x06261F),
                Theme.bg, Color(hex: 0x0B1F18), Theme.bg,
                Color(hex: 0x061A14), Theme.bg, Color(hex: 0x0D3324),
            ])
            .opacity(0.9)
        }
        .ignoresSafeArea()
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
