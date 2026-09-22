/// Watches whether key presses are still reaching the panel that is up.
///
/// Losing key status leaves a panel that answers nothing: every keystroke is
/// swallowed, and on a run with no monitor there is not even a further press
/// that takes it down. So a look goes out on an interval for as long as the
/// panel is up, and a loss it finds is answered with one attempt to take the
/// keyboard back. Up to three such answers per appearance; the third one
/// failing ends the appearance instead.
///
/// Either a taking-back or a giving-up is reported for a loss, and never
/// both. A line for each would leave one loss counted twice, and the count
/// of appearances that lost the keyboard is taken by matching these lines.
///
/// Shaped like `UnreportedReleaseWatch`: no surface held, everything asked
/// through closures, so a test stages a loss by answering the closures
/// differently. The one thing this adds beside it is a clock, because a
/// taking-back is measured and a found release is not.
@MainActor
final class KeyStatusWatch {
    /// How long to wait between looks.
    ///
    /// In the worst case the loss happens just after a look went by: one
    /// interval to find it and try once, two more to spend the remaining
    /// attempts, 1.5 seconds altogether against a budget of 5. The sleep may
    /// be granted tolerance and come back late, which only spends budget that
    /// has room to spare.
    ///
    /// The other watch's fiftieth of a second is not followed here. That one
    /// is short so as not to race a release that is on its way; this one has
    /// nothing to race, and at that shortness the three attempts would be
    /// spent in 150ms — before a space change taking hundreds of
    /// milliseconds had finished, closing a panel that waiting would have
    /// given back. When the limit moves, the interval moves with it: their
    /// product stays at or under 2 seconds, and the interval stays at or
    /// above 200ms. Those bounds are about the defaults, not about what a
    /// test may pass in.
    static let defaultInterval: Duration = .milliseconds(500)

    /// How many takings-back one appearance may attempt before giving up.
    ///
    /// Provisional: what one space change costs in resign/become round trips
    /// was measured at one per loss, which leaves room, but a busier change
    /// could spend all three on an appearance that waiting would have given
    /// back.
    static let defaultLimit = 3

    private let interval: Duration
    private let limit: Int

    /// Read for the figure on a taking-back, and for nothing else.
    ///
    /// Passed in rather than read where it is used, because the figure's
    /// start is a look gone by rather than the moment of the finding: dating
    /// the loss from when it was noticed would read up to one interval low,
    /// and a figure that quietly understates is worse than none. The
    /// presenter hands in the clock it measures everything else with.
    private let now: @MainActor () -> ContinuousClock.Instant

    /// Whether the panel is still up, asked afresh after every wait and
    /// before every taking-back. The panel can go down while this is asleep,
    /// and asking for the keyboard afterwards would take back keys for a
    /// panel that is already gone — handing the next keystroke to a process
    /// the user has moved on from.
    private let isPanelUp: @MainActor () -> Bool

    private let isTakingKeys: @MainActor () -> Bool
    private let takeKeys: @MainActor () -> Bool

    /// Run once, on taking the keyboard back. Carries how long the panel went
    /// without it, counted from the previous look — the earliest the loss
    /// could have happened — so the figure errs towards overstating.
    private let onTakenBack: @MainActor (Duration) -> Void

    /// Run once, on the last attempt failing. The panel is taken down by
    /// whoever holds this, not here: what going down means belongs there.
    private let onGaveUp: @MainActor () -> Void

    private var task: Task<Void, Never>?

    /// How many takings-back this appearance has attempted and found wanting.
    /// A look finding the keyboard where it should be clears it: that is a
    /// loss that mended itself, and it owes no line.
    private var misses = 0

    /// When the previous look ran. The start counts as a look nobody could
    /// have found anything at: a panel just put up was taking keys a moment
    /// ago, when it was asked for outright.
    private var previousLook: ContinuousClock.Instant?

    /// Whether a look is under way, which is to say whether the panel now on
    /// screen has anything watching its key status.
    var isLooking: Bool {
        task != nil
    }

    init(
        interval: Duration = defaultInterval,
        limit: Int = defaultLimit,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        isPanelUp: @escaping @MainActor () -> Bool,
        isTakingKeys: @escaping @MainActor () -> Bool,
        takeKeys: @escaping @MainActor () -> Bool,
        onTakenBack: @escaping @MainActor (Duration) -> Void,
        onGaveUp: @escaping @MainActor () -> Void
    ) {
        self.interval = interval
        self.limit = limit
        self.now = now
        self.isPanelUp = isPanelUp
        self.isTakingKeys = isTakingKeys
        self.takeKeys = takeKeys
        self.onTakenBack = onTakenBack
        self.onGaveUp = onGaveUp
    }

    /// Looks until the attempts run out, the panel goes, or `stop()`.
    ///
    /// A successful taking-back resets the loss baseline and keeps looking:
    /// one recovery does not end the watch for this appearance, so a later
    /// loss is still found and answered.
    ///
    /// Stops whatever it started before, the way the window list's loop does:
    /// two loops watching one panel would take the keyboard back twice over,
    /// and the second taking-back would write a line for a loss the first
    /// had already mended.
    ///
    /// `knownGoodAt` is the last moment the keyboard was known good — the
    /// appearance's own clock read, handed in so this need not take one
    /// inside the span that read is measuring. The first loss found dates
    /// from there rather than from the finding, so the figure covers the
    /// whole of the keyboard-less while.
    func start(knownGoodAt: ContinuousClock.Instant) {
        stop()
        misses = 0
        previousLook = knownGoodAt
        // Read out here because the interval is wanted before there is a
        // `self` to read it from: the first thing the loop does is wait.
        let betweenLooks = interval
        // `weak` because the task is held here, so a strong capture would be
        // this object kept alive by its own loop. A watch nobody holds stops
        // looking at its next wait: whoever wants the looking done has to
        // keep hold of it — the presenter does, for as long as it lives.
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: betweenLooks)
                } catch {
                    // Cancellation is the only way the sleep fails, and it is
                    // one of the ways this is meant to end.
                    return
                }
                guard let self, isPanelUp() else { return }
                if isTakingKeys() {
                    misses = 0
                    previousLook = now()
                    continue
                }
                // Found wanting, so answered with one taking-back. Dated from
                // the previous look: the loss happened sometime since, and
                // the figure is meant to cover all of that sometime.
                let lostSince = previousLook ?? now()
                if takeKeys() {
                    onTakenBack(now() - lostSince)
                    misses = 0
                    previousLook = now()
                    continue
                }
                misses += 1
                previousLook = now()
                if misses >= limit {
                    onGaveUp()
                    return
                }
            }
        }
    }

    /// Ends the looking. A look that never happened reports nothing.
    ///
    /// Safe to call from inside either reporting, which is in fact one of the
    /// ordinary ways round: giving up takes the panel down, and taking the
    /// panel down is what stops the watch.
    func stop() {
        task?.cancel()
        task = nil
    }
}
