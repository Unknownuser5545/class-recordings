import SwiftUI

struct SubjectView: View {
    @EnvironmentObject var lib: Library
    @EnvironmentObject var player: Player
    let subjectID: String

    var body: some View {
        if let sub = lib.subject(subjectID) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Text(sub.name).font(.system(size: 32, weight: .bold)).kerning(-0.6)
                            .foregroundStyle(Theme.text).multilineTextAlignment(.center).padding(.top, 12)
                        Text("\(sub.sessions.count) recordings")
                            .font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 8)
                        HStack(spacing: 10) {
                            Button("Jump to latest \u{2193}") {
                                if let last = sub.sessions.last {
                                    withAnimation { proxy.scrollTo(last.id, anchor: .center) }
                                }
                            }
                            if !lib.autoDownload || sub.sessions.contains(where: { !lib.isDownloaded($0, subject: sub.id) }) {
                                Button("Download all") {
                                    sub.sessions.forEach { lib.download($0, subject: sub.id) }
                                }
                            }
                        }
                        .buttonStyle(.glass)
                        .tint(Theme.accent)
                        .padding(.top, 16)

                        if sub.sessions.isEmpty {
                            Text("No recordings yet. They're still uploading.\nPull down on the home screen to check again.")
                                .font(.system(size: 15)).foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center).padding(.top, 32)
                        }

                        LazyVStack(spacing: 10) {
                            ForEach(Array(sub.sessions.enumerated()), id: \.element.id) { i, s in
                                SessionRow(subject: sub, session: s, index: i).id(s.id)
                            }
                        }
                        .padding(.top, 24)
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 16).padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(GlassBackground())
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("Not found").foregroundStyle(Theme.muted)
        }
    }
}

struct SessionRow: View {
    @EnvironmentObject var lib: Library
    @EnvironmentObject var player: Player
    let subject: Subject
    let session: Session
    let index: Int

    var body: some View {
        let playing = player.isCurrent(session)
        let st = lib.state(session)
        HStack(spacing: 12) {
            Button { player.play(subject: subject.id, index: index) } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            if playing { EqBars(animating: player.isPlaying) }
                            Text("Session \(session.n)").font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                        Text(session.date.isEmpty ? session.file : Fmt.date(session.date))
                            .font(.system(size: 14)).foregroundStyle(Theme.muted)
                        let p = player.progress(session)
                        if p > 0.01 && !playing {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.track)
                                    Capsule().fill(Theme.accent.opacity(0.7)).frame(width: g.size.width * p)
                                }
                            }
                            .frame(width: 90, height: 3).padding(.top, 3)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(rightText)
                        .font(.system(size: 15).monospacedDigit())
                        .foregroundStyle(playing ? Theme.accent : Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            DownloadButton(state: st) {
                switch st {
                case .none, .failed: lib.download(session, subject: subject.id)
                case .queued, .downloading: lib.cancel(session)
                case .done: break
                }
            }
        }
        .card(highlighted: playing)
        .contextMenu {
            if lib.isDownloaded(session, subject: subject.id) {
                Button(role: .destructive) { lib.remove(session, subject: subject.id) } label: {
                    Label("Remove from phone", systemImage: "trash")
                }
            } else {
                Button { lib.download(session, subject: subject.id) } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }
    }

    private var rightText: String {
        let d = lib.duration(session)
        if d > 0 { return Fmt.length(d) }
        return session.bytes > 0 ? Fmt.bytes(session.bytes) : ""
    }
}

/// Download status on the right of each row: arrow, ring with progress, or green tick.
struct DownloadButton: View {
    let state: DownloadState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                switch state {
                case .none:
                    Image(systemName: "arrow.down.circle").foregroundStyle(Theme.accent)
                case .failed:
                    Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(Theme.danger)
                case .queued:
                    Circle().stroke(Theme.track, lineWidth: 2.5).frame(width: 22, height: 22)
                    Image(systemName: "stop.fill").font(.system(size: 8)).foregroundStyle(Theme.muted)
                case .downloading(let p):
                    Circle().stroke(Theme.track, lineWidth: 2.5).frame(width: 22, height: 22)
                    Circle().trim(from: 0, to: p).stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 22, height: 22)
                    Image(systemName: "stop.fill").font(.system(size: 8)).foregroundStyle(Theme.accent)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 20))
            .frame(width: 42, height: 42)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(state == .done)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch state {
        case .none: return "Download"
        case .failed: return "Download failed, try again"
        case .queued: return "Waiting to download, tap to cancel"
        case .downloading: return "Downloading, tap to cancel"
        case .done: return "On your phone"
        }
    }
}
