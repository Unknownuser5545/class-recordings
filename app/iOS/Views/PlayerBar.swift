import SwiftUI

/// Player pinned to the bottom, same controls as the site:
/// previous, back 10, play/pause, forward 10, next. Plus a speed button.
struct PlayerBar: View {
    @EnvironmentObject var player: Player
    @State private var dragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(player.status ?? (player.current.map { Fmt.date($0.date) } ?? ""))
                        .font(.system(size: 13)).lineLimit(2)
                        .foregroundStyle(player.status?.hasPrefix("Couldn't") == true ? Theme.danger : Theme.muted)
                }
                Spacer()
                Menu {
                    ForEach(Player.speeds, id: \.self) { s in
                        Button { player.speed = s } label: {
                            if s == player.speed { Label(speedLabel(s), systemImage: "checkmark") } else { Text(speedLabel(s)) }
                        }
                    }
                } label: {
                    Text(speedLabel(player.speed))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(player.speed == 1 ? Theme.text : Theme.accent)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .accessibilityLabel("Playback speed")
            }

            HStack(spacing: 10) {
                Text(Fmt.time(dragging ? dragValue : player.time))
                    .frame(minWidth: 52, alignment: .leading)
                Slider(value: Binding(
                    get: { dragging ? dragValue : min(player.time, max(player.duration, 1)) },
                    set: { dragValue = $0 }),
                       in: 0...max(player.duration, 1)) { editing in
                    if editing { dragValue = player.time; dragging = true }
                    else { player.seek(to: dragValue); dragging = false }
                }
                .tint(Theme.accent)
                Text(Fmt.time(player.duration)).frame(minWidth: 52, alignment: .trailing)
            }
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(Theme.muted)
            .padding(.top, 4)

            HStack {
                ctl("backward.end.fill", "Previous session", size: 24) { player.go(-1) }
                    .disabled(!player.hasNeighbour(-1))
                Spacer()
                ctl("gobackward.10", "Back 10 seconds", size: 28) { player.skip(-player.step) }
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Theme.accent)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer()
                ctl("goforward.10", "Forward 10 seconds", size: 28) { player.skip(player.step) }
                Spacer()
                ctl("forward.end.fill", "Next session", size: 24) { player.go(1) }
                    .disabled(!player.hasNeighbour(1))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 10).padding(.bottom, 4)
    }

    private var title: String {
        guard let s = player.current, let sub = player.currentSubject else { return "" }
        return "\(sub.name) · Session \(s.n)"
    }

    private func speedLabel(_ s: Float) -> String {
        s == Float(Int(s)) ? "\(Int(s))x" : String(format: "%gx", s)
    }

    private func ctl(_ icon: String, _ label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size)).frame(width: 52, height: 52).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .accessibilityLabel(label)
    }
}
