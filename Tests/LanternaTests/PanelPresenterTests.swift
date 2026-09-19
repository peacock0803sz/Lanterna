import Darwin
@testable import Lanterna
import Testing

/// The tail every appearance line carries when the panel got the keyboard,
/// which is what the stand-in answers unless a case says otherwise. Named
/// rather than repeated, so that the cases below stay about what each of them
/// is for.
private let takingKeys = "; taking keys"

@MainActor
struct PanelPresenterTests {
    @Test func aPressPutsThePanelUpOnceWithTheListItWasGiven() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.presentedLists.first?.map(\.id) == fixture.windows.map(\.id))
        #expect(fixture.surface.isPresented)
    }

    /// Which row is chosen is the presenter's to say, and this is the only
    /// place it is said. The list used to arrive on its own and the view
    /// worked the row out from it; now the two travel together, and nothing
    /// downstream of `present` would notice an appearance that named no row
    /// or named the wrong one — the panel goes up either way, the same size,
    /// with the same rows, and the line written about it says the same thing.
    @Test func theFirstRowIsTheOneThePanelIsToldToDrawAsChosen() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedSelections == [fixture.windows.first?.id])
    }

    /// An empty list is the one input for which no row is the right answer,
    /// so it is the one case that cannot be folded into the above. Naming a
    /// row that is not there, or reaching for a stand-in id, would leave a
    /// highlight nothing could ever move off.
    @Test func anEmptyListLeavesThePanelWithNoRowChosen() {
        let fixture = Fixture(entryCount: 0)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.presentedSelections == [nil])
    }

    /// Every appearance asks for the keyboard, and asks once.
    ///
    /// The order is the assertion, not the count on its own. A window that is
    /// not on screen cannot become the key window, so asking before the panel
    /// is up would fail and the line would report a panel not taking keys
    /// while one sat there taking them — the count alone reads the same
    /// either way round.
    @Test func anAppearanceAsksThePanelForTheKeyboardOnceItIsUp() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.takeKeysCount == 1)
        #expect(
            fixture.surface.calls == [
                .present(selecting: fixture.windows.first?.id),
                .takeKeys,
            ]
        )
    }

    /// A panel that was refused the keyboard says so on its own line.
    ///
    /// Without this the phrase is a constant: the stand-in answers yes to
    /// every ask, so a presenter that reported the answer and one that wrote
    /// a hard-coded yes would read identically everywhere else in the suite.
    @Test func anAppearanceRefusedTheKeyboardSaysSoOnItsLine() {
        let fixture = Fixture(entryCount: 3)
        fixture.surface.takeKeysSucceeds = false
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Cmd+Tab (3 entries)"
                    + "; not taking keys (they reach the frontmost application)",
            ]
        )
    }

    /// The reading spans the press, so a clock that steps once per read gives
    /// the whole line a value the test chose.
    /// No note about gathering: the list was already held, which is what the
    /// note's absence is there to say.
    @Test func eachPressIsAccountedForByExactlyOneLine() {
        let fixture = Fixture(step: .microseconds(4800))
        fixture.presenter.handleHotkey(.forward, deliveryDelay: .microseconds(1900))
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Cmd+Tab (12 entries); delivery 1.9 ms"
                    + takingKeys,
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
                "panel shown 4.8 ms after Shift+Cmd+Tab (3 entries)" + takingKeys,
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
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Cmd+Tab (4 entries)" + takingKeys,
            ]
        )
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
                    + "; gathered on the spot (no list held yet)" + takingKeys,
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
    ///
    /// Two ticks rather than the one every other figure here carries. Every
    /// press reads the clock as it arrives, so the second one's reading falls
    /// inside the span the first is still measuring.
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
                "panel shown 9.6 ms after Cmd+Tab (4 entries)"
                    + "; gathered on the spot (no list held yet)" + takingKeys,
            ]
        )
    }

    /// Turning to another application while the list is still coming means the
    /// panel is no longer wanted. Arriving late, it would land on top of
    /// whatever the user had moved to.
    ///
    /// The press is written down as it goes. A release calls one off in just
    /// the same way and says so, and an activation that stayed quiet would
    /// leave someone counting keystrokes against the log a press short, with
    /// no way to tell whether it ever arrived.
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
        #expect(
            fixture.log.lines == [
                "called off the press waiting for its first list; "
                    + "the frontmost application changed",
            ]
        )
    }

    /// A notification naming this process touches neither the clock nor the
    /// slot, so the press comes out exactly as it would have with no
    /// notification at all: the same panel, the same line, and the same figure
    /// in it as a wait nobody interrupted.
    ///
    /// Pinning that is what fixes where the own-process guard goes. This case
    /// and `anActivationDuringTheWaitCallsThePanelOff` have to come out
    /// opposite, and only asserting both says so: with the guard dropped, or
    /// with the pending-press block moved above it, the panel the user asked
    /// for here would be thrown away and a call-off written down for a press
    /// nobody abandoned.
    @Test func thisProcessComingForwardDoesNotCallOffAPendingPress() async {
        let fake = HeldGather(entryCount: 4)
        let fixture = Fixture(store: storeHoldingNothing(fake))

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        await fake.waitUntilCalled()
        fixture.presenter.handleActivation(of: ownProcess)

        fake.finish()
        await settle()

        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.presentedLists.first?.count == 4)
        #expect(
            fixture.log.lines == [
                "panel shown 4.8 ms after Cmd+Tab (4 entries)"
                    + "; gathered on the spot (no list held yet)" + takingKeys,
            ]
        )
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
        #expect(
            fixture.log.lines == [
                "called off the press waiting for its first list; "
                    + "the frontmost application changed",
                "panel shown 4.8 ms after Cmd+Tab (4 entries)" + takingKeys,
            ]
        )
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
                "called off the press waiting for its first list; "
                    + "the frontmost application changed",
                "panel shown 4.8 ms after Shift+Cmd+Tab (4 entries)"
                    + "; gathered on the spot (no list held yet)" + takingKeys,
            ]
        )
    }
}
