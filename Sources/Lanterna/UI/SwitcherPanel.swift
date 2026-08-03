import AppKit

/// Borderless floating panel that hosts the switcher list.
///
/// The non-activating style is what lets the panel appear without taking focus
/// away from the application the user is working in.
final class SwitcherPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // The SwiftUI surface draws its own shadow.
        hasShadow = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
    }

    /// No keyboard input reaches the panel yet, so it must never become key or
    /// main. The local key monitor of a later step will revisit this.
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
