import Darwin
@testable import Lanterna

/// Arbitrary and distinct. Nothing depends on the values, only on whether the
/// process that came forward is the one the presenter was told to ignore.
let ownProcess: pid_t = 1234
let otherProcess: pid_t = 5678

/// Stands in for the panel. A real one needs a window server. A screen would
/// show that a panel appeared, but not which list it was given, nor that it
/// appeared once rather than twice, and those are what this records.
@MainActor
final class FakeSurface: SwitcherSurface {
    private(set) var presentedLists: [[WindowItem]] = []
    private(set) var dismissCount = 0
    var isPresented = false

    /// Run inside `dismiss()`, before it returns.
    ///
    /// Lets a test make the panel's disappearance cost something it can see.
    /// A stepping clock gives every reading the same weight, so a figure that
    /// is meant to span the dismissal and one that stops just short of it come
    /// out identical — one tick either way. Charging the dismissal its own tick
    /// is what separates them.
    var onDismiss: (@MainActor () -> Void)?

    func present(windows: [WindowItem]) {
        presentedLists.append(windows)
        isPresented = true
    }

    func dismiss() {
        dismissCount += 1
        isPresented = false
        onDismiss?()
    }
}

/// Reads a fixed amount later each time it is asked, so the figure in the
/// measurement line is decided by the test and not by how busy the machine is.
@MainActor
final class SteppingClock {
    private let step: Duration
    private var current = ContinuousClock.now

    init(step: Duration) {
        self.step = step
    }

    func read() -> ContinuousClock.Instant {
        defer { current = current.advanced(by: step) }
        return current
    }
}

/// Lets the hand-offs between tasks on the main actor run out.
///
/// Not a timeout: nothing here waits on the clock or on I/O. Once the gather
/// is released, a fixed and small number of continuations have to resume in
/// turn before the presenter has either shown the panel or decided not to,
/// and this is how many turns that takes with room to spare.
func settle() async {
    for _ in 0 ..< 10 {
        await Task.yield()
    }
}

/// A presenter and the fakes behind it, so a test can drive the one and then
/// read the others.
///
/// Here rather than in the presenter's own suite for the reason
/// `DiagnosticsLog` and `HeldGather` are: more than one suite looks at the
/// presenter, each from its own side. Two copies would be two fakes growing
/// apart, and a change to `SwitcherSurface` would then be made in one of them.
@MainActor
struct Fixture {
    let surface: FakeSurface
    let log: DiagnosticsLog
    let windows: [WindowItem]
    let presenter: PanelPresenter
    /// The very clock the presenter reads, so a test can charge one operation
    /// a tick and then ask whether the figure counted it.
    let clock: SteppingClock

    /// A store that already holds a list, which is every press but the first
    /// one after launch.
    init(entryCount: Int = 12, step: Duration = .microseconds(4800)) {
        let windows = SampleWindows.make(count: entryCount)
        self.init(store: WindowListStore(fixed: windows), windows: windows, step: step)
    }

    init(
        store: WindowListStore,
        windows: [WindowItem] = [],
        step: Duration = .microseconds(4800)
    ) {
        let surface = FakeSurface()
        let log = DiagnosticsLog()
        let clock = SteppingClock(step: step)
        presenter = PanelPresenter(
            surface: surface,
            store: store,
            ownProcessIdentifier: ownProcess,
            now: clock.read,
            writeLine: log.write
        )
        self.surface = surface
        self.log = log
        self.windows = windows
        self.clock = clock
    }
}

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
