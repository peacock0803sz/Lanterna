import AppKit

/// The menu-bar entry point.
///
/// Held for the whole run. It owns no keyboard monitoring of any kind: every
/// entry opens a window or quits, and nothing here touches the three keyboard
/// layers.
@MainActor
final class StatusMenu {
    /// Held so the item outlives the call that makes it. Dropping it would
    /// take the menu down with it.
    private var item: NSStatusItem?

    /// Puts the menu up. The settings entry opens the settings window,
    /// which now carries the permission check on its General tab. The
    /// version entry opens the version and log window, and the quit entry
    /// ends the process through the usual teardown.
    func stand(openSettings: @escaping () -> Void, openVersionLog: @escaping () -> Void) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◈"
        item.button?.toolTip = "Lanterna"
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMenu(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.representedObject = openSettings
        menu.addItem(settingsItem)
        let versionItem = NSMenuItem(
            title: "Version and Logs…",
            action: #selector(openVersionLogFromMenu(_:)),
            keyEquivalent: ""
        )
        versionItem.target = self
        versionItem.representedObject = openVersionLog
        menu.addItem(versionItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit Lanterna",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        menu.addItem(quitItem)
        item.menu = menu
        self.item = item
    }

    /// Takes the menu down on the way out. The status bar would drop it with
    /// the process regardless; this keeps the teardown explicit.
    func remove() {
        if let item {
            NSStatusBar.system.removeStatusItem(item)
        }
        item = nil
    }

    /// Unpacks the closure the menu item carries. A selector cannot carry a
    /// closure, so it rides along as the represented object.
    @objc private func openSettingsFromMenu(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }

    /// The version twin of the above. One unpacker per entry, so a click can
    /// never open the wrong window.
    @objc private func openVersionLogFromMenu(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}
