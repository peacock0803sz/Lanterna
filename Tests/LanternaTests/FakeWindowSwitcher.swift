import Foundation
@testable import Lanterna

/// Records what the commit paths asked for and answers from a script.
///
/// For the exit, not for the seam: what the seam does with scripted answers
/// is `WindowSwitcherTests`' business. This one only proves which target each
/// appearance took and in which order, and that nothing else was taken.
///
/// Confined to the main actor by its callers: the arrays are unguarded, the
/// way `FakeApplication`'s records are, because switching stays synchronous
/// and nothing here is touched off the thread that took the row.
final class FakeWindowSwitcher: WindowSwitching, @unchecked Sendable {
    private(set) var targets: [ActivationTarget] = []
    /// Answers in order; an empty script means every take succeeded.
    var outcomes: [ActivationOutcome] = []

    func switchTo(_ target: ActivationTarget) -> ActivationOutcome {
        targets.append(target)
        return outcomes.isEmpty ? .switched : outcomes.removeFirst()
    }
}
