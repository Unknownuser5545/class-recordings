import Foundation

/// Reads the recordings list from a shared Google Drive folder.
///
/// Expected layout (what Ahmed uploads):
///   Root folder (shared "Anyone with the link")
///     usool/          Usool 04-10-2026.mp3 ...
///     Tafsir/         Khasa 1 Tafseer 04-07-2026.mp3 ...
///     Hidayatn Nahv/  Hidayatun Nahv 04-06-2026.mp3 ...
///
/// With an API key it uses the official Drive API. Without one it reads Drive's
/// public "embedded folder view" page, which needs no setup.
struct DriveSource {
    var folderID: String
    var apiKey: String

    struct Item { var id: String; var name: String; var isFolder: Bool; var size: Int64 }

    enum DriveError: LocalizedError {
        case notSetUp, http(Int), unreadable
        var errorDescription: String? {
            switch self {
            case .notSetUp: return "The Google Drive folder isn't set up yet."
            case .http(let c): return "Google Drive answered with error \(c). Check the folder is shared with \"Anyone with the link\"."
            case .unreadable: return "Couldn't read the Google Drive folder."
            }
        }
    }

    // MARK: Download URL for one file

    func downloadURL(fileID: String) -> URL {
        if !apiKey.isEmpty {
            var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
            c.queryItems = [.init(name: "alt", value: "media"), .init(name: "key", value: apiKey)]
            return c.url!
        }
        var c = URLComponents(string: "https://drive.usercontent.google.com/download")!
        c.queryItems = [.init(name: "id", value: fileID), .init(name: "export", value: "download"),
                        .init(name: "confirm", value: "t")]
        return c.url!
    }

    // MARK: Build the catalog

    func loadCatalog() async throws -> Catalog {
        guard !folderID.isEmpty else { throw DriveError.notSetUp }
        let top = try await list(folderID)
        var subjects: [Subject] = []
        for folder in top where folder.isFolder {
            let files = try await list(folder.id).filter { !$0.isFolder && Self.isAudio($0.name) }
            guard !files.isEmpty else { continue }
            let (sid, sname) = Self.subjectInfo(folder.name)
            var dated: [(date: String, item: Item)] = files.map { (Self.date(from: $0.name) ?? "", $0) }
            dated.sort { ($0.date, $0.item.name) < ($1.date, $1.item.name) }
            var seen: [String: Int] = [:]
            let sessions: [Session] = dated.enumerated().map { idx, pair in
                let ext = Self.ext(pair.item.name)
                var base = "\(sid)-\(pair.date.isEmpty ? "session-\(idx + 1)" : pair.date)"
                seen[base, default: 0] += 1
                if seen[base]! > 1 { base += "-\(seen[base]!)" }
                return Session(id: pair.item.id, n: idx + 1, date: pair.date,
                               file: "\(base).\(ext)", dur: 0, bytes: pair.item.size)
            }
            subjects.append(Subject(id: sid, name: sname, sessions: sessions))
        }
        subjects.sort { Self.order($0.id) < Self.order($1.id) || (Self.order($0.id) == Self.order($1.id) && $0.name < $1.name) }
        return Catalog(title: "Zainab Center Recordings", subjects: subjects, generated: Date())
    }

    private func list(_ folder: String) async throws -> [Item] {
        apiKey.isEmpty ? try await listEmbedded(folder) : try await listAPI(folder)
    }

    private func listAPI(_ folder: String) async throws -> [Item] {
        var items: [Item] = []
        var pageToken: String?
        repeat {
            var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            var q: [URLQueryItem] = [
                .init(name: "q", value: "'\(folder)' in parents and trashed = false"),
                .init(name: "fields", value: "nextPageToken,files(id,name,mimeType,size)"),
                .init(name: "pageSize", value: "1000"),
                .init(name: "key", value: apiKey),
            ]
            if let t = pageToken { q.append(.init(name: "pageToken", value: t)) }
            c.queryItems = q
            let (data, resp) = try await URLSession.shared.data(from: c.url!)
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw DriveError.http(h.statusCode) }
            struct Page: Decodable {
                struct F: Decodable { var id: String; var name: String; var mimeType: String; var size: String? }
                var nextPageToken: String?; var files: [F]
            }
            let page = try JSONDecoder().decode(Page.self, from: data)
            items += page.files.map {
                Item(id: $0.id, name: $0.name, isFolder: $0.mimeType == "application/vnd.google-apps.folder",
                     size: Int64($0.size ?? "") ?? 0)
            }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return items
    }

    /// Parses https://drive.google.com/embeddedfolderview?id=FOLDER (public folders only).
    private func listEmbedded(_ folder: String) async throws -> [Item] {
        let url = URL(string: "https://drive.google.com/embeddedfolderview?id=\(folder)#list")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw DriveError.http(h.statusCode) }
        guard let html = String(data: data, encoding: .utf8) else { throw DriveError.unreadable }
        return Self.parseEmbedded(html)
    }

    static func parseEmbedded(_ html: String) -> [Item] {
        var items: [Item] = []
        // Each entry: <div class="flip-entry" id="entry-ID" ...> <a href="...folders/ID or /file/d/ID/...">
        //   ... <div class="flip-entry-title">NAME</div>
        let parts = html.components(separatedBy: "class=\"flip-entry\"").dropFirst()
        for part in parts {
            guard let idR = part.range(of: "id=\"entry-") else { continue }
            let rest = part[idR.upperBound...]
            guard let q = rest.firstIndex(of: "\"") else { continue }
            let id = String(rest[..<q])
            let isFolder = part.contains("/drive/folders/") || part.contains("folders/\(id)")
            var name = ""
            if let t = part.range(of: "flip-entry-title\">"),
               let e = part[t.upperBound...].range(of: "</div>") {
                name = decodeEntities(String(part[t.upperBound..<e.lowerBound]))
            }
            if !id.isEmpty, !name.isEmpty { items.append(Item(id: id, name: name, isFolder: isFolder, size: 0)) }
        }
        return items
    }

    private static func decodeEntities(_ s: String) -> String {
        var r = s
        for (k, v) in [("&amp;", "&"), ("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">")] {
            r = r.replacingOccurrences(of: k, with: v)
        }
        return r.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Naming helpers

    static let audioExts: Set<String> = ["mp3", "m4a", "aac", "wav", "mp4", "m4v", "mov"]
    static func ext(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }
    static func isAudio(_ name: String) -> Bool { audioExts.contains(ext(name)) }

    /// Folder name -> (id, display name). Matches the class-recordings site.
    static func subjectInfo(_ folder: String) -> (String, String) {
        let key = folder.lowercased().trimmingCharacters(in: .whitespaces)
        if key.contains("usool") || key.contains("usul") { return ("usool", "Usool") }
        if key.contains("tafs") { return ("tafseer", "Tafseer") }
        if key.contains("nahv") || key.contains("nahw") { return ("nahv", "Hidayatun Nahv") }
        let id = key.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return (id, folder)
    }

    static func order(_ id: String) -> Int { ["usool": 0, "tafseer": 1, "nahv": 2][id] ?? 9 }

    /// "Usool 04-10-2026.mp3" -> "2026-04-10"
    static func date(from name: String) -> String? {
        guard let r = name.range(of: #"(\d{1,2})-(\d{1,2})-(\d{4})"#, options: .regularExpression) else { return nil }
        let p = name[r].split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return String(format: "%04d-%02d-%02d", p[2], p[0], p[1])
    }

    /// Accepts a full Drive folder link or a bare id.
    static func folderID(fromLink s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: #"folders/([A-Za-z0-9_-]+)"#, options: .regularExpression) {
            return String(t[r].dropFirst("folders/".count))
        }
        if let c = URLComponents(string: t), let id = c.queryItems?.first(where: { $0.name == "id" })?.value { return id }
        return t
    }
}
