@testable import Lanterna
import Testing

@MainActor
private func eventSnapshot(count: Int) -> WindowListSnapshot {
    WindowListSnapshot(
        items: SampleWindows.make(count: count),
        applicationCount: count,
        gatheringDuration: .milliseconds(12),
        skipped: [],
        droppedWithoutID: 0,
        gatheredAt: .now
    )
}

/// Event-driven refreshes behind an in-flight pass (#44).
///
/// Split from WindowListStoreTests when that file outgrew the length limit.
/// Builders stay file-local, the way the sibling suites keep them.
@MainActor
struct WindowListStoreEventRefreshTests {
    /// A Space switch must neither lose its update to the polling loop's
    /// in-flight pass nor return before it lands (#44). A request arriving
    /// mid-pass runs exactly one more pass after it and waits for that pass.
    /// Awaiting the event call itself is the freshness assertion: it returns
    /// only after the second answer replaced the list, with no "skipped"
    /// line on the way.
    @Test(.timeLimit(.minutes(1))) func anEventRefreshDuringAPassWaitsForTheFollowingPass() async {
        let first = eventSnapshot(count: 3)
        let second = eventSnapshot(count: 7)
        let log = DiagnosticsLog()
        var callCount = 0
        var firstStarted: CheckedContinuation<Void, Never>?
        var secondStarted: CheckedContinuation<Void, Never>?
        var release: CheckedContinuation<Void, Never>?
        let store = WindowListStore(
            gather: {
                callCount += 1
                if callCount == 1 {
                    firstStarted?.resume()
                    firstStarted = nil
                } else {
                    secondStarted?.resume()
                    secondStarted = nil
                }
                let answer = callCount == 1 ? first : second
                await withCheckedContinuation { release = $0 }
                return answer
            },
            writeLine: log.write
        )

        let pass = Task { await store.refreshEventually() }
        if callCount == 0 {
            await withCheckedContinuation { firstStarted = $0 }
        }
        let event = Task { await store.refreshEventually() }
        await settle()
        release?.resume()
        release = nil
        if callCount < 2 {
            await withCheckedContinuation { secondStarted = $0 }
        }
        release?.resume()
        release = nil
        await event.value
        await pass.value

        #expect(callCount == 2)
        #expect(store.snapshot?.items.count == 7)
        #expect(!log.lines.contains("refresh skipped (previous pass still running)"))
    }

    /// A request arriving during the following pass queues a third one: the
    /// drain keeps draining until nothing is queued. Rapid consecutive Space
    /// switches land exactly here.
    @Test(.timeLimit(.minutes(1))) func aRequestDuringTheFollowingPassQueuesAThirdPass() async {
        let answers = [eventSnapshot(count: 3), eventSnapshot(count: 7), eventSnapshot(count: 9)]
        let log = DiagnosticsLog()
        var callCount = 0
        var started: CheckedContinuation<Void, Never>?
        var release: CheckedContinuation<Void, Never>?
        let store = WindowListStore(
            gather: {
                callCount += 1
                started?.resume()
                started = nil
                let answer = answers[min(callCount - 1, answers.count - 1)]
                await withCheckedContinuation { release = $0 }
                return answer
            },
            writeLine: log.write
        )

        let pass = Task { await store.refreshEventually() }
        if callCount == 0 {
            await withCheckedContinuation { started = $0 }
        }
        let firstEvent = Task { await store.refreshEventually() }
        await settle()
        release?.resume()
        release = nil
        if callCount < 2 {
            await withCheckedContinuation { started = $0 }
        }
        let secondEvent = Task { await store.refreshEventually() }
        await settle()
        release?.resume()
        release = nil
        if callCount < 3 {
            await withCheckedContinuation { started = $0 }
        }
        release?.resume()
        release = nil
        await firstEvent.value
        await secondEvent.value
        await pass.value

        #expect(callCount == 3)
        #expect(store.snapshot?.items.count == 9)
        #expect(!log.lines.contains("refresh skipped (previous pass still running)"))
    }

    /// A pass started by the first-list path drains an event flag set
    /// mid-pass the same way the loop does: every production pass goes
    /// through the one draining path, so no waiter is left for a drainer
    /// that never comes (#44). The first press waits inside its own pass
    /// and comes back holding the following one.
    @Test(.timeLimit(.minutes(1))) func anEventDuringAFirstListPassIsReleasedFresh() async {
        let answers = [eventSnapshot(count: 3), eventSnapshot(count: 7)]
        let log = DiagnosticsLog()
        var callCount = 0
        var started: CheckedContinuation<Void, Never>?
        var release: CheckedContinuation<Void, Never>?
        let store = WindowListStore(
            gather: {
                callCount += 1
                started?.resume()
                started = nil
                let answer = answers[min(callCount - 1, answers.count - 1)]
                await withCheckedContinuation { release = $0 }
                return answer
            },
            writeLine: log.write
        )

        let firstList = Task { await store.listWhenGathered() }
        if callCount == 0 {
            await withCheckedContinuation { started = $0 }
        }
        let event = Task { await store.refreshEventually() }
        await settle()
        release?.resume()
        release = nil
        if callCount < 2 {
            await withCheckedContinuation { started = $0 }
        }
        release?.resume()
        release = nil
        let items = await firstList.value
        await event.value

        #expect(callCount == 2)
        #expect(items.count == 7)
        #expect(store.snapshot?.items.count == 7)
        #expect(!log.lines.contains("refresh skipped (previous pass still running)"))
    }

    /// Stopping releases a parked event refresh instead of stranding it:
    /// with no loop left to drain the flag, waiting would never end. The
    /// waiter comes back holding whatever was held, which documents the one
    /// exception to waiting for fresh.
    @Test(.timeLimit(.minutes(1))) func stoppingReleasesAParkedEventRefresh() async {
        let fake = HeldGather(answer: eventSnapshot(count: 5))
        let store = WindowListStore(gather: fake.gather, writeLine: { _ in })

        let pass = Task { await store.refreshEventually() }
        await fake.waitUntilCalled()
        let event = Task { await store.refreshEventually() }
        await settle()
        store.stop()
        await event.value
        #expect(store.snapshot == nil)
        #expect(fake.callCount == 1)
        fake.finish()
        await pass.value
    }

    /// Concurrent requests coalesce: two calls arriving during one pass
    /// still produce only a single following pass, which releases them both.
    @Test(.timeLimit(.minutes(1))) func twoEventRefreshesDuringOnePassProduceOnlyOneExtraPass() async {
        let fake = HeldGather(answer: eventSnapshot(count: 5))
        let store = WindowListStore(gather: fake.gather, writeLine: { _ in })

        let pass = Task { await store.refreshEventually() }
        await fake.waitUntilCalled()
        let first = Task { await store.refreshEventually() }
        let second = Task { await store.refreshEventually() }
        await settle()
        fake.finish()
        while fake.callCount < 2 {
            await Task.yield()
        }
        fake.finish()
        await first.value
        await second.value
        await pass.value

        #expect(fake.callCount == 2)
    }
}
