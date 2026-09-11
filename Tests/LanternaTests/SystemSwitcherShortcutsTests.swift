import CoreGraphics
@testable import Lanterna
import Testing

private typealias Failure = SystemSwitcherShortcuts.Failure

/// Kept at file scope rather than inside the suite, so it does not count
/// against the suite's body.
private func failure(_ combination: HotkeyCombination, _ status: CGError = .failure) -> Failure {
    Failure(combination: combination, status: status)
}

/// The window-server calls cannot be exercised here — a real
/// `CGSSetSymbolicHotKeyEnabled` would change the developer's own machine — so
/// what is tested is the wording, which is all anyone gets. A run that could
/// not take the user's Cmd+Tab, or could not give it back, says so in one of
/// these lines and nowhere else, so they are pinned word by word.
@MainActor
struct SystemSwitcherShortcutsTests {
    /// The empty list is the ordinary case, and a line saying so every time
    /// would bury the ones that matter.
    @Test func neitherVerbWritesALineWhenNothingRefused() {
        #expect(SystemSwitcherShortcuts.summaryLine(disabling: []) == nil)
        #expect(SystemSwitcherShortcuts.summaryLine(restoring: []) == nil)
    }

    /// The number is the window server's own, printed back verbatim: nothing
    /// here knows what it means, and a reader chasing it needs the digits
    /// rather than a paraphrase.
    @Test func oneRefusalNamesTheCombinationAndItsError() {
        #expect(
            SystemSwitcherShortcuts.summaryLine(disabling: [failure(.forward)])
                == "could not disable the system's Cmd+Tab (error 1000)"
        )
    }

    /// Taking a shortcut and giving it back fail for different reasons and
    /// matter differently, so the line has to say which one happened.
    @Test func theVerbSaysWhichDirectionFailed() {
        let failures = [failure(.reverse)]
        #expect(
            SystemSwitcherShortcuts.summaryLine(disabling: failures)
                == "could not disable the system's Shift+Cmd+Tab (error 1000)"
        )
        #expect(
            SystemSwitcherShortcuts.summaryLine(restoring: failures)
                == "could not restore the system's Shift+Cmd+Tab (error 1000)"
        )
    }

    @Test func bothRefusalsAreJoinedInTheOrderTheyCame() {
        #expect(
            SystemSwitcherShortcuts.summaryLine(
                restoring: [failure(.forward), failure(.reverse, .illegalArgument)]
            )
                == "could not restore the system's Cmd+Tab (error 1000), "
                + "Shift+Cmd+Tab (error 1001)"
        )
    }
}
