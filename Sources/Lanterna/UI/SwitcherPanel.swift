import AppKit

/// Borderless floating panel that hosts the switcher list.
///
/// The non-activating style is what lets the panel appear without taking focus
/// away from the application the user is working in.
final class SwitcherPanel: NSPanel {
    /// The panel frame is the one place the switcher's size is decided; the
    /// SwiftUI content fills whatever frame the panel is given.
    init(rowCount: Int) {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PanelMetrics.width,
                height: PanelMetrics.height(rowCount: rowCount)
            ),
            // Borderless is the absence of `.titled`, so it needs no flag.
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // On macOS 15 the drop shadow is the window's, which NSPanel draws by
        // default: a shadow drawn inside SwiftUI would be clipped, because the
        // panel frame is exactly the content frame. Only macOS 26 needs a
        // change, where Liquid Glass brings its own shadow.
        if #available(macOS 26.0, *) {
            hasShadow = false
        }
        hidesOnDeactivate = false
    }

    /// No keyboard input is routed to the panel, and the process must never
    /// become the active application, so key and main status stay with the
    /// application the user is working in.
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
