@testable import Lanterna
import Testing

/// The fixture is the only data the mock panel shows, so its variety is what
/// makes the layout reviewable. These checks pin that variety down.
@MainActor
struct SampleWindowsTests {
    private let windows = SampleWindows.standard()

    @Test func fixtureExceedsThePanelHeightCap() {
        #expect(windows.count >= 15)
        #expect(PanelMetrics.height(rowCount: windows.count) == PanelMetrics.maximumHeight)
    }

    @Test func fixtureRepeatsAnApplication() {
        let countsByApp = Dictionary(grouping: windows, by: \.appName).mapValues(\.count)
        #expect(countsByApp.values.contains { $0 >= 2 })
    }

    @Test func fixtureCoversTruncation() {
        #expect(windows.contains { $0.windowTitle.count > 80 })
        #expect(windows.contains { $0.appName.count > 20 })
    }

    @Test func fixtureCoversTheMissingApplicationCase() {
        #expect(windows.contains { $0.bundleIdentifier == "com.example.lanterna.uninstalled" })
    }

    @Test func fixtureIncludesAnAlwaysInstalledApplication() {
        #expect(windows.contains { $0.bundleIdentifier == "com.apple.finder" })
    }

    @Test func everyEntryHasATitleAndAnApplicationName() {
        #expect(windows.allSatisfy { !$0.appName.isEmpty && !$0.windowTitle.isEmpty })
    }

    @Test(arguments: [0, 3, 30]) func overrideReturnsTheRequestedCountWithUniqueIDs(count: Int) {
        let windows = SampleWindows.make(count: count)
        #expect(windows.count == count)
        #expect(Set(windows.map(\.id)).count == count)
    }
}
