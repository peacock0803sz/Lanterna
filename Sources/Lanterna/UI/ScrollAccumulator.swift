// MARK: - ScrollAccumulator

/// Gathers scroll amounts until they earn whole selection steps.
///
/// A wheel notch and a trackpad's momentum arrive as wildly different
/// amounts. Small amounts gather here so fine scrolling moves the choice
/// one row at a time instead of jumping it: one step per whole unit,
/// keeping the remainder. Turning around throws the savings away, so a
/// hesitation never pays for a step in the other direction. Which way a
/// step goes and where the list edge stops it belong to the caller, which
/// drops unusable steps.
struct ScrollAccumulator: Equatable, Sendable {
  /// What one step costs, in scroll units.
  static let stepCost = 1.0

  /// The ungathered remainder, signed. Thrown away on reversal.
  var pending = 0.0

  /// Banks this amount and answers how many whole steps it earned,
  /// signed: positive for the next row, negative for the previous one.
  mutating func advance(by delta: Double) -> Int {
    if delta != 0, pending != 0, pending.side != delta.side {
      pending = 0
    }
    pending += delta
    let steps = Int(pending / Self.stepCost)
    pending -= Double(steps) * Self.stepCost
    return steps
  }
}

extension Double {
  /// The side of zero this value stands on: +1.0, -1.0, or zero itself.
  fileprivate var side: Double {
    self > 0 ? 1 : self < 0 ? -1 : 0
  }
}
