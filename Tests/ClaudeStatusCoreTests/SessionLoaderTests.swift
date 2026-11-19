import XCTest
@testable import ClaudeStatusCore

final class SessionLoaderTests: XCTestCase {
    private func file(pid: Int32, status: String) -> Data {
        Data(#"{"pid": \#(pid), "status": "\#(status)", "kind": "interactive"}"#.utf8)
    }

    private let alive: (Session) -> Bool = { _ in true }

    // The sessions directory also contains `<pid>.<hash>.key` socket secrets. They are not
    // sessions and this app has no business reading them.
    func testOnlyPidJsonFilesAreSessionFiles() {
        XCTAssertTrue(SessionLoader.isSessionFile("42057.json"))
        XCTAssertFalse(SessionLoader.isSessionFile("42057.0a1b2c.key"))
        XCTAssertFalse(SessionLoader.isSessionFile("42057.0a1b2c.json"))
        XCTAssertFalse(SessionLoader.isSessionFile(".json"))
        XCTAssertFalse(SessionLoader.isSessionFile("notes.json"))
    }

    // A crashed session leaves its file behind with whatever status it had. Counting it would
    // show a session as running forever.
    func testSessionsWhoseProcessIsGoneAreExcluded() {
        var loader = SessionLoader()
        let result = loader.load(
            files: ["1.json": file(pid: 1, status: "busy"), "2.json": file(pid: 2, status: "busy")],
            isAlive: { $0.pid == 2 }
        )
        XCTAssertEqual(result.sessions.map(\.pid), [2])
    }

    // Files are rewritten exactly when the status changes. If a half-written file made the
    // session vanish for one refresh, the tracker would miss the busy → idle transition.
    func testAHalfWrittenFileKeepsTheLastKnownStateAndAsksForARetry() {
        var loader = SessionLoader()
        _ = loader.load(files: ["1.json": file(pid: 1, status: "busy")], isAlive: alive)
        let result = loader.load(files: ["1.json": Data(#"{"pid": 1, "sta"#.utf8)], isAlive: alive)
        XCTAssertEqual(result.sessions.map(\.status), ["busy"])
        XCTAssertTrue(result.needsRetry)
        XCTAssertEqual(result.unreadable, 0)
    }

    // A file that stays broken means the format changed or something is wrong. The user must
    // be told instead of seeing a reassuring zero.
    func testAFileThatStaysBrokenIsReportedAsUnreadable() {
        var loader = SessionLoader()
        var result = loader.load(files: ["1.json": Data("not json".utf8)], isAlive: alive)
        for _ in 1..<SessionLoader.failureThreshold {
            XCTAssertEqual(result.unreadable, 0)
            result = loader.load(files: ["1.json": Data("not json".utf8)], isAlive: alive)
        }
        XCTAssertEqual(result.unreadable, 1)
        XCTAssertFalse(result.needsRetry)
        XCTAssertTrue(result.sessions.isEmpty)
    }

    func testAFileThatRecoversIsNoLongerReported() {
        var loader = SessionLoader()
        for _ in 0..<SessionLoader.failureThreshold {
            _ = loader.load(files: ["1.json": nil], isAlive: alive)
        }
        let result = loader.load(files: ["1.json": file(pid: 1, status: "idle")], isAlive: alive)
        XCTAssertEqual(result.unreadable, 0)
        XCTAssertEqual(result.sessions.map(\.pid), [1])
    }

    // Once the file is deleted the session has ended; the cached copy must not keep it alive.
    func testADeletedFileRemovesTheSession() {
        var loader = SessionLoader()
        _ = loader.load(files: ["1.json": file(pid: 1, status: "busy")], isAlive: alive)
        XCTAssertTrue(loader.load(files: [:], isAlive: alive).sessions.isEmpty)
    }
}
