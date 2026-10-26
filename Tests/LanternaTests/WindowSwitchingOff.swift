@testable import Lanterna

/// A shorthand for suites that exercise the default path. Kept in the test
/// target so production code always hands over the policy it read.
extension WindowSwitching {
  /// The commit switches off: the default path, with no notes.
  func switchTo(_ target: ActivationTarget) -> ActivationOutcome {
    switchTo(target, policy: .off).outcome
  }
}
