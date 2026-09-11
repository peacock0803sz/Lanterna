import Darwin
@testable import Lanterna
import Testing

/// Arbitrary and distinct. Nothing depends on the values, only on whether the
/// process that came forward is the one the presenter was told to ignore.
private let ownProcess: pid_t = 1234
private let otherProcess: pid_t = 5678

/// Stands in for the panel. A real one needs a window server. A screen would
/// show that a panel appeared, but not which list it was given, nor that it
/// appeared once rather than twice, and those are what this records.
@MainActor
private final class FakeSurface: SwitcherSurface {
    private(set) var presentedLists: [[WindowItem]] = []
    private(set) var dismissCount = 0
    var isPresented = false

    func present(windows: [WindowItem]) {
        presentedLists.append(windows)
        isPresented = true
    }

    func dismiss() {
        dismissCount += 1
        isPresented = false
    }
}

/// Reads a fixed amount later each time it is asked, so the figure in the
/// measurement line is decided by the test and not by how busy the machine is.
@MainActor
private final class SteppingClock {
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
private func settle() async {
    for _ in 0 ..< 10 {
        await Task.yield()
    }
}

/// A presenter and the fakes behind it, so a test can drive the one and then
/// read the others.
@MainActor
private struct Fixture {
    let surface: FakeSurface
    let log: DiagnosticsLog
    let windows: [WindowItem]
    let presenter: PanelPresenter

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
    }
}

@MainActor
struct PanelPresenterTests {
    @Test func aPressPutsThePanelUpOnceWithTheListItWasGiven() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.presentedLists.first?.map(\.id) == fixture.windows.map(\.id))
        #expect(fixture.surface.isPresented)
    }

    /// The reading spans the press, so a clock that steps once per read gives
    /// the whole line a value the test chose.
    /// No note about gathering: the list was already held, which is what the
    /// note's absence is there to say.
    @Test func eachPressIsAccountedForByExactlyOneLine() {
        let fixture = Fixture(step: .microseconds(4800))
        fixture.presenter.handleHotkey(.forward, deliveryDelay: .microseconds(1900))
        #expect(
            fixture.log.lines == ["panel shown 4.8 ms after Cmd+Tab (12 entries); delivery 1.9 ms"]
        )
    }

    @Test func theReverseCombinationTakesTheSamePath() {
        let fixture = Fixture(entryCount: 3)
        fixture.presenter.handleHotkey(.reverse, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.presentedLists.first?.count == 3)
        #expect(fixture.log.lines == ["panel shown 4.8 ms after Shift+Cmd+Tab (3 entries)"])
    }

    @Test func aPressWhileThePanelIsUpTakesItDown() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.dismissCount == 1)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(!fixture.surface.isPresented)
    }

    /// Either combination closes it, and the line names the one that did, so a
    /// log read afterwards says which key the panel answered.
    @Test(arguments: [
        (HotkeyCombination.forward, "Cmd+Tab"),
        (.reverse, "Shift+Cmd+Tab"),
    ])
    func theKeyThatTookThePanelDownIsWrittenDown(
        combination: HotkeyCombination,
        name: String
    ) {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleHotkey(combination, deliveryDelay: nil)
        #expect(fixture.log.lines.count == 2)
        #expect(fixture.log.lines.last == "panel hidden (\(name))")
    }

    @Test func aPressAfterThatPutsThePanelBackUp() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.count == 2)
        #expect(fixture.surface.dismissCount == 1)
        #expect(fixture.surface.isPresented)
    }

    /// Twenty presses rather than two. A toggle off by one still looks right
    /// over a single round trip, and only stacks up over many.
    @Test func pressesAlternateWithoutEverStackingASecondPanel() {
        let fixture = Fixture()
        for _ in 0 ..< 20 {
            fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        }
        #expect(fixture.surface.presentedLists.count == 10)
        #expect(fixture.surface.dismissCount == 10)
        #expect(!fixture.surface.isPresented)
    }

    @Test func anotherApplicationComingForwardTakesThePanelDown() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleActivation(of: otherProcess)
        #expect(fixture.surface.dismissCount == 1)
        #expect(!fixture.surface.isPresented)
        #expect(fixture.log.lines.last == "panel hidden (frontmost application changed)")
    }

    /// Nothing else about the panel would say it had closed, so a press that
    /// followed would put a second one up if this were the wrong process.
    @Test func thisProcessComingForwardLeavesThePanelUp() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        let linesSoFar = fixture.log.lines
        fixture.presenter.handleActivation(of: ownProcess)
        #expect(fixture.surface.dismissCount == 0)
        #expect(fixture.surface.isPresented)
        #expect(fixture.log.lines == linesSoFar)
    }

    /// Every application coming forward is announced, panel or no panel, so
    /// the quiet case is the common one and has to stay quiet.
    @Test(arguments: [ownProcess, otherProcess])
    func anActivationWithNoPanelUpChangesNothing(processIdentifier: pid_t) {
        let fixture = Fixture()
        fixture.presenter.handleActivation(of: processIdentifier)
        #expect(fixture.surface.presentedLists.isEmpty)
        #expect(fixture.surface.dismissCount == 0)
        #expect(fixture.log.lines.isEmpty)
    }
}

/// The window between launch and the first completed pass, which is the only
/// time a press finds no list to take.
@MainActor
struct PanelPresenterWaitingForAListTests {
    private func storeHoldingNothing(_ fake: HeldGather) -> WindowListStore {
        WindowListStore(gather: fake.gather, writeLine: { _ in })
    }

    /// A press that finds a list takes it as it stands. Nothing is gathered
    /// for it, which is the whole of what holding a list buys.
    @Test func aPressWithAListHeldGathersNothing() async {
        let fake = HeldGather(entryCount: 4)
        let store = storeHoldingNothing(fake)
        let pass = Task { await store.refresh() }
        await fake.waitUntilCalled()
        fake.finish()
        await pass.value

        let fixture = Fixture(store: store)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fake.callCount == 1)
        #expect(fixture.surface.presentedLists.first?.count == 4)
        #expect(fixture.log.lines == ["panel shown 4.8 ms after Cmd+Tab (4 entries)"])
    }

    /// With nothing held the press has to wait, and the line says so: the
    /// figure then describes the gathering far more than it describes the
    /// panel, and reading it as a panel timing would be reading it wrong.
    @Test func aPressWithNoListHeldWaitsAndTheLineSaysSo() async {
        let fake = HeldGather(entryCount: 4)
        let fixture = Fixture(store: storeHoldingNothing(fake))

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.isEmpty)

        await fake.waitUntilCalled()
        fake.finish()
        await settle()

        #expect(fixture.surface.presentedLists.first?.count == 4)
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Cmd+Tab (4 entries)"
                    + "; gathered on the spot (no list held yet)",
            ]
        )
    }

    /// The panel is not up yet, so a second press finds `isPresented` false
    /// and takes the same path as the first.
    ///
    /// The two presses are given different combinations because that is what
    /// separates "turned away" from "quietly took over": either way one panel
    /// appears and one line is written, and only the name in that line says
    /// which press it belongs to.
    @Test func aPressDuringTheWaitChangesNothing() async {
        let fake = HeldGather(entryCount: 4)
        let fixture = Fixture(store: storeHoldingNothing(fake))

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        await fake.waitUntilCalled()
        fixture.presenter.handleHotkey(.reverse, deliveryDelay: nil)

        fake.finish()
        await settle()

        #expect(fake.callCount == 1)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.dismissCount == 0)
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Cmd+Tab (4 entries)"
                    + "; gathered on the spot (no list held yet)",
            ]
        )
    }

    /// Turning to another application while the list is still coming means the
    /// panel is no longer wanted. Arriving late, it would land on top of
    /// whatever the user had moved to.
    @Test func anActivationDuringTheWaitCallsThePanelOff() async {
        let fake = HeldGather(entryCount: 4)
        let fixture = Fixture(store: storeHoldingNothing(fake))

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        await fake.waitUntilCalled()
        fixture.presenter.handleActivation(of: otherProcess)

        fake.finish()
        await settle()

        #expect(fixture.surface.presentedLists.isEmpty)
        // Nothing was on screen, so nothing was taken off it either.
        #expect(fixture.surface.dismissCount == 0)
        #expect(fixture.log.lines.isEmpty)
    }

    /// The wait that was called off must not leave the next press waiting on
    /// something that is never coming.
    @Test func aPressAfterAWaitWasCalledOffWorksNormally() async {
        let fake = HeldGather(entryCount: 4)
        let fixture = Fixture(store: storeHoldingNothing(fake))

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        await fake.waitUntilCalled()
        fixture.presenter.handleActivation(of: otherProcess)
        fake.finish()
        await settle()

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        await settle()

        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.log.lines.count == 1)
    }

    /// A press landing between the call-off and the list still has to be
    /// answered, and the panel belongs to that second press rather than to the
    /// one the user abandoned. `aPressAfterAWaitWasCalledOffWorksNormally` cannot
    /// reach that window: it presses once the list has arrived, by which time
    /// nothing is waiting and the press is answered whatever came before it.
    @Test func aPressAfterACallOffButBeforeTheListArrivesIsStillAnswered() async {
        let fake = HeldGather(entryCount: 4)
        let fixture = Fixture(store: storeHoldingNothing(fake))

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        await fake.waitUntilCalled()
        fixture.presenter.handleActivation(of: otherProcess)
        fixture.presenter.handleHotkey(.reverse, deliveryDelay: nil)

        fake.finish()
        await settle()

        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.presentedLists.first?.count == 4)
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Shift+Cmd+Tab (4 entries)"
                    + "; gathered on the spot (no list held yet)",
            ]
        )
    }
}
