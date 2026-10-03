import CoreGraphics

/// The pointer position the appearance opened with, as a point.
///
/// A panel opens under the pointer more often than not, and the first
/// hover arrives without the pointer having moved at all. The opening
/// choice belongs to the keyboard until the pointer moves: while it sits
/// where it sat, hovers are dropped. Taken at the moment the panel goes
/// up — after the show delay fires, when one is set — and thrown away
/// with the appearance.
struct HoverAnchor: Equatable, Sendable {
  /// The snapshot to compare arrivals against.
  var point: CGPoint

  /// Whether a hover at this position counts. Exact equality: any move,
  /// however small, is a move.
  func shouldIgnore(current: CGPoint) -> Bool {
    current == point
  }
}
