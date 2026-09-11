@testable import Lanterna
import Testing

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
}
