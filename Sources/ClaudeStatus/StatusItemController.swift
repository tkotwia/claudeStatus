import AppKit
import ClaudeStatusCore

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let reader = SessionReader()
    private var tracker = SessionTracker()
    /// `nil` when the sessions directory cannot be read.
    private var snapshot: Snapshot?
    private var unreadable = 0

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Claude sessions")
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        reader.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        reader.startWatching()

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
            snapshot = tracker.update(with: result.sessions)
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

        if unreadable > 0 {
            menu.addItem(disabledItem("⚠ 無法讀取 \(unreadable) 個 session 檔"))
            menu.addItem(.separator())
        }

        if let snapshot {
            addSection("被擋住", snapshot.blocked, symbol: "hand.raised.fill", to: menu) { " — \($0.blockedReason)" }
            addSection("執行中", snapshot.running, symbol: "circle.fill", to: menu)
            addSection("跑完", snapshot.done, symbol: "checkmark.circle.fill", to: menu)
            if snapshot.blocked.isEmpty && snapshot.running.isEmpty && snapshot.done.isEmpty {
                menu.addItem(disabledItem("沒有進行中的 session"))
            }
        } else {
            menu.addItem(disabledItem("⚠ 讀不到 \(reader.directory.path)"))
        }

        menu.addItem(.separator())
        if snapshot?.done.isEmpty == false {
            let reset = NSMenuItem(title: "清除跑完的 session", action: #selector(resetDone), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }
        menu.addItem(NSMenuItem(title: "結束", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
        guard let session = snapshot?.all.first(where: { Int($0.pid) == sender.tag }) else { return }
        Jumper.jump(to: session)
        tracker.acknowledge(pid: session.pid)
        refresh()
    }

    @objc private func resetDone() {
        tracker.acknowledgeAll()
        refresh()
    }
}
