import Foundation

/// One `~/.claude/sessions/<pid>.json` entry, written by Claude Code for every live session.
/// The format is undocumented, so only `pid` is required and unknown values are tolerated.
public struct Session: Equatable {
    public var pid: Int32
    public var sessionId: String?
    public var cwd: String?
    public var name: String?
    public var entrypoint: String?
    public var kind: String?
    public var status: String?
    public var waitingFor: String?
    public var procStart: String?
    public var pidDomain: String?

    public init(
        pid: Int32, sessionId: String? = nil, cwd: String? = nil, name: String? = nil,
        entrypoint: String? = nil, kind: String? = nil, status: String? = nil,
        waitingFor: String? = nil, procStart: String? = nil, pidDomain: String? = nil
    ) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.name = name
        self.entrypoint = entrypoint
        self.kind = kind
        self.status = status
        self.waitingFor = waitingFor
        self.procStart = procStart
        self.pidDomain = pidDomain
    }
}

extension Session: Decodable {
    private enum CodingKeys: String, CodingKey {
        case pid, sessionId, cwd, name, entrypoint, kind, status, waitingFor, procStart, pidDomain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A missing, null or wrongly typed optional field must not hide the whole session.
        func string(_ key: CodingKeys) -> String? { try? container.decode(String.self, forKey: key) }
        self.init(
            pid: try container.decode(Int32.self, forKey: .pid),
            sessionId: string(.sessionId), cwd: string(.cwd), name: string(.name),
            entrypoint: string(.entrypoint), kind: string(.kind), status: string(.status),
            waitingFor: string(.waitingFor), procStart: string(.procStart), pidDomain: string(.pidDomain)
        )
    }
}

public enum Activity: Equatable {
    /// Claude is thinking or running tools.
    case running
    /// Claude cannot continue until the user answers a prompt.
    case blocked
    /// The turn is over (or never started).
    case idle
}

extension Session {
    public var activity: Activity {
        switch status {
        case "busy": return .running
        case "waiting": return .blocked
        default: return .idle  // "idle", "shell" (idle with background shells), or a value we don't know
        }
    }

    /// Daemon supervisors are not sessions, and a pid from another pid namespace
    /// (e.g. a container sharing ~/.claude) cannot be checked for liveness on this host.
    public var isTracked: Bool {
        kind != "daemon" && kind != "daemon-worker" && (pidDomain == nil || pidDomain == "darwin")
    }

    /// `procStart` is `ps -o lstart` in UTC ("Thu Nov 19 07:12:13 2026"); Claude Code records it
    /// so a reused pid can be told apart from the original process.
    public var procStartDate: Date? {
        guard let procStart else { return nil }
        // lstart pads single-digit days with an extra space.
        let normalized = procStart.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return Session.procStartFormatter.date(from: normalized)
    }

    private static let procStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()

    public var sourceLabel: String {
        switch entrypoint {
        case "claude-vscode": return "VS Code"
        case "claude-desktop", "claude-desktop-3p": return "Desktop"
        case "cli": return "CLI"
        case let other?: return other
        case nil: return "?"
        }
    }

    public var folderName: String {
        guard let cwd, !cwd.isEmpty else { return "?" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    public var blockedReason: String {
        switch waitingFor {
        case "permission prompt": return "needs permission"
        case "input needed": return "needs your answer"
        case let other?: return other
        case nil: return "waiting"
        }
    }
}
