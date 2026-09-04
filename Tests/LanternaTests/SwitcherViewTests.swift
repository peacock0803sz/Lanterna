@testable import Lanterna
import Testing

@MainActor
struct SwitcherViewTests {
    @Test func emptyListHasNoSelection() {
        #expect(SwitcherView(windows: []).selectedID == nil)
    }

    @Test func firstEntryIsSelected() {
        let windows = SampleWindows.standard()
        #expect(SwitcherView(windows: windows).selectedID == windows.first?.id)
    }
}
