import AppKit
import ClaudeStatusCore

/// Brings the window that hosts a session to the front, as precisely as each surface allows.
enum Jumper {
    static func jump(to session: Session) {
        switch session.entrypoint {
        case "claude-vscode":
            jumpToVSCode(session)
        case "claude-desktop", "claude-desktop-3p":
            // Claude Desktop has no public deep link to a session, so the app is as close as we get.
            activate(NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first)
        default:
            if !selectITermSession(of: session.pid) {
                activate(hostApp(of: session.pid))
            }
        }
    }

    // MARK: VS Code

    private static func jumpToVSCode(_ session: Session) {
        guard let app = hostApp(of: session.pid), let appURL = app.bundleURL else {
            NSSound.beep()
            return
        }
        guard let cwd = session.cwd, let folder = workspaceFolder(containing: cwd) else {
            activate(app)
            return
        }
        // Opening a folder that is already open focuses its window.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: appURL, configuration: configuration) { _, error in
            guard error == nil, app.bundleIdentifier == "com.microsoft.VSCode", let id = session.sessionId,
                  let url = URL(string: "vscode://anthropic.claude-code/open?session=\(id)") else { return }
            // The extension's URI handler focuses the session's tab, but VS Code delivers the
            // URI to whichever window is focused, so give the window above time to come forward.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// The workspace root of the VS Code window that contains `cwd`, from the lock files the
    /// extension keeps per window.
    private static func workspaceFolder(containing cwd: String) -> String? {
        let ideDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/ide")
        let locks = (try? FileManager.default.contentsOfDirectory(at: ideDirectory, includingPropertiesForKeys: nil)) ?? []
        struct Lock: Decodable { var workspaceFolders: [String]? }
        return locks
            .filter { $0.pathExtension == "lock" }
            .compactMap { try? JSONDecoder().decode(Lock.self, from: Data(contentsOf: $0)) }
            .flatMap { $0.workspaceFolders ?? [] }
            .filter { cwd == $0 || cwd.hasPrefix($0 + "/") }
            .max { $0.count < $1.count }
    }

    // MARK: Terminal

    /// Selects the iTerm2 tab whose tty runs the session. False when iTerm2 is not hosting it.
    private static func selectITermSession(of pid: pid_t) -> Bool {
        guard let tty = tty(of: pid),
              !NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").isEmpty
        else { return false }
        let source = """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            tell w to select
                            tell t to select
                            tell s to select
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return result?.booleanValue ?? false
    }

    private static func tty(of pid: pid_t) -> String? {
        guard let info = processInfo(of: pid), info.e_tdev != UInt32.max,
              let name = devname(dev_t(bitPattern: info.e_tdev), S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    // MARK: Apps

    /// The nearest ancestor process that is a regular app (the terminal, the editor…).
    private static func hostApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<32 {
            guard let info = processInfo(of: current) else { return nil }
            let parent = pid_t(info.pbi_ppid)
            guard parent > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: parent), app.activationPolicy == .regular {
                return app
            }
            current = parent
        }
        return nil
    }

    private static func activate(_ app: NSRunningApplication?) {
        guard let appURL = app?.bundleURL else {
            NSSound.beep()
            return
        }
        // Re-opening a running app through Launch Services brings it forward reliably, which
        // `NSRunningApplication.activate` no longer does from a background app.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
