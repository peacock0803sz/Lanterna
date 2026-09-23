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

    /// Puts the menu up. The guide entry reopens the onboarding window; the
    /// quit entry ends the process through the usual teardown.
    func stand(openGuide: @escaping () -> Void) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◈"
        item.button?.toolTip = "Lanterna"
        let menu = NSMenu()
        let guideItem = NSMenuItem(
            title: "Check Permissions…",
            action: #selector(openGuideFromMenu(_:)),
            keyEquivalent: ""
        )
        guideItem.target = self
        guideItem.representedObject = openGuide
        menu.addItem(guideItem)
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
    @objc private func openGuideFromMenu(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}
