@testable import Lanterna
import Testing

@MainActor
struct SwitcherViewTests {
    /// The view draws whichever row it is told to, and nothing about the list
    /// decides that any more. Said by handing in a row that is not the first
    /// one: with the old derivation in place this could only ever have read
    /// back the first, so the case is one the view could not have passed
    /// before it was given the choice from outside.
    @Test func theChosenRowIsTheOneItWasHanded() {
        let windows = SampleWindows.standard()
        let third = windows[2].id
        #expect(
            SwitcherView(windows: windows, selectedID: third, appearanceToken: 0, query: "", filterActive: false)
                .selectedID == third
        )
    }

    /// Nothing chosen is a state the view has to be able to draw: the panel
    /// goes up over an empty list whenever the window enumeration comes back
    /// with nothing.
    @Test func nothingNeedBeChosen() {
        #expect(
            SwitcherView(
                windows: SampleWindows.standard(),
                selectedID: nil,
                appearanceToken: 0,
                query: "",
                filterActive: false
            ).selectedID == nil
        )
        #expect(
            SwitcherView(windows: [], selectedID: nil, appearanceToken: 1, query: "", filterActive: false)
                .selectedID == nil
        )
    }
}
