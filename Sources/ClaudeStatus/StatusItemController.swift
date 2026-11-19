import AppKit
import ClaudeStatusCore

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let reader = SessionReader()
    private let notifier = Notifier()
    private var tracker = SessionTracker()
    /// `nil` when the sessions directory cannot be read.
    private var snapshot: Snapshot?
    private var unreadable = 0

    override init() {
        super.init()
        statusItem.button?.image = StatusItemController.menuBarIcon()
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        reader.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        reader.startWatching()

        notifier?.onClick = { [weak self] pid in
            MainActor.assumeIsolated { self?.jump(toPid: pid) }
        }

        // Catches sessions whose process died without removing its file. `.common` keeps it
        // firing while the menu is open.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)

        refresh()
    }

    private func refresh() {
        if let result = reader.read() {
            let updated = tracker.update(with: result.sessions)
            updated.attentionEvents(since: snapshot).forEach { notifier?.post($0) }
            snapshot = updated
            unreadable = result.unreadable
            if result.needsRetry {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
            }
        } else {
            snapshot = nil
            unreadable = 0
        }
        updateTitle()
    }

    // MARK: Menu bar title

    /// The bundled glyph, or an SF Symbol when running outside the app bundle (e.g. `swift run`),
    /// where a missing image would leave the status item invisible.
    private static func menuBarIcon() -> NSImage? {
        guard let icon = Bundle.main.image(forResource: "MenuBarIcon") else {
            return NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Claude sessions")
        }
        icon.isTemplate = true
        icon.accessibilityDescription = "Claude sessions"
        return icon
    }

    private func updateTitle() {
        let title = NSMutableAttributedString()
        if let snapshot {
            if !snapshot.running.isEmpty {
                title.append(text(" \(snapshot.running.count)", color: nil))
            }
            if !snapshot.blocked.isEmpty {
                title.append(segment(symbol: "hand.raised.fill", count: snapshot.blocked.count, color: .systemOrange))
            }
            if !snapshot.done.isEmpty {
                title.append(segment(symbol: "checkmark.circle.fill", count: snapshot.done.count, color: nil))
            }
        } else {
            title.append(text(" ?", color: nil))
        }
        statusItem.button?.attributedTitle = title
    }

    private func text(_ string: String, color: NSColor?) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuBarFont(ofSize: 0)]
        if let color { attributes[.foregroundColor] = color }
        return NSAttributedString(string: string, attributes: attributes)
    }

    private func segment(symbol: String, count: Int, color: NSColor?) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text("  ", color: nil))
        if var image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            if let color, let tinted = image.withSymbolConfiguration(.init(paletteColors: [color])) {
                image = tinted
            }
            let attachment = NSTextAttachment()
            attachment.image = image
            result.append(NSAttributedString(attachment: attachment))
        }
        result.append(text(" \(count)", color: color))
        return result
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        var warnings: [String] = []
        if unreadable > 0 {
            warnings.append("⚠ Cannot read \(unreadable) session file\(unreadable == 1 ? "" : "s")")
        }
        // The setting is fetched asynchronously, so a change shows the next time the menu opens.
        notifier?.refreshStatus()
        if notifier?.isDenied == true {
            warnings.append("⚠ Notifications are turned off in System Settings")
        } else if let notifier, notifier.isSoundOn, notifier.isSoundOffInSystem {
            warnings.append("⚠ Notification sound is turned off in System Settings")
        }
        if !warnings.isEmpty {
            warnings.forEach { menu.addItem(disabledItem($0)) }
            menu.addItem(.separator())
        }

        if let snapshot {
            addSection("Blocked", snapshot.blocked, symbol: "hand.raised.fill", to: menu) { " — \($0.blockedReason)" }
            addSection("Running", snapshot.running, symbol: "circle.fill", to: menu)
            addSection("Done", snapshot.done, symbol: "checkmark.circle.fill", to: menu)
            if snapshot.blocked.isEmpty && snapshot.running.isEmpty && snapshot.done.isEmpty {
                menu.addItem(disabledItem("No active sessions"))
            }
        } else {
            menu.addItem(disabledItem("⚠ Cannot read \(reader.directory.path)"))
        }

        menu.addItem(.separator())
        if snapshot?.done.isEmpty == false {
            let reset = NSMenuItem(title: "Clear Done Sessions", action: #selector(resetDone), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }
        if let notifier {
            let sound = NSMenuItem(title: "Notification Sound", action: #selector(toggleSound), keyEquivalent: "")
            sound.target = self
            sound.state = notifier.isSoundOn ? .on : .off
            menu.addItem(sound)
        }
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addSection(
        _ title: String, _ sessions: [Session], symbol: String, to menu: NSMenu,
        suffix: (Session) -> String = { _ in "" }
    ) {
        guard !sessions.isEmpty else { return }
        menu.addItem(.sectionHeader(title: title))
        sessions.forEach { menu.addItem(item(for: $0, symbol: symbol, suffix: suffix($0))) }
    }

    private func item(for session: Session, symbol: String, suffix: String) -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(session.folderName) · \(session.sourceLabel)\(suffix)",
            action: #selector(jump(_:)), keyEquivalent: ""
        )
        item.target = self
        item.tag = Int(session.pid)
        // The session name tells apart several sessions in the same folder.
        if let name = session.name, !name.isEmpty { item.subtitle = name }
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func jump(_ sender: NSMenuItem) {
        jump(toPid: Int32(sender.tag))
    }

    /// Shared by the menu and by clicking a notification; either way the user has now seen it.
    private func jump(toPid pid: Int32) {
        guard let session = snapshot?.all.first(where: { $0.pid == pid }) else { return }
        Jumper.jump(to: session)
        tracker.acknowledge(pid: pid)
        refresh()
    }

    @objc private func resetDone() {
        tracker.acknowledgeAll()
        refresh()
    }

    @objc private func toggleSound() {
        notifier?.isSoundOn.toggle()
    }
}
