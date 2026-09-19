/// Holds a press that arrived before any list had been gathered, until there
/// is one to show it with.
///
/// Only a press arriving before the window list's first pass completes can get
/// here, which is the moment just after launch.
///
/// Kept in a file of its own. This is already its own piece of work — it has
/// state nothing else reads and a task nothing else starts — and the step that
/// lets the selection move does not touch it. Something of that size had to
/// come out of the presenter's file for its length to leave room for what that
/// step adds, and this is the one piece that comes out without widening what
/// anything can see: the press stays private to the presenter, which is now
/// the only thing holding one of these.
@MainActor
final class PendingPressHold {
    /// A press waiting for a list.
    private struct PendingPress {
        let combination: HotkeyCombination
        let deliveryDelay: Duration?
        /// When the press arrived. The reading spans the gathering too, which
        /// is why the line it produces says the gathering happened.
        let startedAt: ContinuousClock.Instant
    }

    /// The press that is waiting.
    ///
    /// Kept here rather than read back off the store. The task that does the
    /// waiting does not begin the instant it is made, and a second press
    /// landing in that gap would find the store idle and start a second wait.
    private var pending: PendingPress?

    /// Waits for a list and hands back the first one there is.
    ///
    /// Taken as a closure rather than a store, so what does the gathering is
    /// the holder's business and this has only the waiting to get right.
    private let listWhenGathered: @MainActor () async -> [WindowItem]

    /// Puts the panel up for the press that was waiting.
    private let show: @MainActor (
        [WindowItem],
        HotkeyCombination,
        Duration?,
        ContinuousClock.Instant
    ) -> Void

    /// Whether a press is waiting, which is to say whether a panel is on its
    /// way without being on screen yet.
    var isWaiting: Bool {
        pending != nil
    }

    init(
        listWhenGathered: @escaping @MainActor () async -> [WindowItem],
        show: @escaping @MainActor (
            [WindowItem],
            HotkeyCombination,
            Duration?,
            ContinuousClock.Instant
        ) -> Void
    ) {
        self.listWhenGathered = listWhenGathered
        self.show = show
    }

    /// Takes the press and arranges for a panel once there is a list.
    ///
    /// The task below carries none of the press with it; it is a standing
    /// "wake me once a list exists", and every field it shows the panel with
    /// is read out of `pending` at the moment it resumes. That is what makes
    /// two such tasks interchangeable: when a press is called off and another
    /// takes its place, whichever task wakes first finds the press that is
    /// really waiting and puts the panel up for it, and the other finds the
    /// slot empty and does nothing.
    func begin(
        _ combination: HotkeyCombination,
        deliveryDelay: Duration?,
        startedAt: ContinuousClock.Instant
    ) {
        pending = PendingPress(
            combination: combination,
            deliveryDelay: deliveryDelay,
            startedAt: startedAt
        )
        Task { [self] in
            let items = await listWhenGathered()
            guard let waiting = pending else { return }
            pending = nil
            show(items, waiting.combination, waiting.deliveryDelay, waiting.startedAt)
        }
    }

    /// Gives up on the press that was waiting, so nothing appears for it.
    ///
    /// Letting the slot go is what stops the panel still on its way. It also
    /// leaves the way clear for whatever comes next: while the slot is
    /// occupied every press is turned away as the duplicate of one already
    /// being answered.
    func callOff() {
        pending = nil
    }
}
