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
// swiftlint:disable:next no_unchecked_sendable - test-only; synchronous use confined to the taking thread
final class FakeWindowSwitcher: WindowSwitching, @unchecked Sendable {
  private(set) var targets = [ActivationTarget]()
  /// The switch values each take arrived with, in order.
  private(set) var policies = [ActivationPolicy]()
  /// Answers in order; an empty script means every take succeeded.
  var outcomes = [ActivationOutcome]()
  /// Whole reports in order; answers here win over the outcomes above.
  var reports = [ActivationReport]()

  func switchTo(_ target: ActivationTarget, policy: ActivationPolicy) -> ActivationReport {
    targets.append(target)
    policies.append(policy)
    if !reports.isEmpty {
      return reports.removeFirst()
    }
    let outcome = outcomes.isEmpty ? .switched : outcomes.removeFirst()
    return ActivationReport(outcome: outcome, reopen: nil, raiseAlone: nil)
  }
}
