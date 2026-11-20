import SwiftUI

struct HomeView: View {
    @EnvironmentObject var lib: Library
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
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
        .refreshable { await lib.refresh() }
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
                Text("\(subject.sessions.count) recordings · \(onPhone) on phone")
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
