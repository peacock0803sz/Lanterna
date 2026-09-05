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

    /// The enumerator's name fallback (`RunningApplicationInfo.displayName`)
    /// rules out an empty name upstream, so one reaching a row is a programming
    /// error; `displayTitle` is never empty only because of this.
    init(
        id: Identifier,
        ownerProcessIdentifier: pid_t,
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String,
        kind: WindowKind,
        isMinimized: Bool,
        icon: NSImage
    ) {
        precondition(!appName.isEmpty, "appName must not be empty")
        self.id = id
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.kind = kind
        self.isMinimized = isMinimized
        self.icon = icon
    }

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
