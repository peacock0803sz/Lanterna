/// The one owner of the window list.
///
/// The list used to be gathered by the press that needed it, which made every
/// press wait for every application to answer. Here it is gathered on a loop
/// instead and held, so a press takes what is already there. Nothing else
/// keeps a list: the panel is handed an array when it is shown and does not
/// look back at this, which is what makes "the rows do not change while the
/// panel is up" a property of the structure rather than a rule to remember.
@MainActor
final class WindowListStore {
    /// How long to wait between passes.
    ///
    /// A change can arrive just after a pass has read past it, so it waits out
    /// the rest of that pass, then the interval, then the pass that finds it.
    /// A cold parallel pass measured 71 ms, which puts the ordinary case at
    /// 1.642 s. The worst case is far longer and no interval bounds it:
    /// `ReadBudget` gives each application a second, and the last message a
    /// wedged one is sent may run a further messaging timeout past that, so a
    /// single application that has stopped answering can stretch a pass to
    /// about two seconds on its own. This number is chosen for the ordinary
    /// case. One second would leave the list fresher at the price of half
    /// again as many log lines, because every pass writes one.
    static let defaultInterval: Duration = .milliseconds(1500)

    /// Whether the list is refreshed: false for the fixture and the
    /// missing-permission empty list, which never change. The Space
    /// observer is only registered for a live list.
    let isLive: Bool

    /// What the last completed pass found, or `nil` if none has completed.
    ///
    /// Only ever `nil` at the very start. A press landing in that window is
    /// the one case that has to gather its own list.
    private(set) var snapshot: WindowListSnapshot?

    /// Whether a pass is in flight, which is what a second caller is turned
    /// away on. Event-driven callers use `refreshEventually` instead and
    /// queue behind it.
    private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?
    private var refreshAgain = false
    /// Callers that arrived while a pass was running and wait until a pass
    /// completes with nothing queued, which is when the list is freshest.
    /// Released by `stop()` too: the loop is dead then, so what is held is
    /// all there will ever be.
    private var waitingForFresh: [CheckedContinuation<Void, Never>] = []
    /// Callers parked until the first pass produces something.
    private var waitingForFirstList: [CheckedContinuation<Void, Never>] = []
    private let gather: @MainActor () async -> WindowListSnapshot
    private let writeLine: @MainActor (String) -> Void

    init(
        gather: @escaping @MainActor () async -> WindowListSnapshot = {
            await WindowEnumerator().enumerateRegularApplicationsOffMainThread()
        },
        writeLine: @escaping @MainActor (String) -> Void = Diagnostics.writeLine
    ) {
        self.gather = gather
        self.writeLine = writeLine
        isLive = true
    }

    /// A list that stands in for the real one and never changes, which is what
    /// `--sample-count` asks for.
    ///
    /// The list is in place from here, so nothing ever asks for a pass, and no
    /// loop is started for it either. The gathering below therefore only has
    /// to be something; it is the same list again so that a call which should
    /// not happen would at least not change what is held.
    init(
        fixed items: [WindowItem],
        writeLine: @escaping @MainActor (String) -> Void = Diagnostics.writeLine
    ) {
        let fixed = WindowListSnapshot(
            items: items,
            // No pass looked at any application, so this counts the ones the
            // fixture names. Nothing reads it: a fixture is never summarised,
            // because the line that would say so is written by a pass.
            applicationCount: Set(items.map(\.appName)).count,
            gatheringDuration: .zero,
            skipped: [],
            droppedWithoutID: 0,
            gatheredAt: .now
        )
        snapshot = fixed
        gather = { fixed }
        self.writeLine = writeLine
        isLive = false
    }

    /// Runs one pass and replaces the list with what it found.
    ///
    /// A caller arriving while a pass is in flight is turned away rather than
    /// queued behind it. An application that has stopped answering makes a
    /// pass take about a second, and a press landing in that second would
    /// otherwise start a second read over the same connections; waiting for
    /// the one already running is no better, because the press would then wait
    /// the second out. The list it wanted is on its way regardless.
    func refresh() async {
        guard !isRefreshing else {
            writeLine("refresh skipped (previous pass still running)")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let gathered = await gather()
        snapshot = gathered
        writeLine(gathered.summaryLine)

        let waiting = waitingForFirstList
        waitingForFirstList = []
        for continuation in waiting {
            continuation.resume()
        }
        // A pass ending with nothing queued leaves the freshest list:
        // release the event callers waiting for exactly that. No awaits
        // stand between the flag read and the resumes, so a request landing
        // in between cannot miss its pass.
        if !refreshAgain {
            let waitingForFresh = waitingForFresh
            self.waitingForFresh = []
            for continuation in waitingForFresh {
                continuation.resume()
            }
        }
    }

    /// Requests a pass and does not return until the list is fresh again.
    ///
    /// Runs one now unless one is already running, in which case exactly one
    /// more pass follows it and this waits for that pass. Event-driven
    /// callers (a Space switch) must neither lose their update to the
    /// polling loop's in-flight pass nor return before it lands (#44).
    /// Concurrent requests coalesce: any number of calls arriving during one
    /// pass produce a single following pass that releases them all. The
    /// polling loop and the first-list path go through here too, which is
    /// what drains a flag set mid-pass; the loop never overlaps itself
    /// because it awaits each pass. Stopping releases waiters early with
    /// whatever is held, which is the one exception to waiting for fresh.
    func refreshEventually() async {
        if isRefreshing {
            refreshAgain = true
            await withCheckedContinuation { waitingForFresh.append($0) }
            return
        }
        await refresh()
        while refreshAgain {
            refreshAgain = false
            await refresh()
        }
    }

    /// The list, waiting for a pass to finish if none has yet.
    ///
    /// Only a press arriving before the loop's first pass completes can find
    /// nothing held, and it almost always finds that pass already running,
    /// because the loop starts before the hotkeys are claimed. Such a press
    /// parks until a pass produces a list, whichever pass that is, rather than
    /// asking for one of its own: `refresh()` would refuse to start a second
    /// and hand it back the same nothing. A pass is started here only when
    /// none is running at all, which the launch order makes unlikely but
    /// nothing here relies on. Empty only if a pass genuinely found no
    /// windows.
    func listWhenGathered() async -> [WindowItem] {
        if snapshot == nil {
            if isRefreshing {
                await withCheckedContinuation { waitingForFirstList.append($0) }
            } else {
                // Through `refreshEventually` so an event flag set mid-pass
                // is drained rather than orphaned: every production pass
                // goes through the one draining path.
                await refreshEventually()
            }
        }
        return snapshot?.items ?? []
    }

    /// Keeps the list current until `stop()`.
    ///
    /// The first pass is neither delayed nor waited for. Starting it before
    /// the hotkeys are claimed is what makes it likely that the first press
    /// already has a list to take.
    func start(interval: Duration = defaultInterval) {
        stop()
        // `weak` because the task is held here: a strong capture would be the
        // store keeping itself alive through its own loop.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                // Through `refreshEventually` rather than `refresh` so that
                // an event flag set mid-pass is drained by the following
                // pass instead of being orphaned until the next event.
                await self?.refreshEventually()
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    // Cancellation is the only way the sleep fails, and it is
                    // how the loop is meant to end.
                    return
                }
            }
        }
    }

    /// Ends the loop. The list already held stays held. Drops a queued
    /// event pass and releases its waiters: with no loop left to drain it,
    /// waiting would never end.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshAgain = false
        let waitingForFresh = waitingForFresh
        self.waitingForFresh = []
        for continuation in waitingForFresh {
            continuation.resume()
        }
    }
}
