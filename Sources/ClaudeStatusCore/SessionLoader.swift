import Foundation

/// Turns the raw contents of the sessions directory into live sessions.
///
/// A file can be caught half-written exactly when its status changes. Dropping the session for
/// that instant would lose the transition the tracker needs, so the last good parse is kept and
/// a file is only reported as unreadable after it keeps failing.
public struct SessionLoader {
    public struct Result: Equatable {
        public var sessions: [Session]
        /// Files that have failed to parse `failureThreshold` times in a row.
        public var unreadable: Int
        /// A file failed but may just be mid-write; read again shortly.
        public var needsRetry: Bool
    }

    public static let failureThreshold = 3

    private var lastGood: [String: Session] = [:]
    private var failures: [String: Int] = [:]

    public init() {}

    /// Session files are `<pid>.json`. The directory also holds `<pid>.<hash>.key` secrets,
    /// which must never be read.
    public static func isSessionFile(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        let stem = name.dropLast(".json".count)
        return !stem.isEmpty && stem.allSatisfy { ("0"..."9").contains($0) }
    }

    /// - Parameter files: file name → contents, `nil` when the file could not be read.
    public mutating func load(files: [String: Data?], isAlive: (Session) -> Bool) -> Result {
        lastGood = lastGood.filter { files.keys.contains($0.key) }
        failures = failures.filter { files.keys.contains($0.key) }

        var sessions: [Session] = []
        for (name, data) in files where SessionLoader.isSessionFile(name) {
            if let data, let session = try? JSONDecoder().decode(Session.self, from: data) {
                lastGood[name] = session
                failures[name] = nil
                sessions.append(session)
            } else {
                failures[name, default: 0] += 1
                if let previous = lastGood[name] { sessions.append(previous) }
            }
        }

        return Result(
            sessions: sessions.filter { $0.isTracked && isAlive($0) },
            unreadable: failures.values.filter { $0 >= SessionLoader.failureThreshold }.count,
            needsRetry: failures.values.contains { $0 < SessionLoader.failureThreshold }
        )
    }
}
