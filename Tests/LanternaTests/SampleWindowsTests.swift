@testable import Lanterna
import Testing

/// The fixture is what the panel shows unless `--sample-count` asks for a
/// different length, so its variety is what makes the layout reviewable. These
/// checks pin that variety down.
@MainActor
struct SampleWindowsTests {
    /// Key for grouping rows by application: two rows count as the same
    /// application only when both the name and the bundle identifier match.
    private struct ApplicationKey: Hashable {
        let appName: String
        let bundleIdentifier: String?
    }

    private let windows = SampleWindows.standard()

    @Test func fixtureExceedsThePanelHeightCap() {
        #expect(windows.count >= 15)
        #expect(PanelMetrics.height(rowCount: windows.count) == PanelMetrics.maximumHeight)
    }

    @Test func fixtureRepeatsAnApplication() {
        let countsByApplication = Dictionary(grouping: windows) {
            ApplicationKey(appName: $0.appName, bundleIdentifier: $0.bundleIdentifier)
        }.mapValues(\.count)
        #expect(countsByApplication.values.contains { $0 >= 2 })
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

    /// The override cycles the templates, so ids have to come from the position
    /// rather than the content: 30 entries reuse every template twice.
    @Test(arguments: [0, 3, 30]) func overrideReturnsTheRequestedCountWithUniqueIDs(count: Int) {
        let windows = SampleWindows.make(count: count)
        #expect(windows.count == count)
        #expect(Set(windows.map(\.id)).count == count)
    }

    /// Fixture ids are synthesised, so they must stay clear of the ids the
    /// window server hands out to real windows.
    @Test func fixtureIDsSitInTheReservedRange() {
        #expect(windows.allSatisfy { $0.id.windowID >= 1_000_000_000 })
        #expect(SampleWindows.make(count: 30).allSatisfy { $0.id.windowID >= 1_000_000_000 })
    }

    @Test func overrideCyclesTheFixtureContent() {
        #expect(SampleWindows.make(count: 3).map(\.appName) == windows.prefix(3).map(\.appName))

        // One past the fixture length wraps back to the first template.
        let wrapped = SampleWindows.make(count: windows.count + 1)
        #expect(wrapped.last?.appName == windows.first?.appName)
    }
}
