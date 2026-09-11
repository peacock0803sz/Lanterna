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

/// Keeps the lines the presenter writes, so a test can read them back.
@MainActor
private final class DiagnosticsLog {
    private(set) var lines: [String] = []

    func write(_ line: String) {
        lines.append(line)
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

    init(entryCount: Int = 12, step: Duration = .microseconds(4800)) {
        let surface = FakeSurface()
        let log = DiagnosticsLog()
        let clock = SteppingClock(step: step)
        let windows = SampleWindows.make(count: entryCount)
        presenter = PanelPresenter(
            surface: surface,
            gather: { windows },
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
    @Test func eachPressIsAccountedForByExactlyOneLine() {
        let fixture = Fixture(step: .microseconds(4800))
        fixture.presenter.handleHotkey(.forward, deliveryDelay: .microseconds(1900))
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Cmd+Tab (12 entries); delivery 1.9 ms"
                    + "; gathered on the spot (no list held yet)",
            ]
        )
    }

    @Test func theReverseCombinationTakesTheSamePath() {
        let fixture = Fixture(entryCount: 3)
        fixture.presenter.handleHotkey(.reverse, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.presentedLists.first?.count == 3)
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Shift+Cmd+Tab (3 entries)"
                    + "; gathered on the spot (no list held yet)",
            ]
        )
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
