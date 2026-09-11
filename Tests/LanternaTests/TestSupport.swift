@testable import Lanterna

/// Keeps the lines written to it, so a test can read them back — including
/// reading that there were none.
@MainActor
final class DiagnosticsLog {
    private(set) var lines: [String] = []

    func write(_ line: String) {
        lines.append(line)
    }
}

/// A gather the test holds open, so a caller can be made to arrive while a
/// pass is genuinely in flight rather than whenever two tasks happen to
/// interleave.
///
/// Here rather than in one of the suites because both want it for the same
/// reason. The store's tests hold a pass open to put a second caller inside
/// it; the presenter's hold one open to put a press inside it, which is the
/// moment just after launch and the only time a press finds no list to take.
/// One double, because it is one situation looked at from two sides.
@MainActor
final class HeldGather {
    private(set) var callCount = 0
    private let answer: WindowListSnapshot
    private var called: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    init(answer: WindowListSnapshot) {
        self.answer = answer
    }

    /// Most callers care only how many rows came back, so this fills the rest
    /// in. The gathering duration is the one the rest of the suite uses;
    /// nothing asserts on it from here, and one figure throughout reads better
    /// than two that differ for no reason.
    convenience init(entryCount: Int) {
        self.init(
            answer: WindowListSnapshot(
                items: SampleWindows.make(count: entryCount),
                applicationCount: entryCount,
                gatheringDuration: .milliseconds(12),
                skipped: [],
                droppedWithoutID: 0
            )
        )
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
