@testable import Lanterna

/// Answers badge reads from a script and records each deadline it was given.
@MainActor
final class FakeDockBadgeReader: DockBadgeReading {
  /// Readings in order; an empty script answers an empty, finished read.
  var readings = [BadgeReading]()
  private(set) var deadlines = [Duration]()

  var readCount: Int {
    deadlines.count
  }

  func read(deadline: Duration) -> BadgeReading {
    deadlines.append(deadline)
    if !readings.isEmpty {
      return readings.removeFirst()
    }
    return BadgeReading(badges: .none, outcome: .read, elapsed: .zero)
  }
}
