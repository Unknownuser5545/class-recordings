import Foundation
import AVFoundation
import SwiftUI

enum DownloadState: Equatable {
    case none
    case queued
    case downloading(Double)   // 0...1
    case done
    case failed(String)
}

/// Holds the recordings list, settings, and which recordings are on the phone.
@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    /// Baked-in Drive folder (set once Ahmed shares it). Can be changed in Settings.
    static let defaultFolderID = "13ZxYSV6ueRwseAChVEKo5i8w_NBbY4zg"
    static let defaultAPIKey = ""

    @Published private(set) var catalog: Catalog?
    @Published private(set) var states: [String: DownloadState] = [:]
    @Published private(set) var refreshing = false
    @Published var lastError: String?
    @Published private(set) var durations: [String: Double] = [:]

    @Published var folderID: String = UserDefaults.standard.string(forKey: "folderID") ?? Library.defaultFolderID {
        didSet { UserDefaults.standard.set(folderID, forKey: "folderID") }
    }
    @Published var apiKey: String = UserDefaults.standard.string(forKey: "apiKey") ?? Library.defaultAPIKey {
        didSet { UserDefaults.standard.set(apiKey, forKey: "apiKey") }
    }
    /// "Download everything" (default) vs pick recordings one by one.
    @Published var autoDownload: Bool = UserDefaults.standard.object(forKey: "autoDownload") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoDownload, forKey: "autoDownload") }
    }

    var source: DriveSource { DriveSource(folderID: folderID, apiKey: apiKey) }
    var isSetUp: Bool { !folderID.isEmpty }

    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var catalogURL: URL { docs.appendingPathComponent("catalog.json") }
    private var durationsURL: URL { docs.appendingPathComponent("durations.json") }
    var recordingsDir: URL { docs.appendingPathComponent("Recordings", isDirectory: true) }

    private init() {
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        // Keep downloads out of iCloud backups (they can be downloaded again).
        var dir = recordingsDir
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? dir.setResourceValues(rv)

        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: catalogURL), let c = try? dec.decode(Catalog.self, from: d) { catalog = c }
        if catalog == nil { catalog = Self.previewCatalog() }
        if let d = try? Data(contentsOf: durationsURL), let m = try? JSONDecoder().decode([String: Double].self, from: d) { durations = m }
        rebuildStates()
    }

    /// Until Google Drive is set up, show the session list from the class-recordings site
    /// so the layout can be seen. These can't be downloaded.
    var isPreview: Bool { !isSetUp }

    private static func previewCatalog() -> Catalog? {
        struct Site: Decodable {
            struct Sub: Decodable { var id: String; var name: String; var sessions: [S] }
            struct S: Decodable { var n: Int; var date: String; var file: String; var dur: Double; var bytes: Int64 }
            var subjects: [Sub]
        }
        guard let u = Bundle.main.url(forResource: "preview", withExtension: "json"),
              let d = try? Data(contentsOf: u), let site = try? JSONDecoder().decode(Site.self, from: d) else { return nil }
        return Catalog(title: "Zainab Center Recordings", subjects: site.subjects.map { sub in
            Subject(id: sub.id, name: sub.name, sessions: sub.sessions.map {
                Session(id: "preview-" + $0.file, n: $0.n, date: $0.date, file: $0.file, dur: $0.dur, bytes: $0.bytes)
            })
        }, generated: Date())
    }

    // MARK: Lookup

    func subject(_ id: String) -> Subject? { catalog?.subjects.first { $0.id == id } }

    func session(id: String) -> (Subject, Int)? {
        for s in catalog?.subjects ?? [] {
            if let i = s.sessions.firstIndex(where: { $0.id == id }) { return (s, i) }
        }
        return nil
    }

    func localURL(_ s: Session, subject: String) -> URL {
        recordingsDir.appendingPathComponent(subject, isDirectory: true).appendingPathComponent(s.file)
    }

    func isDownloaded(_ s: Session, subject: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(s, subject: subject).path)
    }

    func state(_ s: Session) -> DownloadState { states[s.id] ?? .none }

    func duration(_ s: Session) -> Double { s.dur > 0 ? s.dur : (durations[s.id] ?? 0) }

    var allSessions: [(Subject, Session)] {
        (catalog?.subjects ?? []).flatMap { sub in sub.sessions.map { (sub, $0) } }
    }

    var downloadedCount: Int { allSessions.filter { isDownloaded($0.1, subject: $0.0.id) }.count }
    var totalCount: Int { allSessions.count }
    var totalBytes: Int64 { allSessions.reduce(0) { $0 + $1.1.bytes } }

    var bytesOnPhone: Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: recordingsDir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    var activeCount: Int {
        states.values.filter { if case .queued = $0 { return true }; if case .downloading = $0 { return true }; return false }.count
    }

    /// Overall progress of the downloads currently running or waiting (0...1).
    var activeProgress: Double {
        var sum = 0.0, n = 0.0
        for v in states.values {
            switch v {
            case .queued: n += 1
            case .downloading(let p): sum += p; n += 1
            default: break
            }
        }
        return n > 0 ? sum / n : 0
    }

    // MARK: Refresh

    func refresh() async {
        guard isSetUp, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let fresh = try await source.loadCatalog()
            catalog = fresh
            lastError = nil
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            try? enc.encode(fresh).write(to: catalogURL, options: .atomic)
            rebuildStates()
            await Downloader.shared.syncStates()
            if autoDownload { downloadAll() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Downloads

    func downloadAll() {
        for (sub, s) in allSessions where !isDownloaded(s, subject: sub.id) { download(s, subject: sub.id) }
    }

    func download(_ s: Session, subject: String) {
        guard !isPreview else { lastError = "Downloads start once the recordings are on Google Drive."; return }
        switch state(s) {
        case .queued, .downloading, .done: return
        default: break
        }
        states[s.id] = .queued
        Downloader.shared.start(sessionID: s.id, url: source.downloadURL(fileID: s.id),
                                destination: localURL(s, subject: subject))
    }

    func stopAll() {
        Downloader.shared.cancelAll()
        for (k, v) in states {
            switch v { case .queued, .downloading: states[k] = .none; default: break }
        }
    }

    func cancel(_ s: Session) {
        Downloader.shared.cancel(sessionID: s.id)
        states[s.id] = .none
    }

    func remove(_ s: Session, subject: String) {
        try? FileManager.default.removeItem(at: localURL(s, subject: subject))
        states[s.id] = .none
        objectWillChange.send()
    }

    func removeAll() {
        stopAll()
        try? FileManager.default.removeItem(at: recordingsDir)
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        rebuildStates()
    }

    // Called by Downloader (on main actor)
    func downloadProgress(_ id: String, _ p: Double) { states[id] = .downloading(p) }
    func downloadQueued(_ id: String) { if states[id] == nil || states[id] == DownloadState.none { states[id] = .queued } }

    func downloadFinished(_ id: String, error: String?) {
        if let error {
            states[id] = .failed(error)
            return
        }
        states[id] = .done
        if let (sub, i) = session(id: id) {
            let s = sub.sessions[i]
            let url = localURL(s, subject: sub.id)
            Task { await self.measure(id: id, url: url) }
        }
    }

    private func measure(id: String, url: URL) async {
        guard let d = try? await AVURLAsset(url: url).load(.duration) else { return }
        let sec = CMTimeGetSeconds(d)
        guard sec.isFinite, sec > 0 else { return }
        durations[id] = sec
        try? JSONEncoder().encode(durations).write(to: durationsURL, options: .atomic)
    }

    private func rebuildStates() {
        var m: [String: DownloadState] = [:]
        for (sub, s) in allSessions {
            if isDownloaded(s, subject: sub.id) { m[s.id] = .done }
            else if let old = states[s.id] {
                switch old { case .queued, .downloading: m[s.id] = old; default: break }
            }
        }
        states = m
        // Measure any downloaded file whose length we don't know yet.
        for (sub, s) in allSessions where duration(s) == 0 && isDownloaded(s, subject: sub.id) {
            let url = localURL(s, subject: sub.id), id = s.id
            Task { await self.measure(id: id, url: url) }
        }
    }
}
