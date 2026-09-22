@testable import Lanterna
import Testing

/// What the panel does when key presses stop reaching it.
///
/// A file of its own for the reason `PanelExitTests` is one: the suites this
/// would have joined are already long enough that adding to them would put
/// them over the file limit. The doubles come from `TestSupport`, so every
/// file driving the presenter drives the same fakes.
///
/// A loss is staged through the one seam the stand-in offers: `isTakingKeys`
/// flipped by hand, and `takeKeysSucceeds` deciding whether the taking-back
/// answers. Waiting is done by yielding until something happened rather than
/// by sleeping a fixed span — every test here shares the main actor, so a
/// fixed sleep passes alone and fails in the full suite.
@MainActor
struct KeyStatusWatchTests {
    /// Yields until the condition holds, however many turns that takes. Not
    /// a timeout: a condition that never comes true simply falls through,
    /// and the assertions below say so.
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0 ..< 10000 {
            if condition() {
                return
            }
            await Task.yield()
        }
    }

    /// A loss is answered with an attempt, and the panel stays up while the
    /// answer is pending. The count tells the attempt from the asking that
    /// put the panel up: one for the appearance, one for the loss.
    @Test func aLossIsAnsweredWithOneAttemptWhileThePanelStaysUp() async {
        let fixture = Fixture(entryCount: 3)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.surface.isTakingKeys = false

        await waitUntil { fixture.surface.takeKeysCount >= 2 }

        #expect(fixture.surface.takeKeysCount == 2)
        #expect(fixture.surface.isPresented)
    }

    /// A taking-back says so on exactly one line, and the panel stays up.
    /// The figure runs from the previous look — the earliest the loss could
    /// have happened — which is the appearance's own clock read: two steps
    /// on from it by the time the line is written.
    @Test func aTakingBackWritesOneLineAndLeavesThePanelUp() async {
        let fixture = Fixture(entryCount: 3)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.surface.isTakingKeys = false

        await waitUntil {
            fixture.log.lines.contains { $0.hasPrefix("panel stopped taking keys;") }
        }

        #expect(fixture.surface.isPresented)
        #expect(fixture.surface.isTakingKeys)
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Cmd+Tab (3 entries); taking keys",
                "panel stopped taking keys; taken back 9.6 ms later",
            ]
        )
    }

    /// Three failures in a row close the panel with the tidying-up wording,
    /// and nothing else is written: no taking-back line for a loss that was
    /// never mended, and no second reason alongside the first.
    @Test func threeFailuresCloseThePanelWithOneReason() async {
        let fixture = Fixture(entryCount: 3)
        fixture.surface.takeKeysSucceeds = false
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        await waitUntil { !fixture.surface.isPresented }

        #expect(fixture.surface.dismissCount == 1)
        #expect(fixture.surface.takeKeysCount == 4)
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Cmd+Tab (3 entries)"
                    + "; not taking keys (they reach the frontmost application)",
                "panel hidden (stopped taking keys)",
            ]
        )
    }

    /// Repeated losses spend the appearance's answers even when each taking-back
    /// succeeds. The fourth loss finds the budget exhausted, so it closes the
    /// panel without a fourth attempt: taking the keyboard back indefinitely
    /// within one appearance is what the budget is there to stop.
    @Test func repeatedLossesSpendTheBudgetAndCloseWithoutAnotherAttempt() async {
        let fixture = Fixture(entryCount: 3)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        for expectedCount in 2 ... 4 {
            fixture.surface.isTakingKeys = false
            await waitUntil { fixture.surface.takeKeysCount >= expectedCount }
        }
        #expect(fixture.surface.takeKeysCount == 4)
        #expect(fixture.surface.isPresented)

        fixture.surface.isTakingKeys = false
        await waitUntil { !fixture.surface.isPresented }

        #expect(fixture.surface.dismissCount == 1)
        #expect(fixture.surface.takeKeysCount == 4)
        #expect(
            fixture.log.lines.filter { $0.hasPrefix("panel stopped taking keys;") }.count == 3
        )
    }

    /// A panel that lost the keyboard never stays up swallowing keystrokes.
    /// Either the taking-back mends it, or it comes down — and once down, a
    /// keystroke goes on to whatever would have had it instead of into a
    /// panel that answers nothing.
    @Test func aPanelThatLostTheKeyboardNeverStaysUpAnsweringNothing() async {
        let fixture = Fixture(entryCount: 3)
        fixture.surface.takeKeysSucceeds = false
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        await waitUntil { !fixture.surface.isPresented }

        let keystroke = PanelKeystroke(keyCode: 0, modifiers: [], isARepeat: false)
        #expect(fixture.presenter.handleKeyStroke(keystroke) == .passedThrough)
        #expect(fixture.log.lines.filter { $0.hasPrefix("panel stopped taking keys;") }.isEmpty)
    }
}
