import Foundation

/// Background downloads: they keep going when the app is closed or the phone is locked.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = Downloader()
    static let identifier = "org.alhikmahinstitute.zainabrecordings.downloads"

    /// Set by the app delegate when iOS wakes the app for finished background downloads.
    var backgroundCompletion: (() -> Void)?

    private struct Tag: Codable { var id: String; var dest: String }   // dest is relative to Documents

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        c.sessionSendsLaunchEvents = true
        c.isDiscretionary = false
        c.allowsCellularAccess = true
        c.httpMaximumConnectionsPerHost = 3
        c.timeoutIntervalForResource = 60 * 60 * 24
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    private var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    func wake() { _ = session }

    func start(sessionID: String, url: URL, destination: URL) {
        let rel = destination.path.replacingOccurrences(of: docs.path + "/", with: "")
        let task = session.downloadTask(with: url)
        task.taskDescription = String(data: try! JSONEncoder().encode(Tag(id: sessionID, dest: rel)), encoding: .utf8)
        task.resume()
    }

    func cancel(sessionID: String) {
        session.getAllTasks { tasks in
            tasks.filter { self.tag($0)?.id == sessionID }.forEach { $0.cancel() }
        }
    }

    func cancelAll() {
        session.getAllTasks { $0.forEach { $0.cancel() } }
    }

    /// After launch: mark recordings that are still downloading.
    func syncStates() async {
        let tasks = await session.allTasks
        let ids = tasks.filter { $0.state == .running || $0.state == .suspended }.compactMap { tag($0)?.id }
        await MainActor.run { ids.forEach { Library.shared.downloadQueued($0) } }
    }

    private func tag(_ t: URLSessionTask) -> Tag? {
        guard let s = t.taskDescription, let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Tag.self, from: d)
    }

    // MARK: Delegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = tag(downloadTask)?.id, totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in Library.shared.downloadProgress(id, p) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let t = tag(downloadTask) else { return }
        let http = downloadTask.response as? HTTPURLResponse
        let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if let code = http?.statusCode, !(200..<300).contains(code) {
            Task { @MainActor in Library.shared.downloadFinished(t.id, error: "Google Drive error \(code)") }
            return
        }
        if type.contains("text/html") {
            // Drive sent a web page instead of the file (not shared, or too many downloads today).
            Task { @MainActor in Library.shared.downloadFinished(t.id, error: "Google Drive didn't allow this download. Try again later.") }
            return
        }
        let dest = docs.appendingPathComponent(t.dest)
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            Task { @MainActor in Library.shared.downloadFinished(t.id, error: error.localizedDescription) }
            return
        }
        Task { @MainActor in Library.shared.downloadFinished(t.id, error: nil) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = tag(task)?.id else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        Task { @MainActor in Library.shared.downloadFinished(id, error: error.localizedDescription) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}
