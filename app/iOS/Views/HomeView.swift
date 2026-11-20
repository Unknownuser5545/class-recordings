import SwiftUI

struct HomeView: View {
    @EnvironmentObject var lib: Library
    @State private var showSettings = false
    @State private var pull: CGFloat = 0          // how far the list is pulled down
    @State private var armed = false              // pulled far enough to refresh
    @State private var dragging = false
    private let threshold: CGFloat = 80

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PullArrow(progress: min(pull / threshold, 1), armed: armed, refreshing: lib.refreshing)
                    .frame(height: 0)
                    .offset(y: lib.refreshing ? 4 : -pull / 2 - 4)

                Text("Zainab Center\nRecordings")
                    .font(.system(size: 34, weight: .bold)).kerning(-0.6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.text)
                    .padding(.top, 24)
                Text("Audio recordings")
                    .font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 8)

                DownloadPanel().padding(.top, 24)

                VStack(spacing: 10) {
                    ForEach(lib.catalog?.subjects ?? []) { sub in
                        NavigationLink(value: sub.id) { SubjectCard(subject: sub) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.top, 16)

                Link(destination: Links.website) { Label("Website", systemImage: "globe") }
                .buttonStyle(.glass)
                .tint(Theme.accent)
                .padding(.top, 24)

                if lib.catalog == nil {
                    Text(lib.isSetUp ? "Loading the recordings…" : "No recordings yet.")
                        .foregroundStyle(Theme.muted).padding(.top, 40)
                }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(GlassBackground())
        .onScrollGeometryChange(for: CGFloat.self) { g in
            -(g.contentOffset.y + g.contentInsets.top)
        } action: { _, new in
            pull = max(0, new)
            if dragging {
                let nowArmed = pull >= threshold
                if nowArmed != armed {
                    armed = nowArmed
                    if nowArmed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                }
            }
        }
        .onScrollPhaseChange { old, new in
            dragging = (new == .interacting)
            if old == .interacting && new != .interacting {
                if armed && !lib.refreshing { Task { await lib.refresh() } }
                armed = false
            }
        }
        .navigationDestination(for: String.self) { SubjectView(subjectID: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .foregroundStyle(Theme.muted)
                    .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

private struct SubjectCard: View {
    @EnvironmentObject var lib: Library
    let subject: Subject
    var body: some View {
        let onPhone = subject.sessions.filter { lib.isDownloaded($0, subject: subject.id) }.count
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(subject.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Text(subject.sessions.isEmpty ? "Recordings coming soon"
                     : "\(subject.sessions.count) recordings · \(onPhone) on phone")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
        }
        .card()
    }
}

/// "Download all" box at the top of the home screen.
struct DownloadPanel: View {
    @EnvironmentObject var lib: Library
    @Namespace private var glass

    var body: some View {
        let done = lib.downloadedCount, total = lib.totalCount, active = lib.activeCount
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(done == total && total > 0 ? "All recordings are on your phone" : "\(done) of \(total) on your phone")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(subtitle(active: active))
                        .font(.system(size: 13)).foregroundStyle(lib.lastError == nil ? Theme.muted : Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if lib.refreshing { ProgressView().tint(Theme.muted) }
            }
            GlassEffectContainer(spacing: 12) {
                if active > 0 {
                    VStack(spacing: 12) {
                        ProgressView(value: lib.activeProgress).tint(Theme.accent)
                        Button { withAnimation(.bouncy) { lib.stopAll() } } label: {
                            Label("Stop downloads", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("action", in: glass)
                    }
                } else if done < total {
                    Button { withAnimation(.bouncy) { lib.downloadAll() } } label: {
                        Label("Download all", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .glassEffectID("action", in: glass)
                }
            }
        }
        .card()
    }

    private func subtitle(active: Int) -> String {
        if let e = lib.lastError { return e }
        if lib.isPreview { return "Preview: downloads start once the recordings are on Google Drive." }
        if active > 0 { return "Downloading \(active) recording\(active == 1 ? "" : "s")… keeps going if you close the app." }
        return "\(Fmt.bytes(lib.bytesOnPhone)) used of \(Fmt.bytes(lib.totalBytes))"
    }
}

/// Small arrow shown when you pull the list down.
/// Points down while pulling, flips up when you've pulled far enough, then spins while refreshing.
struct PullArrow: View {
    var progress: CGFloat
    var armed: Bool
    var refreshing: Bool
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: refreshing ? 0.75 : progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(refreshing && spin ? 270 : -90))
                .animation(refreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: spin)
            Image(systemName: refreshing ? "arrow.clockwise" : "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(armed && !refreshing ? 180 : 0))
                .contentTransition(.symbolEffect(.replace))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: armed)
        }
        .frame(width: 34, height: 34)
        .glassEffect(.regular, in: Circle())
        .scaleEffect(refreshing ? 1 : max(0.4, progress))
        .opacity(refreshing ? 1 : Double(progress))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: refreshing)
        .onChange(of: refreshing) { _, r in spin = r }
        .accessibilityLabel(refreshing ? "Refreshing" : "Pull down to refresh")
    }
}
