import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// The filter invocation seen from outside the presenter.
///
/// A file of its own for the reason `PanelPresenterCommitTests` is one: the
/// suite driving the narrowing is long enough that adding to it would put it
/// over the file limit. These cases drive the whole presenter through the
/// shared fixture instead, so they need nothing from that suite's doubles.
///
/// What the narrowing does with the rows is settled in `PanelFilterTests`.
/// What is settled here is everything around it: that the invocation shows
/// the panel with the filter on, that a plain appearance swallows typing,
/// and that closing drops the query for the next appearance.
@MainActor
struct FilterActivationTests {
    /// A plain appearance swallows typing: without the invocation, letters
    /// narrow nothing.
    @Test func typingWithoutTheInvocationNarrowsNothing() {
        let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        let letter = PanelKeystroke(
            keyCode: UInt16(kVK_ANSI_S),
            modifiers: [],
            isARepeat: false,
            characters: "s"
        )
        #expect(fixture.presenter.handleKeyStroke(letter) == .absorbed)
        #expect(fixture.surface.updatedLists.isEmpty)
        #expect(fixture.surface.presentedLists.last?.count == 12)
    }

    /// The invocation on a closed panel shows the whole list, and typing
    /// from there narrows it.
    @Test func invokingOnAClosedPanelShowsTheWholeList() {
        let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.last?.count == 12)
        let letter = PanelKeystroke(
            keyCode: UInt16(kVK_ANSI_S),
            modifiers: [],
            isARepeat: false,
            characters: "s"
        )
        #expect(fixture.presenter.handleKeyStroke(letter) == .absorbed)
        #expect((fixture.surface.updatedLists.last?.count ?? 12) < 12)
    }

    /// The invocation on an open panel keeps the list and the choice, and
    /// typing from there narrows it.
    @Test func invokingOnAnOpenPanelKeepsTheListAndTheChoice() {
        let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        let shown = fixture.surface.presentedLists.last?.map(\.id)
        let chosen = fixture.surface.presentedSelections.last
        fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.presentedSelections.last == chosen)
        let letter = PanelKeystroke(
            keyCode: UInt16(kVK_ANSI_S),
            modifiers: [],
            isARepeat: false,
            characters: "s"
        )
        #expect(fixture.presenter.handleKeyStroke(letter) == .absorbed)
        #expect((fixture.surface.updatedLists.last?.count ?? 12) < 12)
        #expect(shown?.count == 12)
    }

    /// Letting go of Command while filtering ends nothing: the panel stays
    /// up with no commit line, and narrowing goes on.
    @Test func releasingCommandWhileFilteringEndsNothing() {
        let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
        let letter = PanelKeystroke(
            keyCode: UInt16(kVK_ANSI_S),
            modifiers: [],
            isARepeat: false,
            characters: "s"
        )
        #expect(fixture.presenter.handleKeyStroke(letter) == .absorbed)
        fixture.presenter.handleCommandRelease()
        #expect(fixture.surface.isPresented)
        #expect(fixture.log.lines.filter { $0.hasPrefix("committed ") }.isEmpty)
        #expect((fixture.surface.updatedLists.last?.count ?? 12) < 12)
    }

    /// Filtering starts no watch: a further press closes the panel the way
    /// a watchless appearance always closes it.
    @Test func aFurtherPressClosesTheFilteringPanel() {
        let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(!fixture.surface.isPresented)
    }

    /// Closing drops the query: the next appearance starts over the whole list.
    @Test func closingDropsTheQueryForTheNextAppearance() {
        let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
        let letter = PanelKeystroke(
            keyCode: UInt16(kVK_ANSI_S),
            modifiers: [],
            isARepeat: false,
            characters: "s"
        )
        #expect(fixture.presenter.handleKeyStroke(letter) == .absorbed)
        let cancel = PanelKeystroke(keyCode: UInt16(kVK_ANSI_Period), modifiers: .command, isARepeat: false)
        #expect(fixture.presenter.handleKeyStroke(cancel) == .absorbed)
        #expect(!fixture.surface.isPresented)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.last?.count == 12)
    }
}
