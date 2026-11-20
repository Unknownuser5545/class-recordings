import Foundation
import AVFoundation
import MediaPlayer

/// Plays recordings (from the phone if downloaded, otherwise streamed from Google Drive).
/// Remembers where you stopped in each recording.
@MainActor
final class Player: ObservableObject {
    static let shared = Player()

    @Published private(set) var subjectID: String?
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var status: String?
    @Published var speed: Float = UserDefaults.standard.object(forKey: "speed") as? Float ?? 1.0 {
        didSet {
            UserDefaults.standard.set(speed, forKey: "speed")
            if isPlaying { player.rate = speed }
            updateNowPlaying()
        }
    }

    static let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    let step: Double = 10

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObs: NSKeyValueObservation?
    private var lastSaved: Double = 0
    private var lib: Library { Library.shared }

    var current: Session? {
        guard let sid = subjectID, let sub = lib.subject(sid), sub.sessions.indices.contains(index) else { return nil }
        return sub.sessions[index]
    }
    var currentSubject: Subject? { subjectID.flatMap { lib.subject($0) } }

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(CMTimeGetSeconds(t)) }
        }
        setupRemote()
    }

    // MARK: Control

    func isCurrent(_ s: Session) -> Bool { current?.id == s.id }

    func play(subject: String, index i: Int) {
        guard let sub = lib.subject(subject), sub.sessions.indices.contains(i) else { return }
        let s = sub.sessions[i]
        if isCurrent(s) { toggle(); return }
        saveNow()
        if lib.isPreview {
            player.replaceCurrentItem(with: nil)
            subjectID = subject; index = i; duration = lib.duration(s); time = 0; isPlaying = false
            status = "Playback starts once the recordings are on Google Drive."
            return
        }
        let url: URL
        if lib.isDownloaded(s, subject: subject) {
            url = lib.localURL(s, subject: subject)
            status = nil
        } else {
            url = lib.source.downloadURL(fileID: s.id)
            status = "Streaming from Google Drive…"
        }
        subjectID = subject
        index = i
        duration = lib.duration(s)
        let item = AVPlayerItem(url: url)
        statusObs = item.observe(\.status) { [weak self] it, _ in
            let st = it.status
            let d = CMTimeGetSeconds(it.duration)
            Task { @MainActor in
                guard let self else { return }
                if st == .failed { self.status = "Couldn't play this recording."; self.isPlaying = false }
                if st == .readyToPlay {
                    if d.isFinite, d > 0 { self.duration = d }
                    if self.status == "Loading…" { self.status = nil }
                }
            }
        }
        player.replaceCurrentItem(with: item)
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished() }
        }
        let resume = UserDefaults.standard.double(forKey: "pos-\(s.id)")
        time = resume
        if resume > 5 { player.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.playImmediately(atRate: speed)
        isPlaying = true
        updateNowPlaying()
    }

    func toggle() {
        guard current != nil else { return }
        if isPlaying { pause() } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.playImmediately(atRate: speed)
            isPlaying = true
            updateNowPlaying()
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        saveNow()
        updateNowPlaying()
    }

    func skip(_ delta: Double) { seek(to: time + delta) }

    func seek(to t: Double) {
        let maxT = duration > 0 ? duration - 0.5 : .greatestFiniteMagnitude
        let target = min(max(0, t), maxT)
        time = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        saveNow()
        updateNowPlaying()
    }

    func hasNeighbour(_ dir: Int) -> Bool {
        guard let sub = currentSubject else { return false }
        return sub.sessions.indices.contains(index + dir)
    }

    func go(_ dir: Int) {
        guard let sid = subjectID, hasNeighbour(dir) else { return }
        play(subject: sid, index: index + dir)
    }

    // MARK: Internals

    private func tick(_ t: Double) {
        guard t.isFinite else { return }
        time = t
        if let d = player.currentItem?.duration, CMTimeGetSeconds(d).isFinite, CMTimeGetSeconds(d) > 0 {
            duration = CMTimeGetSeconds(d)
        }
        if abs(t - lastSaved) > 5 { saveNow() }
    }

    private func saveNow() {
        guard let s = current else { return }
        lastSaved = time
        UserDefaults.standard.set(time, forKey: "pos-\(s.id)")
    }

    private func finished() {
        if let s = current { UserDefaults.standard.set(0.0, forKey: "pos-\(s.id)") }
        isPlaying = false
        time = 0
        updateNowPlaying()
    }

    /// 0...1 how far you got in a recording (for the list).
    func progress(_ s: Session) -> Double {
        let d = lib.duration(s)
        guard d > 0 else { return 0 }
        return min(1, UserDefaults.standard.double(forKey: "pos-\(s.id)") / d)
    }

    // MARK: Lock screen

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPlaying == false { self?.toggle() } }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }; return .success }
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(-10) }; return .success }
        c.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(10) }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.go(1) }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.go(-1) }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let s = current, let sub = currentSubject else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Session \(s.n) · \(Fmt.date(s.date))",
            MPMediaItemPropertyArtist: sub.name,
            MPMediaItemPropertyAlbumTitle: "Zainab Center Recordings",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0.0,
        ]
    }
}
