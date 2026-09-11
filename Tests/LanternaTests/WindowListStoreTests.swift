@testable import Lanterna
import Testing

/// Keeps the lines the store writes, so a test can read them back — including
/// reading that there were none.
@MainActor
private final class DiagnosticsLog {
    private(set) var lines: [String] = []

    func write(_ line: String) {
        lines.append(line)
    }
}

@MainActor
private func snapshot(count: Int) -> WindowListSnapshot {
    WindowListSnapshot(
        items: SampleWindows.make(count: count),
        applicationCount: count,
        gatheringDuration: .milliseconds(12),
        skipped: [],
        droppedWithoutID: 0
    )
}

/// Asks the store to refresh again from inside the pass it is already running.
///
/// That is the overlap the rule is about — a press asking for a list while the
/// loop is mid-pass — and arranging it this way makes it happen at a known
/// point rather than whenever two tasks happen to interleave.
@MainActor
private final class ReentrantGather {
    var store: WindowListStore?
    private(set) var callCount = 0
    private let answers: [WindowListSnapshot]

    init(answers: [WindowListSnapshot]) {
        self.answers = answers
    }

    func gather() async -> WindowListSnapshot {
        callCount += 1
        if callCount == 1, let store {
            await store.refresh()
        }
        return answers[min(callCount - 1, answers.count - 1)]
    }
}

/// A gather the test holds open, so a second caller can be made to arrive
/// while a pass is genuinely in flight rather than whenever two tasks happen
/// to interleave.
@MainActor
private final class HeldGather {
    private(set) var callCount = 0
    private let answer: WindowListSnapshot
    private var called: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    init(answer: WindowListSnapshot) {
        self.answer = answer
    }

    func gather() async -> WindowListSnapshot {
        callCount += 1
        called?.resume()
        called = nil
        await withCheckedContinuation { release = $0 }
        return answer
    }

    func waitUntilCalled() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { called = $0 }
    }

    func finish() {
        release?.resume()
        release = nil
    }
}

/// Counts the passes and lets a test wait until a given number of them have
/// begun, so how far round the loop has gone is settled by an event rather
/// than by how long a test was willing to wait for one.
///
/// Unlike `HeldGather` this does not hold the pass open. What these tests are
/// about is the loop coming back round, and a pass that never returned would
/// leave it nothing to come back round from.
@MainActor
private final class CountingGather {
    private(set) var callCount = 0
    private let answer: WindowListSnapshot
    private var reached: CheckedContinuation<Void, Never>?
    private var awaitedCount = 0

    init(answer: WindowListSnapshot) {
        self.answer = answer
    }

    func gather() async -> WindowListSnapshot {
        callCount += 1
        if callCount >= awaitedCount {
            reached?.resume()
            reached = nil
        }
        return answer
    }

    func waitUntilCalled(times: Int) async {
        guard callCount < times else { return }
        awaitedCount = times
        await withCheckedContinuation { reached = $0 }
    }
}

@MainActor
struct WindowListStoreTests {
    @Test func theFirstPassPutsAListInPlace() async {
        let store = WindowListStore(gather: { snapshot(count: 3) }, writeLine: { _ in })
        #expect(store.snapshot == nil)
        await store.refresh()
        #expect(store.snapshot?.items.count == 3)
    }

    @Test func aLaterPassReplacesTheList() async {
        var counts = [3, 7]
        let store = WindowListStore(
            gather: { snapshot(count: counts.removeFirst()) },
            writeLine: { _ in }
        )
        await store.refresh()
        await store.refresh()
        #expect(store.snapshot?.items.count == 7)
    }

    @Test func eachCompletedPassWritesItsSummary() async {
        let log = DiagnosticsLog()
        let store = WindowListStore(gather: { snapshot(count: 3) }, writeLine: log.write)
        await store.refresh()
        #expect(log.lines == ["listed 3 windows from 3 applications in 12.0 ms"])
    }

    /// A pass takes about a second when an application has stopped answering,
    /// and a second call in that window would have two reads running over the
    /// same accessibility connections.
    @Test func aRefreshArrivingDuringAPassIsRefused() async {
        let log = DiagnosticsLog()
        let fake = ReentrantGather(answers: [snapshot(count: 3)])
        let store = WindowListStore(gather: fake.gather, writeLine: log.write)
        fake.store = store

        await store.refresh()

        #expect(fake.callCount == 1)
        #expect(log.lines.first == "refresh skipped (previous pass still running)")
        #expect(log.lines.count == 2)
    }

    /// The refusal is for the duration of a pass, not for good.
    @Test func aRefreshAfterThePassHasFinishedRunsNormally() async {
        let fake = ReentrantGather(answers: [snapshot(count: 3), snapshot(count: 9)])
        let store = WindowListStore(gather: fake.gather, writeLine: { _ in })
        fake.store = store

        await store.refresh()
        await store.refresh()

        #expect(fake.callCount == 2)
        #expect(store.snapshot?.items.count == 9)
    }

    /// The fixture needs no gathering at all, so the list is there before the
    /// first press rather than after the first pass.
    @Test func aFixedListIsInPlaceBeforeAnythingIsGathered() {
        let store = WindowListStore(fixed: SampleWindows.make(count: 4))
        #expect(store.snapshot?.items.count == 4)
    }

    /// The panel asks whether a list is held in order to decide whether it may
    /// show at once, so a list that went missing again would put the delay
    /// back after it had already been paid for.
    @Test func aListThatArrivedIsNeverTakenAway() async {
        let store = WindowListStore(gather: { snapshot(count: 3) }, writeLine: { _ in })
        await store.refresh()
        store.stop()
        #expect(store.snapshot?.items.count == 3)
    }

    /// `stop()` ends the loop, not the store. The restart path leans on that:
    /// `start()` stops whatever it started before and then gathers from the
    /// loop it puts in its place, so a `stop()` that latched the store off
    /// would leave a freshly started loop producing nothing at all.
    @Test func aRefreshAfterTheLoopHasStoppedStillReplacesTheList() async {
        var counts = [3, 7]
        let store = WindowListStore(
            gather: { snapshot(count: counts.removeFirst()) },
            writeLine: { _ in }
        )
        await store.refresh()
        store.stop()
        await store.refresh()
        #expect(store.snapshot?.items.count == 7)
    }

    // MARK: - Asking for the list

    @Test func aHeldListIsHandedOverWithoutGatheringAgain() async {
        let fake = HeldGather(answer: snapshot(count: 5))
        let store = WindowListStore(gather: fake.gather, writeLine: { _ in })
        let pass = Task { await store.refresh() }
        await fake.waitUntilCalled()
        fake.finish()
        await pass.value

        let items = await store.listWhenGathered()
        #expect(items.count == 5)
        #expect(fake.callCount == 1)
    }

    @Test func askingBeforeAnyPassHasRunGathersOne() async {
        let store = WindowListStore(gather: { snapshot(count: 2) }, writeLine: { _ in })
        let items = await store.listWhenGathered()
        #expect(items.count == 2)
    }

    /// The press this is for lands just after launch, when the loop's first
    /// pass is almost certainly already running. Asking for a pass of its own
    /// would be refused and leave it with nothing, so what it waits for is the
    /// first list rather than its own attempt at one.
    @Test func askingDuringAPassWaitsForThatPassRatherThanStartingAnother() async {
        let fake = HeldGather(answer: snapshot(count: 5))
        let store = WindowListStore(gather: fake.gather, writeLine: { _ in })

        let pass = Task { await store.refresh() }
        await fake.waitUntilCalled()
        let waiting = Task { await store.listWhenGathered() }
        fake.finish()

        let items = await waiting.value
        await pass.value
        #expect(items.count == 5)
        #expect(fake.callCount == 1)
    }

    // MARK: - The loop

    /// Holding a list is worth something only if the list keeps up, and the
    /// loop is the whole of what makes it. A loop that went round once and
    /// stopped would leave the app showing the windows as they stood at launch
    /// for as long as it ran, and nothing in the log would look wrong: the one
    /// pass that did run wrote the same summary line a healthy pass writes.
    ///
    /// The time limit is not about slowness: these three are the only tests
    /// here that await a count the store is free to stop producing, so a loop
    /// reduced to a single pass would wait for ever rather than fail.
    @Test(.timeLimit(.minutes(1))) func theLoopKeepsGoingUntilItIsStopped() async {
        let fake = CountingGather(answer: snapshot(count: 3))
        let store = WindowListStore(gather: fake.gather, writeLine: { _ in })

        store.start(interval: .milliseconds(1))
        await fake.waitUntilCalled(times: 3)
        store.stop()

        #expect(fake.callCount >= 3)
    }

    /// The only wait on a real clock in this file, and it cannot be avoided:
    /// what is pinned here is that nothing further happens, and there is no
    /// event to await for something that must not occur. Fifty times the
    /// interval is long enough that a loop still going would have gone round
    /// many times over within it.
    @Test(.timeLimit(.minutes(1))) func stoppingEndsTheLoop() async {
        let fake = CountingGather(answer: snapshot(count: 3))
        let store = WindowListStore(gather: fake.gather, writeLine: { _ in })

        store.start(interval: .milliseconds(1))
        await fake.waitUntilCalled(times: 3)
        store.stop()
        let countWhenStopped = fake.callCount

        try? await Task.sleep(for: .milliseconds(50))

        #expect(fake.callCount == countWhenStopped)
    }

    /// Starting again ends what was started before, so two calls leave one
    /// loop rather than two. Stopping once is what shows it: a first loop that
    /// had survived would still be going after the second was stopped, because
    /// only the second one's handle was kept, and the count would climb on
    /// past the reading taken here.
    @Test(.timeLimit(.minutes(1))) func startingAgainReplacesTheLoopRatherThanAddingOne() async {
        let fake = CountingGather(answer: snapshot(count: 3))
        let store = WindowListStore(gather: fake.gather, writeLine: { _ in })

        store.start(interval: .milliseconds(1))
        store.start(interval: .milliseconds(1))
        await fake.waitUntilCalled(times: 3)
        store.stop()
        let countWhenStopped = fake.callCount

        try? await Task.sleep(for: .milliseconds(50))

        #expect(fake.callCount == countWhenStopped)
    }
}
