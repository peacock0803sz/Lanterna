import AppKit

/// Borderless floating panel that hosts the switcher list.
///
/// The non-activating style is what lets the panel appear without taking focus
/// away from the application the user is working in.
final class SwitcherPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // Borderless is the absence of `.titled`, so it needs no flag.
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        if #available(macOS 26.0, *) {
            // Liquid Glass brings its own shadow.
            hasShadow = false
        } else {
            // A shadow drawn inside SwiftUI would be clipped, because the panel
            // frame is exactly the content frame, so AppKit draws the drop
            // shadow the macOS 15 appearance requires.
            hasShadow = true
        }
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
