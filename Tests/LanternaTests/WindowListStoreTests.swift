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
        await store.refresh()
        #expect(store.snapshot != nil)
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
}
