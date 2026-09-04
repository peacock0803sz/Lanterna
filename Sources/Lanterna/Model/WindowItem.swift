import AppKit

/// One switchable window as shown in the switcher list.
///
/// Every value except the icon comes from a static fixture, and the view layer
/// consumes nothing else, so this shape is the contract between the two.
struct WindowItem: Identifiable {
    /// Identity of a row, and so `WindowItem.ID` through `Identifiable`. The
    /// payload is a UUID because a fixture row has no system handle to borrow;
    /// wrapping it means the payload can change without touching
    /// `SwitcherView.selectedID` or the list rendering.
    struct Identifier: Hashable {
        let rawValue: UUID

        init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
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
