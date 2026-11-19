import Foundation

/// A session that just started needing the user, which is worth a notification.
public struct AttentionEvent: Equatable {
    public enum Kind: Equatable {
        case blocked, done
    }

    public var kind: Kind
    public var session: Session

    public var title: String { "\(session.folderName) · \(session.sourceLabel)" }

    public var body: String {
        switch kind {
        case .blocked: return "Blocked: \(session.blockedReason)"
        case .done: return "Done: waiting for your next instruction"
        }
    }
}

extension Snapshot {
    /// Sessions that are blocked or done now and were not in `previous`.
    ///
    /// With no previous snapshot nothing is reported: sessions already waiting when the app
    /// starts are visible in the menu bar and should not all be announced at once.
    public func attentionEvents(since previous: Snapshot?) -> [AttentionEvent] {
        guard let previous else { return [] }
        let wasBlocked = Set(previous.blocked.map(\.pid))
        let wasDone = Set(previous.done.map(\.pid))
        return blocked.filter { !wasBlocked.contains($0.pid) }.map { AttentionEvent(kind: .blocked, session: $0) }
            + done.filter { !wasDone.contains($0.pid) }.map { AttentionEvent(kind: .done, session: $0) }
    }
}
