import Foundation

public struct Snapshot: Equatable {
    public var running: [Session] = []
    public var blocked: [Session] = []
    /// Finished a turn and not yet handled by the user.
    public var done: [Session] = []
    public var idle: [Session] = []

    public var all: [Session] { blocked + running + done + idle }
}

/// Remembers which sessions finished a turn while we were watching, so they can be shown as
/// "done" until the user handles them. The session files alone cannot tell a session that just
/// finished from one that has been sitting idle (or was never used).
public struct SessionTracker {
    private var lastActivity: [Int32: Activity] = [:]
    private var donePids: Set<Int32> = []

    public init() {}

    public mutating func update(with sessions: [Session]) -> Snapshot {
        var seen: [Int32: Activity] = [:]
        for session in sessions {
            let now = session.activity
            if now == .idle {
                // Only a transition we witnessed counts; sessions already idle at launch stay quiet.
                if let before = lastActivity[session.pid], before != .idle {
                    donePids.insert(session.pid)
                }
            } else {
                donePids.remove(session.pid)
            }
            seen[session.pid] = now
        }
        donePids.formIntersection(seen.keys)
        lastActivity = seen

        var snapshot = Snapshot()
        for session in sessions.sorted(by: { ($0.folderName, $0.pid) < ($1.folderName, $1.pid) }) {
            switch session.activity {
            case .running: snapshot.running.append(session)
            case .blocked: snapshot.blocked.append(session)
            case .idle:
                if donePids.contains(session.pid) {
                    snapshot.done.append(session)
                } else {
                    snapshot.idle.append(session)
                }
            }
        }
        return snapshot
    }

    /// The user has looked at this session (clicked it in the menu).
    public mutating func acknowledge(pid: Int32) {
        donePids.remove(pid)
    }

    /// The user dismissed every "done" session at once.
    public mutating func acknowledgeAll() {
        donePids.removeAll()
    }
}
