import AppKit

/// One switchable window as shown in the switcher list.
///
/// Every value except the icon comes from a static fixture, and the view layer
/// consumes nothing else, so this shape is the contract between the two.
struct WindowItem: Identifiable {
    /// Identity of a row, and so `WindowItem.ID` through `Identifiable`.
    /// `Identifier()` mints a fresh one and nothing else can be done with it,
    /// which is all the view layer needs: the stored value can become a window
    /// id without touching `SwitcherView.selectedID` or the list rendering.
    struct Identifier: Hashable {
        private let storage = UUID()
    }

    let id: Identifier
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String
    let icon: NSImage

    /// Hint shown at the left edge of a row. `prefix` yields the whole name when
    /// it is shorter than two characters, which is the intended behaviour.
    var shortcutHint: String {
        appName.prefix(2).lowercased()
    }
}
