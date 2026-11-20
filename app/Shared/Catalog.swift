import Foundation

/// The list of recordings the Mac shares. Same shape as the site's recordings.json,
/// plus a stable id per session.
struct Catalog: Codable, Equatable {
    var title: String
    var subjects: [Subject]
    var generated: Date
}

struct Subject: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var sessions: [Session]
}

struct Session: Codable, Equatable, Identifiable, Hashable {
    /// Google Drive file id (stable, used for downloads).
    var id: String
    var n: Int
    /// yyyy-MM-dd
    var date: String
    /// File name on the phone, e.g. "usool-2026-04-10.mp3"
    var file: String
    /// Seconds. 0 until known (filled in after download).
    var dur: Double
    var bytes: Int64
}

enum Fmt {
    static func length(_ sec: Double) -> String {
        guard sec > 0 else { return "" }
        var h = Int(sec) / 3600
        var m = Int(((sec.truncatingRemainder(dividingBy: 3600)) / 60).rounded())
        if m == 60 { h += 1; m = 0 }
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func time(_ sec: Double) -> String {
        let s = max(0, Int(sec.isFinite ? sec : 0))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }

    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    private static let isoIn: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let out: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d yyyy")
        return f
    }()

    /// "2026-04-10" -> "Fri, Apr 10, 2026"
    static func date(_ iso: String) -> String {
        guard let d = isoIn.date(from: iso) else { return iso }
        return out.string(from: d)
    }
}
