import AppKit

/// One switchable window as shown in the switcher list.
///
/// The view layer consumes nothing else, so this shape is the contract between
/// the window enumeration and the list rendering.
struct WindowItem: Identifiable {
    /// Identity of a row, and so `WindowItem.ID` through `Identifiable`.
    ///
    /// The window-server id is unique while the window exists and is
    /// independent of the title, so two windows showing the same title stay two
    /// rows and a renamed window keeps its row.
    struct Identifier: Hashable {
        let windowID: CGWindowID
    }

    let id: Identifier
    let ownerProcessIdentifier: pid_t
    let appName: String
    let bundleIdentifier: String?
    /// The title exactly as the window reported it, which may be empty or hold
    /// nothing but whitespace.
    let windowTitle: String
    let kind: WindowKind
    /// Read for later steps; minimised rows look like any other row today.
    let isMinimized: Bool
    let icon: NSImage

    /// Title to draw. Trimming decides emptiness only: a title that has any
    /// content is drawn verbatim, leading and trailing whitespace included, so
    /// the row matches the title bar.
    var displayTitle: String {
        windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? appName
            : windowTitle
    }

    /// Hint shown at the left edge of a row. `prefix` yields the whole name when
    /// it is shorter than two characters, which is the intended behaviour.
    var shortcutHint: String {
        appName.prefix(2).lowercased()
    }
}
