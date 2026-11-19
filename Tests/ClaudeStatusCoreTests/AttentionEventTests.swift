import XCTest
@testable import ClaudeStatusCore

final class AttentionEventTests: XCTestCase {
    private func session(_ pid: Int32, _ status: String, waitingFor: String? = nil) -> Session {
        Session(pid: pid, cwd: "/work/app", entrypoint: "cli", status: status, waitingFor: waitingFor)
    }

    /// Feeds a sequence of directory states through the tracker and returns the events
    /// produced by the last step, the way the app does on every refresh.
    private func events(after steps: [[Session]]) -> [AttentionEvent] {
        var tracker = SessionTracker()
        var previous: Snapshot?
        var events: [AttentionEvent] = []
        for sessions in steps {
            let snapshot = tracker.update(with: sessions)
            events = snapshot.attentionEvents(since: previous)
            previous = snapshot
        }
        return events
    }

    // Restarting the app (login, reinstall) must not fire a burst of notifications for
    // sessions that were already waiting; the menu bar shows those.
    func testNothingIsAnnouncedWhenTheAppStarts() {
        XCTAssertTrue(events(after: [[session(1, "waiting"), session(2, "idle")]]).isEmpty)
    }

    func testBecomingBlockedIsAnnounced() {
        let result = events(after: [[session(1, "busy")], [session(1, "waiting", waitingFor: "permission prompt")]])
        XCTAssertEqual(result.map(\.kind), [.blocked])
        XCTAssertEqual(result.first?.session.pid, 1)
    }

    func testFinishingATurnIsAnnounced() {
        let result = events(after: [[session(1, "busy")], [session(1, "idle")]])
        XCTAssertEqual(result.map(\.kind), [.done])
    }

    // The directory is re-read every few seconds. A session that keeps waiting must produce
    // one notification, not one per refresh.
    func testStayingInTheSameStateIsNotAnnouncedAgain() {
        let blocked = [session(1, "waiting")]
        XCTAssertTrue(events(after: [[session(1, "busy")], blocked, blocked, blocked]).isEmpty)
        let done = [session(1, "idle")]
        XCTAssertTrue(events(after: [[session(1, "busy")], done, done, done]).isEmpty)
    }

    // Each new prompt is a new reason to look, even in a session that was announced before.
    func testBlockingAgainAfterResumingIsAnnouncedAgain() {
        let result = events(after: [
            [session(1, "busy")], [session(1, "waiting")], [session(1, "busy")], [session(1, "waiting")],
        ])
        XCTAssertEqual(result.map(\.kind), [.blocked])
    }

    // A session can open straight into a prompt. It was not there before, so it is news.
    func testASessionThatAppearsAlreadyBlockedIsAnnounced() {
        let result = events(after: [[session(1, "idle")], [session(1, "idle"), session(2, "waiting")]])
        XCTAssertEqual(result.map(\.session.pid), [2])
    }

    // Dealing with a session (answering, sending the next prompt, closing it) is the user
    // acting, not something to notify the user about.
    func testHandlingASessionAnnouncesNothing() {
        XCTAssertTrue(events(after: [[session(1, "busy")], [session(1, "waiting")], [session(1, "busy")]]).isEmpty)
        XCTAssertTrue(events(after: [[session(1, "busy")], [session(1, "idle")], [session(1, "busy")]]).isEmpty)
        XCTAssertTrue(events(after: [[session(1, "busy")], [session(1, "idle")], []]).isEmpty)
    }

    // Several sessions can change in the same refresh; none may be dropped.
    func testEveryChangedSessionIsAnnounced() {
        let result = events(after: [
            [session(1, "busy"), session(2, "busy"), session(3, "busy")],
            [session(1, "waiting"), session(2, "idle"), session(3, "busy")],
        ])
        XCTAssertEqual(result.map(\.kind), [.blocked, .done])
        XCTAssertEqual(result.map(\.session.pid), [1, 2])
    }

    // The notification has to say which session and why without opening the menu.
    func testTextNamesTheSessionAndTheReason() {
        let blocked = AttentionEvent(kind: .blocked, session: session(1, "waiting", waitingFor: "permission prompt"))
        XCTAssertEqual(blocked.title, "app · CLI")
        XCTAssertEqual(blocked.body, "Blocked: needs permission")
        let done = AttentionEvent(kind: .done, session: session(1, "idle"))
        XCTAssertEqual(done.title, "app · CLI")
        XCTAssertEqual(done.body, "Done: waiting for your next instruction")
    }
}
