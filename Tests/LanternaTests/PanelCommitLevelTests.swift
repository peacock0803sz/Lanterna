@testable import Lanterna
import Logging
import Testing

/// The levels beside the commit lines, split out the way long suites split:
/// `PanelPresenterCommitTests` reached the body-length limit, so the level
/// pinning for its lines lives here instead.
@MainActor
struct PanelCommitLevelTests {
    /// A presenter wired the way a run with a working monitor wires it.
    private func runningWithAMonitor(entryCount: Int = 12) -> Fixture {
        Fixture(entryCount: entryCount, closesOnCommandRelease: true)
    }

    /// A commit line is ordinary news: hidden by default, back when lowered.
    @Test func aCommitLineIsOrdinaryNews() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        #expect(
            fixture.log.entries.first(where: { $0.line.hasPrefix("committed ") })?.level == .info
        )
    }
}
