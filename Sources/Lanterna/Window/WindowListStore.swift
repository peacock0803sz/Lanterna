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
    /// The list may be at most two seconds out of date, and the worst a change
    /// can do is arrive just after a pass has read past it: one interval plus
    /// one pass. A cold parallel pass measured 71 ms, so 1.5 s + 71 ms is
    /// 1.571 s and fits. Two seconds would not — 2.071 s is already over. One
    /// second would fit more comfortably but doubles the log, because every
    /// pass writes a line.
    static let defaultInterval: Duration = .milliseconds(1500)

    /// What the last completed pass found, or `nil` if none has completed.
    ///
    /// Only ever `nil` at the very start. A press landing in that window is
    /// the one case that has to gather its own list.
    private(set) var snapshot: WindowListSnapshot?

    /// Whether a pass is in flight, which is what a second caller is turned
    /// away on.
    private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?
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
            droppedWithoutID: 0
        )
        snapshot = fixed
        gather = { fixed }
        self.writeLine = writeLine
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
    }

    /// The list, waiting for a pass to finish if none has yet.
    ///
    /// Only the first press after launch can find nothing held, and it is
    /// almost certain to find a pass already running, because the loop starts
    /// before the hotkeys are claimed. Such a press cannot ask for a pass of
    /// its own — `refresh()` would refuse to start a second and hand it back
    /// the same nothing — so what it waits for is the first list, whichever
    /// pass produces it. Empty only if a pass genuinely found no windows.
    func listWhenGathered() async -> [WindowItem] {
        if snapshot == nil {
            if isRefreshing {
                await withCheckedContinuation { waitingForFirstList.append($0) }
            } else {
                await refresh()
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
                await self?.refresh()
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

    /// Ends the loop. The list already held stays held.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
