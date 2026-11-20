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
        .background(Theme.bg.ignoresSafeArea())
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
            if active > 0 {
                ProgressView(value: lib.activeProgress).tint(Theme.accent)
                Button("Stop downloads") { lib.stopAll() }.buttonStyle(PillButtonStyle(color: Theme.muted))
            } else if done < total {
                Button {
                    lib.downloadAll()
                } label: {
                    Label("Download all", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x04120B))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
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
