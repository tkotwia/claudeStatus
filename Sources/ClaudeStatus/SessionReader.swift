import ClaudeStatusCore
import CoreServices
import Darwin
import Foundation

/// Reads `~/.claude/sessions` and watches it for changes.
final class SessionReader {
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")

    /// Called on the main queue whenever something in the directory changes.
    var onChange: (() -> Void)?

    private var loader = SessionLoader()
    private var stream: FSEventStreamRef?

    /// `nil` when the directory cannot be listed at all.
    func read() -> SessionLoader.Result? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        var files: [String: Data?] = [:]
        for name in names where SessionLoader.isSessionFile(name) {
            files[name] = .some(try? Data(contentsOf: directory.appendingPathComponent(name)))
        }
        return loader.load(files: files, isAlive: SessionReader.isAlive)
    }

    func startWatching() {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<SessionReader>.fromOpaque(info).takeUnretainedValue().onChange?()
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    /// The process exists and is the one that wrote the file, not a later process reusing the pid.
    static func isAlive(_ session: Session) -> Bool {
        guard let info = processInfo(of: session.pid) else { return false }
        guard let recorded = session.procStartDate else { return true }
        return abs(Double(info.pbi_start_tvsec) - recorded.timeIntervalSince1970) <= 2
    }
}

func processInfo(of pid: pid_t) -> proc_bsdinfo? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return info
}
