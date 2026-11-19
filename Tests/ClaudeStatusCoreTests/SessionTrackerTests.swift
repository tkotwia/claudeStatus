import XCTest
@testable import ClaudeStatusCore

final class SessionTrackerTests: XCTestCase {
    private func session(_ pid: Int32, _ status: String, cwd: String = "/work/app") -> Session {
        Session(pid: pid, cwd: cwd, status: status)
    }

    // VS Code reopens panels that are never used. They are idle from the first moment we see
    // them and must not nag the user as "done".
    func testSessionsAlreadyIdleWhenFirstSeenAreNotDone() {
        var tracker = SessionTracker()
        let snapshot = tracker.update(with: [session(1, "idle"), session(2, "idle")])
        XCTAssertTrue(snapshot.done.isEmpty)
        XCTAssertEqual(snapshot.idle.map(\.pid), [1, 2])
    }

    func testFinishingATurnMarksTheSessionDone() {
        var tracker = SessionTracker()
        _ = tracker.update(with: [session(1, "busy")])
        let snapshot = tracker.update(with: [session(1, "idle")])
        XCTAssertEqual(snapshot.done.map(\.pid), [1])
        XCTAssertTrue(snapshot.idle.isEmpty)
    }

    // A prompt that ends the turn (e.g. denied and stopped) also leaves the session waiting
    // for the next instruction.
    func testLeavingABlockedStateForIdleAlsoMarksDone() {
        var tracker = SessionTracker()
        _ = tracker.update(with: [session(1, "waiting")])
        XCTAssertEqual(tracker.update(with: [session(1, "shell")]).done.map(\.pid), [1])
    }

    // "Done" is an attention flag: it has to stay up until the user deals with it, however
    // many refreshes pass in between.
    func testDoneStaysUntilHandled() {
        var tracker = SessionTracker()
        _ = tracker.update(with: [session(1, "busy")])
        for _ in 0..<5 {
            XCTAssertEqual(tracker.update(with: [session(1, "idle")]).done.map(\.pid), [1])
        }
    }

    func testClickingTheSessionClearsDone() {
        var tracker = SessionTracker()
        _ = tracker.update(with: [session(1, "busy")])
        _ = tracker.update(with: [session(1, "idle")])
        tracker.acknowledge(pid: 1)
        let snapshot = tracker.update(with: [session(1, "idle")])
        XCTAssertTrue(snapshot.done.isEmpty)
        XCTAssertEqual(snapshot.idle.map(\.pid), [1])
    }

    func testSendingTheNextPromptClearsDone() {
        var tracker = SessionTracker()
        _ = tracker.update(with: [session(1, "busy")])
        _ = tracker.update(with: [session(1, "idle")])
        let snapshot = tracker.update(with: [session(1, "busy")])
        XCTAssertTrue(snapshot.done.isEmpty)
        XCTAssertEqual(snapshot.running.map(\.pid), [1])
    }

    // Reset dismisses what is finished now. It must not touch sessions that still need the user
    // or are still working, and it must not mute a session that finishes again later.
    func testResetClearsEveryDoneSessionAndNothingElse() {
        var tracker = SessionTracker()
        _ = tracker.update(with: [session(1, "busy"), session(2, "busy"), session(3, "busy"), session(4, "busy")])
        let sessions = [session(1, "idle"), session(2, "idle"), session(3, "busy"), session(4, "waiting")]
        XCTAssertEqual(tracker.update(with: sessions).done.map(\.pid), [1, 2])

        tracker.acknowledgeAll()
        let afterReset = tracker.update(with: sessions)
        XCTAssertTrue(afterReset.done.isEmpty)
        XCTAssertEqual(afterReset.running.map(\.pid), [3])
        XCTAssertEqual(afterReset.blocked.map(\.pid), [4])

        _ = tracker.update(with: [session(1, "busy"), session(2, "idle"), session(3, "busy"), session(4, "waiting")])
        let finishedAgain = tracker.update(with: [session(1, "idle"), session(2, "idle"), session(3, "busy"), session(4, "waiting")])
        XCTAssertEqual(finishedAgain.done.map(\.pid), [1])
    }

    // A closed session must not leave a flag behind that a later process with the same pid
    // would inherit.
    func testClosingTheSessionClearsDone() {
        var tracker = SessionTracker()
        _ = tracker.update(with: [session(1, "busy")])
        _ = tracker.update(with: [session(1, "idle")])
        _ = tracker.update(with: [])
        XCTAssertTrue(tracker.update(with: [session(1, "idle")]).done.isEmpty)
    }

    // The three numbers in the menu bar are independent: each session is in exactly one group.
    func testSnapshotGroupsEachSessionOnce() {
        var tracker = SessionTracker()
        _ = tracker.update(with: [session(1, "busy"), session(2, "busy"), session(3, "busy"), session(4, "idle")])
        let snapshot = tracker.update(with: [session(1, "busy"), session(2, "waiting"), session(3, "idle"), session(4, "idle")])
        XCTAssertEqual(snapshot.running.map(\.pid), [1])
        XCTAssertEqual(snapshot.blocked.map(\.pid), [2])
        XCTAssertEqual(snapshot.done.map(\.pid), [3])
        XCTAssertEqual(snapshot.idle.map(\.pid), [4])
        XCTAssertEqual(snapshot.all.count, 4)
    }
}
