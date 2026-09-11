import AppKit
import SwiftUI

/// Borderless floating panel that hosts the switcher list.
///
/// The non-activating style is what lets the panel appear without taking focus
/// away from the application the user is working in.
///
/// One panel is built once and shown many times. Rebuilding it per appearance
/// would put window creation on the path between the key press and the panel,
/// which is the one path that has a time budget.
final class SwitcherPanel: NSPanel {
    /// Held rather than dropped at the end of `init`: swapping the list in
    /// place needs a handle on the view that holds it.
    private let hostingView: NSHostingView<SwitcherView>

    /// The window decides its own size and the hosting view is denied any say
    /// in it. `update(windows:)` decides it again for a swapped-in list; the
    /// two cannot disagree, because both take their numbers from
    /// `PanelMetrics`.
    init(content: SwitcherView) {
        hostingView = NSHostingView(rootView: content)
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PanelMetrics.width,
                height: PanelMetrics.height(rowCount: content.windows.count)
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
        // Liquid Glass brings its own shadow, so the window must not draw the
        // one NSPanel gives it by default. Drawing the shadow inside SwiftUI
        // instead is not an option: it would be clipped, because the panel
        // frame is exactly the content frame.
        hasShadow = false
        hidesOnDeactivate = false

        // With no sizing options the SwiftUI intrinsic size cannot change the
        // window's content size or its minimum and maximum sizes.
        hostingView.sizingOptions = []
        contentView = hostingView

        // Nothing is removed. The observation ends with the process, and the
        // notification centre holds the token in the meantime whether or not
        // anyone else does.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The queue above is the main one, so this is the main actor's
            // executor; nothing weaker than a trap is wanted if that ever
            // stops being true.
            MainActor.assumeIsolated {
                self?.screensChanged()
            }
        }
    }

    /// Whether the panel is currently on screen.
    var isPresented: Bool {
        isVisible
    }

    /// Replaces the list and resizes to it, leaving the panel where it was:
    /// off screen if it was off screen, on screen if it was on.
    ///
    /// `SwitcherView` holds nothing but its array and the package has no
    /// observable state anywhere, so assigning a new root view is a complete
    /// swap; SwiftUI diffs the rows by their identity from there.
    func update(windows: [WindowItem]) {
        hostingView.rootView = SwitcherView(windows: windows)
        // The height is pushed down from the window, because the hosting view
        // has no sizing options and so cannot push one up.
        setContentSize(
            NSSize(
                width: PanelMetrics.width,
                height: PanelMetrics.height(rowCount: windows.count)
            )
        )
        centerOnMainDisplay()
    }

    func present(windows: [WindowItem]) {
        update(windows: windows)
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }

    /// Puts the panel back where it belongs after the displays have been
    /// rearranged.
    ///
    /// Between appearances nothing moves the panel, so a display change would
    /// otherwise leave one that is up wherever the old arrangement had put it.
    /// That is not only the wrong place. A panel left behind on a display that
    /// is no longer the main one does not go away when `dismiss()` asks it to,
    /// and the press that asked is spent: the panel stays on screen until a
    /// later appearance has moved it back. Moving it here is what keeps that
    /// state from arising.
    ///
    /// A panel that is down needs nothing. The next appearance places it, and
    /// this runs whenever anyone plugs in a display.
    func screensChanged() {
        guard isPresented else { return }
        centerOnMainDisplay()
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

    /// `NSWindow.center()` centres on whichever screen the window already sits
    /// on, so the display is picked explicitly. `NSScreen.screens.first` is the
    /// display that carries the menu bar, which is the one the panel belongs
    /// on; `NSScreen.main` would instead follow the key window and so could be
    /// any display.
    ///
    /// Run on every update, because a resize leaves the panel off centre.
    private func centerOnMainDisplay() {
        guard let area = NSScreen.screens.first?.visibleFrame else {
            center()
            return
        }
        let size = frame.size
        setFrameOrigin(
            NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        )
    }
}
