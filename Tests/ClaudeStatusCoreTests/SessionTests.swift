import XCTest
@testable import ClaudeStatusCore

final class SessionTests: XCTestCase {
    private func decode(_ json: String) throws -> Session {
        try JSONDecoder().decode(Session.self, from: Data(json.utf8))
    }

    // The menu bar number means "Claude is working right now". Anything else must not inflate it.
    func testOnlyBusyCountsAsRunning() {
        XCTAssertEqual(Session(pid: 1, status: "busy").activity, .running)
        for status in ["idle", "shell", "some-future-status", nil] {
            XCTAssertEqual(Session(pid: 1, status: status).activity, .idle, "status \(status ?? "nil")")
        }
    }

    // Every kind of prompt stops Claude until the user acts, so all of them are "blocked",
    // including reasons this app has never heard of.
    func testWaitingIsBlockedWhateverTheReason() {
        for reason in ["permission prompt", "input needed", "sandbox request", "some-future-reason", nil] {
            XCTAssertEqual(Session(pid: 1, status: "waiting", waitingFor: reason).activity, .blocked)
        }
    }

    // The file format is undocumented and differs between Claude Code versions. A session must
    // still show up when fields are missing, null, or have an unexpected type.
    func testDecodingSurvivesMissingNullAndMistypedFields() throws {
        let session = try decode(#"{"pid": 42, "status": "busy", "cwd": null, "name": {"unexpected": true}}"#)
        XCTAssertEqual(session.pid, 42)
        XCTAssertEqual(session.activity, .running)
        XCTAssertNil(session.cwd)
        XCTAssertNil(session.name)
    }

    func testDecodingReadsARealSessionFile() throws {
        let session = try decode("""
        {"pid":42057,"sessionId":"72bf","cwd":"/Users/me/project/claudeStatus","startedAt":1795072333724,
         "procStart":"Thu Nov 19 07:12:13 2026","version":"2.1.328","kind":"interactive",
         "entrypoint":"claude-vscode","pidDomain":"darwin","name":"status icon",
         "status":"waiting","waitingFor":"input needed","updatedAt":1795072658245}
        """)
        XCTAssertEqual(session.activity, .blocked)
        XCTAssertEqual(session.sourceLabel, "VS Code")
        XCTAssertEqual(session.folderName, "claudeStatus")
        XCTAssertEqual(session.blockedReason, "等你回答")
        XCTAssertTrue(session.isTracked)
    }

    // Without a pid there is nothing to check for liveness, so the file is not a usable session.
    func testDecodingRequiresPid() {
        XCTAssertThrowsError(try decode(#"{"status": "busy"}"#))
    }

    // The daemon supervisor is not something the user is talking to, and a pid from another
    // pid namespace would be checked against the wrong process table.
    func testDaemonsAndForeignPidNamespacesAreNotTracked() {
        XCTAssertTrue(Session(pid: 1, kind: "interactive").isTracked)
        XCTAssertTrue(Session(pid: 1, kind: "bg").isTracked)
        XCTAssertFalse(Session(pid: 1, kind: "daemon").isTracked)
        XCTAssertFalse(Session(pid: 1, kind: "daemon-worker").isTracked)
        XCTAssertFalse(Session(pid: 1, kind: "interactive", pidDomain: "linux").isTracked)
    }

    // procStart guards against pid reuse, so it has to match what the kernel reports (UTC seconds).
    func testProcStartIsParsedAsUTC() {
        XCTAssertEqual(
            Session(pid: 1, procStart: "Thu Nov 19 07:12:13 2026").procStartDate?.timeIntervalSince1970,
            1_795_072_333
        )
        // `ps -o lstart` pads single-digit days with two spaces.
        XCTAssertEqual(
            Session(pid: 1, procStart: "Mon Nov  9 07:12:13 2026").procStartDate?.timeIntervalSince1970,
            1_795_072_333 - 10 * 86_400
        )
        XCTAssertNil(Session(pid: 1, procStart: "garbage").procStartDate)
        XCTAssertNil(Session(pid: 1).procStartDate)
    }

    func testSourceLabelsCoverTheThreeSurfacesAndPassUnknownOnesThrough() {
        XCTAssertEqual(Session(pid: 1, entrypoint: "claude-vscode").sourceLabel, "VS Code")
        XCTAssertEqual(Session(pid: 1, entrypoint: "claude-desktop").sourceLabel, "Desktop")
        XCTAssertEqual(Session(pid: 1, entrypoint: "cli").sourceLabel, "CLI")
        XCTAssertEqual(Session(pid: 1, entrypoint: "sdk-ts").sourceLabel, "sdk-ts")
    }
}
