import Darwin

/// What the presenter does when another application comes to the front.
///
/// Split from the presenter, which decides when a panel goes up, and kept
/// beside it rather than inside a file already at the length the linter
/// allows.
extension PanelPresenter {
    /// Takes the panel down when an application other than this one comes to
    /// the front, which is the user having moved on to something else.
    ///
    /// Every activation is announced, so most calls arrive with no panel up
    /// and must do nothing at all.
    ///
    /// This process is ruled out rather than assumed absent. The panel can
    /// take key status now, which is the part of this that changed, and
    /// taking it was measured not to bring the application forward: over
    /// twenty appearances no notification named this process, the frontmost
    /// application never changed, and the application never reported itself
    /// active. The reading is not an instrument that failed to fire, because
    /// a control that brought another application forward on purpose was
    /// announced both times.
    ///
    /// So a notification naming this process is not expected — and it is
    /// still compared for, because acting on one that did arrive would take a
    /// panel down the moment it appeared, or throw away a press still on its
    /// way to becoming one. One comparison is a cheap way never to find out
    /// the hard way.
    func handleActivation(of processIdentifier: pid_t) {
        guard processIdentifier != ownProcessIdentifier else { return }
        if pendingPress.isWaiting {
            // Nothing is on screen to take down. What has to stop is the
            // panel still on its way, which would otherwise appear over
            // whatever the user has just turned to. The line is for the press
            // and not for the panel: the press is what the user did, and one
            // that disappeared without a word could not be told from one that
            // never arrived at all. Written plainly rather than measured,
            // because every figure in these lines runs from something the
            // user did to this process answering it — a release, or one of
            // the keys that end an appearance — and nothing of the kind
            // happened here. The frontmost application changed on its own.
            pendingPress.callOff()
            writeLine(
                "called off the press waiting for its first list; "
                    + "the frontmost application changed"
            )
            return
        }
        guard surface.isPresented else { return }
        wayOut.takeDown(because: "frontmost application changed")
    }
}
