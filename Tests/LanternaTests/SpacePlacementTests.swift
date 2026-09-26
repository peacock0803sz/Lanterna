import Foundation
@testable import Lanterna
import PrivateAPIs
import Testing

/// The other-Space decision, fed the shapes the window server answers with
/// but none of its answers: nothing here depends on the Spaces this machine
/// happens to have.
struct SpacePlacementTests {
    private func display(currentSpace: CGSSpaceID) -> [String: Any] {
        ["Current Space": ["id64": NSNumber(value: currentSpace)]]
    }

    // MARK: - One window against the shown Spaces

    @Test func aWindowOnlyOnAHiddenSpaceIsElsewhere() {
        #expect(SpacePlacement.isOnOtherSpace(windowSpaces: [7], currentSpaces: [3]))
    }

    @Test func aWindowOnTheShownSpaceIsNotElsewhere() {
        #expect(!SpacePlacement.isOnOtherSpace(windowSpaces: [3], currentSpaces: [3]))
    }

    /// No Space at all is what an unknown window answers, and unknown never
    /// hides.
    @Test func anEmptyAnswerIsNotElsewhere() {
        #expect(!SpacePlacement.isOnOtherSpace(windowSpaces: [], currentSpaces: [3]))
    }

    // MARK: - Fullscreen via Space type

    @Test func aWindowOnlyOnAFullscreenSpaceReadsFullscreen() {
        #expect(SpacePlacement.isFullscreen(windowSpaces: [122], fullscreenSpaces: [122]))
    }

    @Test func aWindowOnADesktopSpaceIsNotFullscreen() {
        #expect(!SpacePlacement.isFullscreen(windowSpaces: [7], fullscreenSpaces: [122]))
        #expect(!SpacePlacement.isFullscreen(windowSpaces: [5, 7], fullscreenSpaces: [122]))
    }

    @Test func anEmptySpaceAnswerIsNeverFullscreen() {
        #expect(!SpacePlacement.isFullscreen(windowSpaces: [], fullscreenSpaces: [122]))
        #expect(!SpacePlacement.isFullscreen(windowSpaces: [122], fullscreenSpaces: []))
    }

    /// A window on every Space lists the shown one among the rest.
    @Test func aWindowOnEverySpaceIsNotElsewhere() {
        #expect(!SpacePlacement.isOnOtherSpace(windowSpaces: [3, 7, 9], currentSpaces: [3]))
    }

    /// Without a shown Space nothing can be compared, so nothing is elsewhere.
    @Test func noKnownCurrentSpaceLeavesEveryWindowInPlace() {
        #expect(!SpacePlacement.isOnOtherSpace(windowSpaces: [7], currentSpaces: []))
    }

    /// With two displays, a window on the second display's shown Space is in
    /// view even though the first display shows another one.
    @Test func aWindowShownOnTheSecondDisplayIsNotElsewhere() {
        let current = SpacePlacement.currentSpaces(from: [
            display(currentSpace: 3),
            display(currentSpace: 12),
        ])
        #expect(!SpacePlacement.isOnOtherSpace(windowSpaces: [12], currentSpaces: current))
        #expect(SpacePlacement.isOnOtherSpace(windowSpaces: [4], currentSpaces: current))
    }

    // MARK: - Reading the displays

    @Test func everyDisplayContributesItsShownSpace() {
        let current = SpacePlacement.currentSpaces(from: [
            display(currentSpace: 3),
            display(currentSpace: 12),
        ])
        #expect(current == [3, 12])
    }

    /// Space ids are 64-bit; one past 32 bits must survive the reading whole.
    @Test func aLargeSpaceIDIsReadWhole() {
        let large: CGSSpaceID = 1 << 40
        #expect(SpacePlacement.currentSpaces(from: [display(currentSpace: large)]) == [large])
    }

    /// A display entry that names no current Space, or names it in a shape
    /// that is not a number, adds nothing rather than a made-up id.
    @Test func aDisplayWithoutAReadableCurrentSpaceAddsNothing() {
        let current = SpacePlacement.currentSpaces(from: [
            [:],
            ["Current Space": ["id64": "3"]],
            ["Current Space": "3"],
            display(currentSpace: 12),
        ])
        #expect(current == [12])
    }
}
