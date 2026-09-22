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
    /// Every call in the order it came, so a test can say that keys were
    /// asked for after the panel went up and not before.
    enum Call: Equatable {
        case present(selecting: WindowItem.Identifier?)
        case takeKeys
        case showSelection(WindowItem.Identifier?)
        case dismiss
    }

    private(set) var calls: [Call] = []
    private(set) var presentedLists: [[WindowItem]] = []
    /// The row each appearance was told to draw as chosen.
    private(set) var presentedSelections: [WindowItem.Identifier?] = []
    /// Every row the panel was told to redraw as chosen, in order. The count
    /// matters as much as the values: redrawing a selection must not go
    /// through `present`, and a test can only tell those apart by which
    /// record grew.
    private(set) var shownSelections: [WindowItem.Identifier?] = []
    private(set) var takeKeysCount = 0
    private(set) var dismissCount = 0
    var isPresented = false

    /// Whether presses are reaching the panel.
    ///
    /// Settable, because this is the one seam through which a test stages
    /// key status being lost while a panel is up. There is no second way in:
    /// a lost-and-regained answer that could be injected somewhere else
    /// would be a second record of one thing.
    var isTakingKeys = false

    /// What `takeKeys()` answers.
    ///
    /// Separate from the flag above, and it has to be. Implementing the ask
    /// as a read of `isTakingKeys` would answer no for ever once a test had
    /// staged a loss, so no test could stage a recovery; answering yes always
    /// would make three failures in a row impossible to stage. Both are cases
    /// the panel has to be held to.
    var takeKeysSucceeds = true

    /// Run inside `dismiss()`, before it returns.
    ///
    /// Lets a test make the panel's disappearance cost something it can see.
    /// A stepping clock gives every reading the same weight, so a figure that
    /// is meant to span the dismissal and one that stops just short of it come
    /// out identical — one tick either way. Charging the dismissal its own tick
    /// is what separates them.
    var onDismiss: (@MainActor () -> Void)?

    func present(windows: [WindowItem], selecting: WindowItem.Identifier?) {
        presentedLists.append(windows)
        presentedSelections.append(selecting)
        calls.append(.present(selecting: selecting))
        isPresented = true
    }

    func takeKeys() -> Bool {
        takeKeysCount += 1
        calls.append(.takeKeys)
        isTakingKeys = takeKeysSucceeds
        return takeKeysSucceeds
    }

    func showSelection(_ id: WindowItem.Identifier?) {
        shownSelections.append(id)
        calls.append(.showSelection(id))
    }

    func dismiss() {
        dismissCount += 1
        calls.append(.dismiss)
        isPresented = false
        // A panel ordered off the screen is no longer taking anything, and a
        // stand-in that went on saying it was would let a test pass that the
        // real one could not.
        isTakingKeys = false
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

/// Whether a monitor is running, as the presenter asks it.
///
/// A box rather than a flag passed once, because the whole point of asking
/// per press is that the answer can change between two of them. A test that
/// could only set it at construction could not stage a tap dying while the
/// panel is up.
@MainActor
final class MonitorLiveness {
    var isRunning: Bool

    init(isRunning: Bool) {
        self.isRunning = isRunning
    }
}

/// Whether Command is down, as the presenter asks it.
///
/// A box for the same reason `MonitorLiveness` is one, and here it is the only
/// way at all: a test process cannot put a real Command key down, so staging a
/// press that arrives after its own release means saying so between presses.
///
/// It counts the asking as well, and lets a test wait for a given number of
/// asks. The presenter looks again on a timer for as long as the panel is up,
/// and what a test needs to know is that a look has happened — sleeping a
/// fixed span instead would be waiting on how busy the machine is rather than
/// on the thing that was meant to occur.
@MainActor
final class CommandHold {
    var isHeld: Bool
    private(set) var askCount = 0
    private var reached: CheckedContinuation<Void, Never>?
    private var awaitedCount = 0

    init(isHeld: Bool) {
        self.isHeld = isHeld
    }

    func read() -> Bool {
        askCount += 1
        if askCount >= awaitedCount {
            reached?.resume()
            reached = nil
        }
        return isHeld
    }

    func waitUntilAsked(times: Int) async {
        guard askCount < times else { return }
        awaitedCount = times
        await withCheckedContinuation { reached = $0 }
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
    /// The very box the presenter asks, so a test can switch the monitor off
    /// between one press and the next.
    let monitorLiveness: MonitorLiveness
    /// The very box the presenter asks, so a test can let Command go before
    /// the press that was made with it arrives.
    let commandHold: CommandHold
    /// What commits take. Silent unless a test scripts it, so the suites
    /// written before anything was taken keep reading the same lines.
    let switcher: FakeWindowSwitcher

    /// A store that already holds a list, which is every press but the first
    /// one after launch.
    init(
        entryCount: Int = 12,
        step: Duration = .microseconds(4800),
        closesOnCommandRelease: Bool = false,
        commandIsHeld: Bool = true,
        commandWatchInterval: Duration = .milliseconds(1),
        keyStatusWatchInterval: Duration = .milliseconds(1),
        switcher: FakeWindowSwitcher = FakeWindowSwitcher()
    ) {
        let windows = SampleWindows.make(count: entryCount)
        self.init(
            store: WindowListStore(fixed: windows),
            windows: windows,
            step: step,
            closesOnCommandRelease: closesOnCommandRelease,
            commandIsHeld: commandIsHeld,
            commandWatchInterval: commandWatchInterval,
            keyStatusWatchInterval: keyStatusWatchInterval,
            switcher: switcher
        )
    }

    init(
        store: WindowListStore,
        windows: [WindowItem] = [],
        step: Duration = .microseconds(4800),
        closesOnCommandRelease: Bool = false,
        commandIsHeld: Bool = true,
        commandWatchInterval: Duration = .milliseconds(1),
        keyStatusWatchInterval: Duration = .milliseconds(1),
        switcher: FakeWindowSwitcher = FakeWindowSwitcher()
    ) {
        let surface = FakeSurface()
        let log = DiagnosticsLog()
        let clock = SteppingClock(step: step)
        let monitorLiveness = MonitorLiveness(isRunning: closesOnCommandRelease)
        // Held by default, because that is what a press made with the key
        // down means, and every test written before the presenter could ask
        // was written for that press.
        let commandHold = CommandHold(isHeld: commandIsHeld)
        presenter = PanelPresenter(
            surface: surface,
            store: store,
            ownProcessIdentifier: ownProcess,
            now: clock.read,
            writeLine: log.write,
            closesOnCommandRelease: { [monitorLiveness] in monitorLiveness.isRunning },
            commandIsHeld: { [commandHold] in commandHold.read() },
            // A real fiftieth of a second per look would be paid over again by
            // every test that waits for one. The store's loop tests shorten
            // their interval for the same reason.
            commandWatchInterval: commandWatchInterval,
            // Half a second per look would put every loss past any test's
            // patience. Shortened for the same reason as the watch above.
            keyStatusWatchInterval: keyStatusWatchInterval,
            switcher: switcher
        )
        self.surface = surface
        self.log = log
        self.windows = windows
        self.clock = clock
        self.monitorLiveness = monitorLiveness
        self.commandHold = commandHold
        self.switcher = switcher
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

/// A monitor and the fake tap behind it, so a test can drive the one and read
/// the other.
///
/// Named for what it holds rather than just `Fixture`: the presenter's own
/// fixture is shared from this file too, and two things called the same in one
/// module would read as the same thing.
@MainActor
struct MonitorFixture {
    let tap: FakeEventTap
    let log: DiagnosticsLog
    let monitor: ModifierKeyMonitor
    /// How many times the monitor passed a release on to its owner.
    let releases: Counter

    @MainActor
    final class Counter {
        private(set) var count = 0
        func increment() {
            count += 1
        }
    }

    /// The default interval is long enough that no loop started here ever
    /// comes round during a test: every case that wants a check drives it by
    /// hand. The cases about the loop itself shorten it and wait out a turn or
    /// several, which is the only way to tell a timer that exists from one
    /// that does not — four of them in `ModifierKeyMonitorRecoveryTests`, plus
    /// the yardstick loop that file's `waitOutATurn()` starts to measure a
    /// turn against.
    init(
        startSucceeds: Bool = true,
        hasPermission: Bool = true,
        healthCheckInterval: Duration = .seconds(60),
        step: Duration = .microseconds(4800)
    ) {
        let tap = FakeEventTap()
        tap.startSucceeds = startSucceeds
        tap.hasPermission = hasPermission
        let log = DiagnosticsLog()
        let releases = Counter()
        // Built here and not kept. What a monitor test wants of the clock is
        // that it tick by a known amount, which `step` settles at the call —
        // unlike the presenter's fixture, nothing here reads the clock back,
        // and a property nobody asks anything of is one more thing to keep
        // true.
        let clock = SteppingClock(step: step)
        monitor = ModifierKeyMonitor(
            tap: tap,
            healthCheckInterval: healthCheckInterval,
            onCommandRelease: { releases.increment() },
            now: clock.read,
            writeLine: log.write
        )
        self.tap = tap
        self.log = log
        self.releases = releases
    }
}
