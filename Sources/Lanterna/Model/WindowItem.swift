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
    struct Identifier: Hashable, Sendable {
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
    /// Whether the window is minimised: one of the ways a row parks below
    /// the separator (`isParked`), and what reconciling a minimize reads.
    let isMinimized: Bool
    /// Whether the owning application is hidden. Read with the names and
    /// icons, on the main thread, never by the parallel reading.
    let isHidden: Bool
    /// Whether the window lives on another Space. False until the per-window
    /// Space information arrives; unknown never hides.
    let isOnOtherSpace: Bool
    /// Whether the window is natively fullscreen. Read as one AX attribute;
    /// a manually zoomed window is not fullscreen.
    let isFullscreen: Bool
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
        isHidden: Bool = false,
        isOnOtherSpace: Bool = false,
        isFullscreen: Bool = false,
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
        self.isHidden = isHidden
        self.isOnOtherSpace = isOnOtherSpace
        self.isFullscreen = isFullscreen
        self.icon = icon
    }

    /// Whether the row parks below the separator: minimised or hidden.
    var isParked: Bool {
        isMinimized || isHidden
    }

    /// The rows in the order the panel draws them: the rows in use, then the
    /// parked rows, each group in the order it arrived in. The panel draws
    /// the parked group below the separator, and the choice and the arrows
    /// step through this same order, so a place on screen and a place in
    /// the list are one place.
    static func parkedLast(_ rows: [WindowItem]) -> [WindowItem] {
        rows.filter { !$0.isParked } + rows.filter(\.isParked)
    }

    /// The same row, marked minimized or not. The optimistic look moves
    /// rows before the reconciling pass confirms them.
    func settingMinimized(_ minimized: Bool) -> WindowItem {
        WindowItem(
            id: id,
            ownerProcessIdentifier: ownerProcessIdentifier,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            kind: kind,
            isMinimized: minimized,
            isHidden: isHidden,
            isOnOtherSpace: isOnOtherSpace,
            isFullscreen: isFullscreen,
            icon: icon
        )
    }

    /// The same row, marked hidden or shown. The optimistic look moves rows
    /// before the reconciling pass confirms them.
    func settingHidden(_ hidden: Bool) -> WindowItem {
        WindowItem(
            id: id,
            ownerProcessIdentifier: ownerProcessIdentifier,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            kind: kind,
            isMinimized: isMinimized,
            isHidden: hidden,
            isOnOtherSpace: isOnOtherSpace,
            isFullscreen: isFullscreen,
            icon: icon
        )
    }

    /// The same row, marked on another Space or not.
    func settingOnOtherSpace(_ onOtherSpace: Bool) -> WindowItem {
        WindowItem(
            id: id,
            ownerProcessIdentifier: ownerProcessIdentifier,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            kind: kind,
            isMinimized: isMinimized,
            isHidden: isHidden,
            isOnOtherSpace: onOtherSpace,
            isFullscreen: isFullscreen,
            icon: icon
        )
    }

    /// The same row, marked fullscreen or not.
    func settingFullscreen(_ fullscreen: Bool) -> WindowItem {
        WindowItem(
            id: id,
            ownerProcessIdentifier: ownerProcessIdentifier,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            kind: kind,
            isMinimized: isMinimized,
            isHidden: isHidden,
            isOnOtherSpace: isOnOtherSpace,
            isFullscreen: fullscreen,
            icon: icon
        )
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
